#!/bin/bash

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Verify Azure CLI login
az account show &> /dev/null || {
    log_error "Not logged in to Azure. Please run 'az login' first."
    exit 1
}

# Initialize working directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Deploy bootstrap (Terraform state storage)
deploy_bootstrap() {
    log_info "Deploying bootstrap (Terraform state storage)..."
    cd terraform/modules/bootstrap
    terraform init
    terraform apply -auto-approve
    cd ../../..
    sleep 20
}

# Deploy environment infrastructure
deploy_environment() {
    local env=$1
    log_info "Deploying $env environment infrastructure..."

    # Deploy AKS base first
    log_info "Deploying AKS cluster..."
    cd "terraform/environments/$env/aks-base"
    terragrunt init
    terragrunt apply -auto-approve

    sleep 20
    
    # Deploy Data Lake
    log_info "Deploying Data Lake..."
    cd ../data-lake
    terragrunt init
    terragrunt apply -auto-approve

    sleep 20

    #deploy Airflow on top of k8s
    cd ../../../../helm/airflow
    az aks get-credentials --resource-group air-quality-kube-dev --name air-quality-kube-aks
    helm repo add airflow https://airflow.apache.org
    helm upgrade --install airflow airflow/airflow -f values.yaml
    
    cd ../../..
}

# Main deployment function
main() {
    local environment=${1:-dev}  # Default to dev if no environment specified
    
    # Validate environment
    if [ "$environment" != "dev" ] && [ "$environment" != "prod" ]; then
        log_error "Invalid environment. Please specify 'dev' or 'prod'"
        exit 1
    fi
    
    log_info "Starting deployment for $environment environment..."
    
    # Deploy bootstrap if it hasn't been deployed yet
    if [ ! -f "terraform/bootstrap/terraform.tfstate" ]; then
        deploy_bootstrap
    else
        log_warn "Bootstrap state exists, skipping bootstrap deployment"
    fi
    
    # Deploy environment infrastructure
    deploy_environment $environment
    
    log_info "Deployment completed successfully!"
}

# Parse command line arguments
environment="dev"
while getopts "e:" opt; do
    case $opt in
        e)
            environment="$OPTARG"
            ;;
        \?)
            log_error "Invalid option: -$OPTARG"
            exit 1
            ;;
    esac
done

# Execute main function
main $environment