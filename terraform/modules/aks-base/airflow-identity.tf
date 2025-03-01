# modules/aks-base/airflow-identity.tf

# Create Managed Identity for Airflow
resource "azurerm_user_assigned_identity" "airflow_identity" {
  name                = "${var.prefix}-airflow-identity"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tags                = var.tags
}


# Role Assignment for Data Lake access
resource "azurerm_role_assignment" "airflow_data_lake_role" {
  scope                = data.azurerm_storage_account.data_lake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.airflow_identity.principal_id
}

# Role Assignment for Key Vault access
resource "azurerm_role_assignment" "airflow_key_vault_role" {
  scope                = data.azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.airflow_identity.principal_id
}

# Configure the Federated Identity for Kubernetes Workload Identity
resource "azurerm_federated_identity_credential" "airflow_federated_credential" {
  name                = "${var.prefix}-airflow-federated-credential"
  resource_group_name = azurerm_resource_group.rg.name
  parent_id           = azurerm_user_assigned_identity.airflow_identity.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  subject             = "system:serviceaccount:airflow:airflow-service-account"
  
  depends_on = [
    azurerm_kubernetes_cluster.aks,
    azurerm_user_assigned_identity.airflow_identity
  ]
  
  lifecycle {
    create_before_destroy = true
  }
}

# Output the managed identity client ID
output "airflow_managed_identity_client_id" {
  value = azurerm_user_assigned_identity.airflow_identity.client_id
  description = "Client ID of the Airflow managed identity"
}

output "airflow_managed_identity_id" {
  value = azurerm_user_assigned_identity.airflow_identity.id
  description = "Resource ID of the Airflow managed identity"
}