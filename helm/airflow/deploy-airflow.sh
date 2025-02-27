#!/bin/bash

set -e  # Exit on any error

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Helper functions
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
for cmd in kubectl helm az; do
    if ! command -v $cmd &> /dev/null; then
        log_error "$cmd is required but not installed."
        exit 1
    fi
done

# Environment Variables
AIRFLOW_NAME="airflow-cluster"
AIRFLOW_NAMESPACE="airflow"
KV_NAME="airqualitykubedbkvdev"  # Key Vault name from your terraform code
RESOURCE_GROUP="air-quality-db-dev"  # Resource group where Key Vault is located

log_info "Getting credentials from Azure Key Vault..."

# Get PostgreSQL connection details from Key Vault
POSTGRES_HOST=$(az keyvault secret show --vault-name "$KV_NAME" --name "airflow-postgres-host" --query value -o tsv 2>/dev/null || echo "air-quality-kube-airflow-pg-dev.postgres.database.azure.com")
POSTGRES_USER=$(az keyvault secret show --vault-name "$KV_NAME" --name "airflow-postgres-user" --query value -o tsv 2>/dev/null || echo "airflow_admin")
POSTGRES_PASSWORD=$(az keyvault secret show --vault-name "$KV_NAME" --name "airflow-postgres-password" --query value -o tsv)
FERNET_KEY=$(python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
WEBSERVER_SECRET_KEY=$(python -c "import secrets; print(secrets.token_hex(32))")

# If the secrets don't exist, create them
if [ -z "$POSTGRES_HOST" ]; then
    log_warn "PostgreSQL host secret not found in Key Vault. Using default FQDN."
    POSTGRES_HOST="air-quality-kube-airflow-pg-dev.postgres.database.azure.com"
    
    # Store the secret in Key Vault for future use
    az keyvault secret set --vault-name "$KV_NAME" --name "airflow-postgres-host" --value "$POSTGRES_HOST"
fi

if [ -z "$POSTGRES_USER" ]; then
    log_warn "PostgreSQL user secret not found in Key Vault. Using default user."
    POSTGRES_USER="airflow_admin"
    
    # Store the secret in Key Vault for future use
    az keyvault secret set --vault-name "$KV_NAME" --name "airflow-postgres-user" --value "$POSTGRES_USER"
fi

# Get admin credentials from Key Vault
AIRFLOW_ADMIN_USER=$(az keyvault secret show --vault-name "$KV_NAME" --name "airflow-admin-user" --query value -o tsv 2>/dev/null || echo "admin")
AIRFLOW_ADMIN_PASSWORD=$(az keyvault secret show --vault-name "$KV_NAME" --name "airflow-admin-password" --query value -o tsv 2>/dev/null || echo "admin")
AIRFLOW_ADMIN_EMAIL=$(az keyvault secret show --vault-name "$KV_NAME" --name "airflow-admin-email" --query value -o tsv 2>/dev/null || echo "admin@example.com")

log_info "Using admin credentials from Key Vault:"
echo "Username: $AIRFLOW_ADMIN_USER"
echo "Password: (retrieved from Key Vault)"
echo "Email: $AIRFLOW_ADMIN_EMAIL"

# Get Airflow Managed Identity Client ID (if you're using Workload Identity)
AIRFLOW_MANAGED_IDENTITY_CLIENT_ID=$(az identity show \
    --name air-quality-kube-airflow-identity \
    --resource-group air-quality-kube-dev \
    --query 'clientId' -o tsv 2>/dev/null || echo "")

# Create Airflow namespace if it doesn't exist
log_info "Creating Airflow namespace..."
kubectl create namespace "$AIRFLOW_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Create Kubernetes secrets for PostgreSQL and admin credentials
log_info "Creating Kubernetes secrets for PostgreSQL and admin credentials..."
kubectl create secret generic airflow-postgres-secret \
    --namespace "$AIRFLOW_NAMESPACE" \
    --from-literal=postgres-password="$POSTGRES_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic airflow-admin-secret \
    --namespace "$AIRFLOW_NAMESPACE" \
    --from-literal=admin-password="$AIRFLOW_ADMIN_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -

# Create temporary values file with replaced placeholders
log_info "Creating values file with credentials..."
cp airflow-values.yaml airflow-values-with-creds.yaml

# Replace placeholders in the values file
sed -i "s|\${POSTGRES_HOST}|$POSTGRES_HOST|g" airflow-values-with-creds.yaml
sed -i "s|\${POSTGRES_USER}|$POSTGRES_USER|g" airflow-values-with-creds.yaml
sed -i "s|\${AIRFLOW_ADMIN_USER}|$AIRFLOW_ADMIN_USER|g" airflow-values-with-creds.yaml
sed -i "s|\${AIRFLOW_ADMIN_PASSWORD}|$AIRFLOW_ADMIN_PASSWORD|g" airflow-values-with-creds.yaml
sed -i "s|\${AIRFLOW_ADMIN_EMAIL}|$AIRFLOW_ADMIN_EMAIL|g" airflow-values-with-creds.yaml
sed -i "s|\${WEBSERVER_SECRET_KEY}|$WEBSERVER_SECRET_KEY|g" airflow-values-with-creds.yaml
sed -i "s|\${FERNET_KEY}|$FERNET_KEY|g" airflow-values-with-creds.yaml

# Replace Workload Identity Client ID if available
if [ ! -z "$AIRFLOW_MANAGED_IDENTITY_CLIENT_ID" ]; then
    sed -i "s|\${AIRFLOW_MANAGED_IDENTITY_CLIENT_ID}|$AIRFLOW_MANAGED_IDENTITY_CLIENT_ID|g" airflow-values-with-creds.yaml
else
    # If no managed identity is available, disable workload identity
    sed -i "s|workloadIdentity:|workloadIdentity:\n  enabled: false|g" airflow-values-with-creds.yaml
    sed -i "/\${AIRFLOW_MANAGED_IDENTITY_CLIENT_ID}/d" airflow-values-with-creds.yaml
fi

# Add Airflow helm repo if it doesn't exist
log_info "Adding Airflow Helm repository..."
helm repo add airflow-stable https://airflow-helm.github.io/charts || true
helm repo update

# Delete existing release if it exists
if helm status "$AIRFLOW_NAME" -n "$AIRFLOW_NAMESPACE" &> /dev/null; then
    log_warn "Existing Airflow release found. Deleting to allow clean installation..."
    helm uninstall "$AIRFLOW_NAME" -n "$AIRFLOW_NAMESPACE"
    
    # Wait for resources to be deleted
    log_info "Waiting for resources to be deleted..."
    sleep 10
    
    # Force delete pods if necessary
    kubectl delete pods -n "$AIRFLOW_NAMESPACE" --all --force --grace-period=0 || true
    sleep 5
fi

# Install Airflow using Helm with longer timeout
log_info "Installing Airflow using Helm chart..."
helm install "$AIRFLOW_NAME" airflow-stable/airflow \
    --namespace "$AIRFLOW_NAMESPACE" \
    --version "8.8.0" \
    --values airflow-values-with-creds.yaml \
    --timeout 10m

# Wait for Airflow webserver to be ready
log_info "Waiting for Airflow webserver to be ready..."
kubectl wait --for=condition=available --timeout=600s deployment/$AIRFLOW_NAME-web -n $AIRFLOW_NAMESPACE || {
    log_warn "Webserver deployment did not become ready within timeout."
    log_info "Checking webserver pod logs:"
    kubectl logs -l component=web -n "$AIRFLOW_NAMESPACE" --tail=50
}

log_info "Airflow has been deployed successfully!"
log_info "Run the following command to access the Airflow UI:"
echo "kubectl port-forward svc/$AIRFLOW_NAME-web 8080:8080 -n $AIRFLOW_NAMESPACE"
log_info "Then open your browser to: http://localhost:8080"
log_info "Username: $AIRFLOW_ADMIN_USER"
log_info "Password: $AIRFLOW_ADMIN_PASSWORD"

# Clean up temporary files
rm -f airflow-values-with-creds.yaml