#!/bin/bash

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
DELETE_WAREHOUSE=false
ENVIRONMENT="dev"

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

check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 is required but not installed. Please install it first."
        exit 1
    fi
}

# Check required tools
check_command "terraform"
check_command "terragrunt"
check_command "az"
check_command "helm"
check_command "kubectl"

# Verify Azure CLI login
az account show &> /dev/null || {
    log_error "Not logged in to Azure. Please run 'az login' first."
    exit 1
}

# Initialize working directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

wait_for_lock(){
    max_retries=5
    retry_count=0
    while [ $retry_count -lt $max_retries ]; do
        if az storage blob show \
            --container-name tfstate \
            --name "terraform.tfstate.tflock" \
            --account-name aqtfstatedev \
            2>/dev/null; then
            log_info "State is still locked, waiting..."
            sleep 30
            retry_count=$((retry_count + 1))
        else
            break
        fi
    done
}

wait_for_postgres() {
    log_info "Waiting for PostgreSQL to be ready..."
    RETRIES=0
    MAX_RETRIES=30
    until az postgres flexible-server show \
        --name air-quality-kube-airflow-pg-${ENVIRONMENT} \
        --resource-group air-quality-db-${ENVIRONMENT} \
        --query 'state' -o tsv | grep -q "Ready"; do
        if [ $RETRIES -eq $MAX_RETRIES ]; then
            log_error "Timed out waiting for PostgreSQL"
            exit 1
        fi
        RETRIES=$((RETRIES+1))
        echo "Waiting... ($RETRIES/$MAX_RETRIES)"
        sleep 10
    done
    log_info "PostgreSQL is ready!"
}

