#!/bin/bash

set -e  # Exit on any error

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required tools are installed
for cmd in kubectl az; do
    if ! command -v $cmd &> /dev/null; then
        log_error "$cmd is required but not installed."
        exit 1
    fi
done

# Get PostgreSQL connection details
log_header "RETRIEVING CONNECTION DETAILS"

# Key Vault configuration
KV_NAME="airqualitykubedbkvdev"  # Key Vault name from your terraform code
RESOURCE_GROUP="air-quality-db-dev"  # Resource group where Key Vault is located

# Get credentials from Azure Key Vault
log_info "Getting credentials from Azure Key Vault..."

# Get PostgreSQL connection details from Key Vault
POSTGRES_HOST=$(az keyvault secret show --vault-name "$KV_NAME" --name "airflow-postgres-host" --query value -o tsv 2>/dev/null || echo "air-quality-kube-airflow-pg-dev.postgres.database.azure.com")
POSTGRES_USER=$(az keyvault secret show --vault-name "$KV_NAME" --name "airflow-postgres-user" --query value -o tsv 2>/dev/null || echo "airflow_admin")
POSTGRES_PASSWORD=$(az keyvault secret show --vault-name "$KV_NAME" --name "airflow-postgres-password" --query value -o tsv)
POSTGRES_DB="airflow"

if [ -z "$POSTGRES_PASSWORD" ]; then
    log_error "Could not retrieve PostgreSQL password from Key Vault"
    exit 1
fi

log_info "Connection details:"
echo "Host: $POSTGRES_HOST"
echo "User: $POSTGRES_USER"
echo "Database: $POSTGRES_DB"

# First, check if we can connect to the PostgreSQL server
log_header "CHECKING DATABASE CONNECTION"

log_info "Creating temporary pod to check PostgreSQL connection..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: db-check
  labels:
    app: db-check
spec:
  containers:
  - name: postgresql-client
    image: postgres:13
    command: ["sleep", "300"]
    resources:
      requests:
        memory: "128Mi"
        cpu: "100m"
      limits:
        memory: "256Mi"
        cpu: "200m"
  restartPolicy: Never
EOF

# Wait for pod to be ready
log_info "Waiting for pod to be ready..."
kubectl wait --for=condition=ready pod/db-check --timeout=60s || {
    log_error "Pod did not start within timeout"
    kubectl delete pod db-check --force --grace-period=0
    exit 1
}

# Test connection
log_info "Testing database connection..."
kubectl exec db-check -- bash -c "PGPASSWORD='$POSTGRES_PASSWORD' psql -h $POSTGRES_HOST -U $POSTGRES_USER -d postgres -c '\l'" || {
    log_error "Could not connect to PostgreSQL server"
    
    # Try with sslmode=require explicitly
    log_info "Trying with sslmode=require..."
    kubectl exec db-check -- bash -c "PGPASSWORD='$POSTGRES_PASSWORD' psql -h $POSTGRES_HOST -U $POSTGRES_USER -d postgres -c '\l' sslmode=require" || {
        log_error "Could not connect with sslmode=require. Check if the PostgreSQL server is accessible."
        kubectl delete pod db-check --force --grace-period=0
        exit 1
    }
}

log_info "Connection successful! Creating airflow database if it doesn't exist..."
kubectl exec db-check -- bash -c "PGPASSWORD='$POSTGRES_PASSWORD' psql -h $POSTGRES_HOST -U $POSTGRES_USER -d postgres -c 'CREATE DATABASE airflow;'" || {
    log_info "Airflow database might already exist. Continuing..."
}

# Clean up check pod
kubectl delete pod db-check --grace-period=0 --force

# Run an initialization pod to set up the Airflow database
log_header "INITIALIZING AIRFLOW DATABASE"

log_info "Creating a pod with higher memory limits to run Airflow database initialization..."

# Create a temporary pod with Airflow image and higher memory limits
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: airflow-db-init
  labels:
    app: airflow-db-init
spec:
  containers:
  - name: airflow
    image: apache/airflow:2.8.1
    command: ["sleep", "600"]
    env:
    - name: AIRFLOW__DATABASE__SQL_ALCHEMY_CONN
      value: postgresql+psycopg2://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:5432/${POSTGRES_DB}?sslmode=require
    - name: AIRFLOW__CORE__FERNET_KEY
      value: UKMzEm3yIuL_GiAiRPl0sMRosgSY25Q9At-0LjqXpWs=
    - name: AIRFLOW__LOGGING__LOGGING_LEVEL
      value: INFO
    resources:
      requests:
        memory: "1Gi"
        cpu: "500m"
      limits:
        memory: "2Gi"
        cpu: "1000m"
  restartPolicy: Never
EOF

log_info "Waiting for initialization pod to be ready..."
kubectl wait --for=condition=ready pod/airflow-db-init --timeout=60s || {
    log_error "Initialization pod did not start within timeout"
    kubectl delete pod airflow-db-init --force --grace-period=0
    exit 1
}

# Split the initialization process into smaller steps to make it more reliable
log_info "Running Airflow database check..."
kubectl exec airflow-db-init -- bash -c "airflow db check" || {
    log_warn "Database connection check failed. This may be normal if the database is not yet initialized."
}

log_info "Initializing Airflow database (Step 1/2: Running db init)..."
kubectl exec airflow-db-init -- bash -c "airflow db init" || {
    log_error "Failed to initialize Airflow database"
    kubectl logs airflow-db-init
    kubectl delete pod airflow-db-init --force --grace-period=0
    exit 1
}

log_info "Initializing Airflow database (Step 2/2: Running db upgrade)..."
kubectl exec airflow-db-init -- bash -c "airflow db upgrade" || {
    log_error "Failed to upgrade Airflow database schema"
    kubectl logs airflow-db-init
    kubectl delete pod airflow-db-init --force --grace-period=0
    exit 1
}

# Create admin user with a fixed password for predictability, then update it later if needed
log_info "Creating admin user..."
ADMIN_USER="admin"
ADMIN_PASSWORD=$(openssl rand -base64 12)
ADMIN_EMAIL="admin@example.com"

kubectl exec airflow-db-init -- bash -c "airflow users create \
  --username $ADMIN_USER \
  --password $ADMIN_PASSWORD \
  --firstname Admin \
  --lastname User \
  --role Admin \
  --email $ADMIN_EMAIL" || {
    log_warn "Failed to create admin user. It might already exist."
}

# Display admin credentials
log_info "Admin user:"
echo "Username: $ADMIN_USER"
echo "Password: $ADMIN_PASSWORD"
echo "Email: $ADMIN_EMAIL"

# Store admin credentials in Key Vault for future use
log_info "Storing admin credentials in Key Vault..."
az keyvault secret set --vault-name "$KV_NAME" --name "airflow-admin-user" --value "$ADMIN_USER" || log_warn "Failed to store admin username in Key Vault"
az keyvault secret set --vault-name "$KV_NAME" --name "airflow-admin-password" --value "$ADMIN_PASSWORD" || log_warn "Failed to store admin password in Key Vault"
az keyvault secret set --vault-name "$KV_NAME" --name "airflow-admin-email" --value "$ADMIN_EMAIL" || log_warn "Failed to store admin email in Key Vault"

# Clean up
log_info "Cleaning up initialization pod..."
kubectl delete pod airflow-db-init --force --grace-period=0

log_header "DATABASE INITIALIZATION COMPLETE"
log_info "Use the airflow-values.yaml file for your deployment"
log_info "Then run: ./deploy-airflow.sh"