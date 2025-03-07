output "workspace_id" {
  value = azurerm_databricks_workspace.databricks.id
  description = "The ID of the Databricks workspace"
}

output "workspace_url" {
  value = azurerm_databricks_workspace.databricks.workspace_url
  description = "The URL of the Databricks workspace"
}

output "databricks_managed_identity_id" {
  value = azurerm_user_assigned_identity.databricks_identity.id
  description = "Resource ID of the Databricks managed identity"
}

output "databricks_managed_identity_client_id" {
  value = azurerm_user_assigned_identity.databricks_identity.client_id
  description = "Client ID of the Databricks managed identity"
}