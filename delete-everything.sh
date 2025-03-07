#!/bin/bash

# First, ensure we're logged in
az account show &> /dev/null
if [ $? -ne 0 ]; then
    echo "Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Get current subscription
SUBSCRIPTION=$(az account show --query name -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

echo "WARNING: This script will delete ALL resource groups and their resources"
echo "and purge soft-deleted resources that require explicit purging"
echo "in subscription: $SUBSCRIPTION"
echo
echo "This action cannot be undone!"
read -p "Are you sure you want to continue? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Operation cancelled."
    exit 0
fi

# Get all resource groups
echo "Fetching resource groups..."
RESOURCE_GROUPS=$(az group list --query "[].name" -o tsv)

if [ -z "$RESOURCE_GROUPS" ]; then
    echo "No resource groups found."
else
    # Count resource groups
    RG_COUNT=$(echo "$RESOURCE_GROUPS" | wc -l)
    echo "Found $RG_COUNT resource group(s)"

    # Final confirmation with count
    read -p "Delete $RG_COUNT resource group(s) and ALL their resources? (yes/no): " final_confirm

    if [[ "$final_confirm" != "yes" ]]; then
        echo "Operation cancelled."
    else
        # Delete each resource group
        echo "Starting resource group deletion process..."
        for rg in $RESOURCE_GROUPS; do
            echo "Deleting resource group: $rg"
            az group delete --name "$rg" --yes
        done

    fi
fi

# Handle soft-deleted resources that need explicit purging

# 1. Key Vaults (these need explicit purging)
echo
echo "Checking for soft-deleted Key Vaults to purge..."
DELETED_VAULTS=$(az keyvault list-deleted --query "[].name" -o tsv)

if [ -z "$DELETED_VAULTS" ]; then
    echo "No soft-deleted Key Vaults found."
else
    VAULT_COUNT=$(echo "$DELETED_VAULTS" | wc -l)
    echo "Found $VAULT_COUNT soft-deleted Key Vault(s)"
    
    for vault in $DELETED_VAULTS; do
        echo "Purging soft-deleted Key Vault: $vault"
        az keyvault purge --name "$vault" 
    done
    echo "Key Vault purge commands have been initiated."
fi

# 2. App Service Plans (these need explicit deletion in some cases)
echo
echo "Checking for App Service Plans to delete..."
ASP_LIST=$(az appservice plan list --query "[].name" -o tsv)

if [ -z "$ASP_LIST" ]; then
    echo "No App Service Plans found."
else
    ASP_COUNT=$(echo "$ASP_LIST" | wc -l)
    echo "Found $ASP_COUNT App Service Plan(s)"
    
    for asp in $ASP_LIST; do
        echo "Deleting App Service Plan: $asp"
        RESOURCE_GROUP=$(az appservice plan show --name "$asp" --query "resourceGroup" -o tsv)
        az appservice plan delete --name "$asp" --resource-group "$RESOURCE_GROUP" --yes
    done
    echo "App Service Plan deletions completed."
fi

# 3. Check for soft-deleted Storage Accounts
echo
echo "Checking for soft-deleted Storage Accounts to purge..."
DELETED_STORAGE=$(az storage account list-deleted --query "[].name" -o tsv 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$DELETED_STORAGE" ]; then
    STORAGE_COUNT=$(echo "$DELETED_STORAGE" | wc -l)
    echo "Found $STORAGE_COUNT soft-deleted Storage Account(s)"
    
    for storage in $DELETED_STORAGE; do
        echo "Purging soft-deleted Storage Account: $storage"
        az storage account purge --name "$storage" --subscription "$SUBSCRIPTION_ID" 
    done
    echo "Storage Account purge commands have been initiated."
else
    echo "No soft-deleted Storage Accounts found or command not supported with your CLI version."
fi

# 4. Check for soft-deleted Cosmos DB accounts
echo
echo "Checking for soft-deleted Cosmos DB accounts to purge..."
DELETED_COSMOS=$(az cosmosdb list-deleted --query "[].name" -o tsv 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$DELETED_COSMOS" ]; then
    COSMOS_COUNT=$(echo "$DELETED_COSMOS" | wc -l)
    echo "Found $COSMOS_COUNT soft-deleted Cosmos DB account(s)"
    
    for cosmos in $DELETED_COSMOS; do
        location=$(az cosmosdb list-deleted --query "[?name=='$cosmos'].location" -o tsv)
        echo "Purging soft-deleted Cosmos DB account: $cosmos in $location"
        az cosmosdb purge --name "$cosmos" --location "$location" --subscription "$SUBSCRIPTION_ID" 
    done
    echo "Cosmos DB purge commands have been initiated."
else
    echo "No soft-deleted Cosmos DB accounts found or command not supported with your CLI version."
fi

echo
echo "Cleanup process terminated for all resources."