# Clean up data warehouse resources
clean_data_warehouse() {
    if [ "$DELETE_WAREHOUSE" = true ]; then
        log_info "Cleaning up existing data-warehouse resources..."
        
        # Set up variables
        PREFIX="air-quality-kube"
        KV_NAME="${PREFIX}dbkv${ENVIRONMENT}"
        KV_NAME=${KV_NAME//-/}  # Remove hyphens
        
        # Delete PostgreSQL server if it exists
        log_info "Deleting PostgreSQL server if it exists..."
        az postgres flexible-server delete \
            --name "${PREFIX}-airflow-pg-${ENVIRONMENT}" \
            --resource-group "air-quality-db-${ENVIRONMENT}" \
            --yes 2>/dev/null || true
            
        # Delete Key Vault secrets if they exist
        log_info "Deleting Key Vault secrets if they exist..."
        SECRETS_TO_DELETE=("airflow-postgres-password" "airflow-admin-password" "airflow-postgres-host" "airflow-postgres-port" "airflow-postgres-db" "airflow-postgres-user" "airflow-admin-user" "airflow-admin-email")
        
        for secret in "${SECRETS_TO_DELETE[@]}"; do
            if az keyvault secret show --vault-name "${KV_NAME}" --name "$secret" &>/dev/null; then
                log_info "Deleting secret: $secret"
                az keyvault secret delete --vault-name "${KV_NAME}" --name "$secret" || true
                
                # Wait for deletion to complete before purging
                WAIT_DELETE=15
                INTERVAL=3
                ELAPSED=0
                
                while [ $ELAPSED -lt $WAIT_DELETE ]; do
                    if az keyvault secret show-deleted --vault-name "${KV_NAME}" --name "$secret" &>/dev/null; then
                        log_info "Secret $secret is now in deleted state, proceeding to purge"
                        break
                    fi
                    
                    log_info "Waiting for secret $secret to enter deleted state... ($ELAPSED/$WAIT_DELETE seconds)"
                    sleep $INTERVAL
                    ELAPSED=$((ELAPSED + INTERVAL))
                done
                
                # Purge the secret
                az keyvault secret purge --vault-name "${KV_NAME}" --name "$secret" || true
            fi
        done
        
        # Verify PostgreSQL server deletion
        log_info "Verifying PostgreSQL server deletion..."
        MAX_WAIT=60
        WAIT_INTERVAL=5
        ELAPSED=0
        
        while [ $ELAPSED -lt $MAX_WAIT ]; do
            if ! az postgres flexible-server show \
                --name "${PREFIX}-airflow-pg-${ENVIRONMENT}" \
                --resource-group "air-quality-db-${ENVIRONMENT}" \
                &>/dev/null; then
                log_info "PostgreSQL server has been deleted successfully"
                break
            fi
            
            log_info "Waiting for PostgreSQL server deletion to complete... ($ELAPSED/$MAX_WAIT seconds)"
            sleep $WAIT_INTERVAL
            ELAPSED=$((ELAPSED + WAIT_INTERVAL))
        done
        
        if [ $ELAPSED -ge $MAX_WAIT ]; then
            log_warn "PostgreSQL server deletion verification timed out, proceeding anyway..."
        fi
        
        # Verify Key Vault secrets are purged
        log_info "Verifying Key Vault secrets purge completion..."
        ELAPSED=0
        SECRETS_PURGED=true
        
        while [ $ELAPSED -lt $MAX_WAIT ]; do
            SECRETS_PURGED=true
            for secret in "airflow-postgres-password" "airflow-admin-password" "airflow-postgres-host"; do
                if az keyvault secret show --vault-name "${KV_NAME}" --name "$secret" &>/dev/null; then
                    SECRETS_PURGED=false
                    break
                fi
                
                if az keyvault secret show-deleted --vault-name "${KV_NAME}" --name "$secret" &>/dev/null; then
                    SECRETS_PURGED=false
                    break
                fi
            done
            
            if [ "$SECRETS_PURGED" = true ]; then
                log_info "Key Vault secrets have been purged successfully"
                break
            fi
            
            log_info "Waiting for Key Vault secrets purge to complete... ($ELAPSED/$MAX_WAIT seconds)"
            sleep $WAIT_INTERVAL
            ELAPSED=$((ELAPSED + WAIT_INTERVAL))
        done
        
        if [ $ELAPSED -ge $MAX_WAIT ]; then
            log_warn "Key Vault secrets purge verification timed out, proceeding anyway..."
        fi
    else
        log_info "Skipping data-warehouse cleanup (use --delete-warehouse to enable cleanup)"
    fi
}

# Deploy bootstrap (Terraform state storage)
deploy_bootstrap() {
    log_info "Deploying bootstrap (Terraform state storage)..."
    cd terraform/modules/bootstrap
    terraform init
    terraform apply -auto-approve
    cd ../../..
}

# Deploy environment infrastructure
deploy_environment() {
    local env=$1
    ENVIRONMENT=$env  # Set global environment variable
    log_info "Deploying $env environment infrastructure..."

    # Deploy Data Lake first
    wait_for_lock
    sleep 60
    log_info "Deploying Data Lake..."
    cd terraform/environments/$env/data-lake
    terragrunt init
    terragrunt apply -auto-approve

    # Deploy AKS last - now including the role assignments
    wait_for_lock
    sleep 60
    log_info "Deploying AKS cluster..."
    cd ../aks-base
    terragrunt init
    terragrunt apply -auto-approve

    # Clean up before deploying Data Warehouse if delete flag is set
    clean_data_warehouse

    # Deploy Data Warehouse (PostgreSQL) with proper secret handling
    wait_for_lock
    sleep 60
    log_info "Deploying Data Warehouse..."
    cd ../data-warehouse
    terragrunt init
    
    # Import existing KeyVault secrets into Terraform state before applying
    PREFIX="air-quality-kube"
    KV_NAME="${PREFIX}dbkv${ENVIRONMENT}"
    KV_NAME=${KV_NAME//-/}  # Remove hyphens
    
    # Check which secrets already exist and import them
    log_info "Checking for existing Key Vault secrets to import into Terraform state..."
    SECRETS_TO_CHECK=("airflow-postgres-port" "airflow-admin-user" "airflow-admin-email" "airflow-postgres-password")
    SECRET_RESOURCES=("airflow_postgres_port" "airflow_admin_user" "airflow_admin_email" "postgres_password")
    
    for i in "${!SECRETS_TO_CHECK[@]}"; do
        SECRET_NAME="${SECRETS_TO_CHECK[$i]}"
        RESOURCE_NAME="${SECRET_RESOURCES[$i]}"
        
        # Check if secret exists in Azure
        if az keyvault secret show --vault-name "${KV_NAME}" --name "$SECRET_NAME" &>/dev/null; then
            log_info "Secret $SECRET_NAME exists. Importing into Terraform state..."
            
            # Get secret ID
            SECRET_ID=$(az keyvault secret show --vault-name "${KV_NAME}" --name "$SECRET_NAME" --query id -o tsv)
            
            # Import the secret into Terraform state
            terraform import "azurerm_key_vault_secret.$RESOURCE_NAME" "$SECRET_ID" || {
                log_warn "Failed to import $SECRET_NAME. It may already be in state or resource name might be different."
            }
        fi
    done
    
    # Check for the authorization issues with admin password
    if ! az keyvault secret show --vault-name "${KV_NAME}" --name "airflow-admin-password" &>/dev/null; then
        log_warn "Cannot access airflow-admin-password secret. This might cause authorization errors."
        log_info "Checking current identity permissions on Key Vault..."
        
        # Get current user/SP details
        CURRENT_PRINCIPAL=$(az account show --query user.name -o tsv)
        
        # Check and fix permissions if needed
        log_info "Ensuring $CURRENT_PRINCIPAL has Key Vault Secrets Officer role on $KV_NAME..."
        RG_NAME="air-quality-data-$ENVIRONMENT"
        SUBSCRIPTION_ID=$(az account show --query id -o tsv)
        
        az role assignment create \
            --assignee "$CURRENT_PRINCIPAL" \
            --role "Key Vault Secrets Officer" \
            --scope "/subscriptions/$SUBSCRIPTION_ID/resourcegroups/$RG_NAME/providers/microsoft.keyvault/vaults/$KV_NAME" || {
            log_warn "Failed to assign role. The role might already be assigned or you lack permissions."
        }
    fi
    
    # Now run the apply with an optional flag to ignore specific resource errors
    log_info "Applying Terraform configuration with improved secret handling..."
    terragrunt apply -auto-approve || {
        log_warn "Terraform apply had errors. This might be due to secrets that already exist."
        log_info "Trying targeted apply to create only missing resources..."
        
        # Try a targeted apply for resources that aren't secrets
        terragrunt apply -auto-approve -target="module.postgresql" || true
    }

    # Wait for PostgreSQL to be ready
    wait_for_postgres
    sleep 60

    # Get Kubernetes credentials
    log_info "Getting AKS credentials..."
    az aks get-credentials \
        --resource-group air-quality-kube-${env} \
        --name air-quality-kube-aks \
        --overwrite-existing
        
    cd ../../../../helm/airflow

    # Init Airflow Db
    log_info "Initializing Airflow Db..."
    ./initialize-airflow-db.sh 
    
    # deploy Airflow using Helm
    sleep 20
    log_info "Deploying Airflow..."
    ./deploy-airflow.sh

    cd ../..


}

# Print usage information
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Deploy infrastructure for the Air Quality project"
    echo ""
    echo "Options:"
    echo "  -e, --environment ENV   Specify environment (dev or prod, default: dev)"
    echo "  -d, --delete-warehouse            Delete existing resources before deployment"
    echo "  -h, --help              Display this help message"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -d|--delete-warehouse)
            DELETE_WAREHOUSE=true
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Validate environment
if [ "$ENVIRONMENT" != "dev" ] && [ "$ENVIRONMENT" != "prod" ]; then
    log_error "Invalid environment. Please specify 'dev' or 'prod'"
    exit 1
fi

# Main deployment function
main() {
    log_info "Starting deployment for $ENVIRONMENT environment..."
    
    if [ "$DELETE_WAREHOUSE" = true ]; then
        log_warn "Delete mode enabled: Existing resources will be deleted before deployment"
    fi
    
    # Deploy bootstrap if it hasn't been deployed yet
    if [ ! -f "terraform/bootstrap/terraform.tfstate" ]; then
        deploy_bootstrap
    else
        log_warn "Bootstrap state exists, skipping bootstrap deployment"
    fi
    
    # Deploy environment infrastructure
    deploy_environment $ENVIRONMENT
    
    log_info "Deployment completed successfully!"
}

# Execute main function
main
