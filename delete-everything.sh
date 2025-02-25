#!/bin/bash

# First, ensure we're logged in
az account show &> /dev/null
if [ $? -ne 0 ]; then
    echo "Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Get current subscription
SUBSCRIPTION=$(az account show --query name -o tsv)

echo "WARNING: This script will delete ALL resource groups and their resources"
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
    exit 0
fi

# Count resource groups
RG_COUNT=$(echo "$RESOURCE_GROUPS" | wc -l)
echo "Found $RG_COUNT resource group(s)"

# Final confirmation with count
read -p "Delete $RG_COUNT resource group(s) and ALL their resources? (yes/no): " final_confirm

if [[ "$final_confirm" != "yes" ]]; then
    echo "Operation cancelled."
    exit 0
fi

# Delete each resource group
echo "Starting deletion process..."
for rg in $RESOURCE_GROUPS; do
    echo "Deleting resource group: $rg"
    az group delete --name "$rg" --yes --no-wait
done

echo "Deletion commands have been initiated."
echo "Note: Deletions are running asynchronously (--no-wait flag used)"
echo "You can check the status using: az group list -o table"