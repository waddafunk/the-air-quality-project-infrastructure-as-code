output "workspace_id" {
  description = "The ID of the Machine Learning Workspace"
  value       = azurerm_machine_learning_workspace.aml.id
}

output "workspace_name" {
  description = "The name of the Machine Learning Workspace"
  value       = azurerm_machine_learning_workspace.aml.name
}

output "storage_account_id" {
  description = "The ID of the Storage Account associated with AzureML"
  value       = azurerm_storage_account.aml.id
}

output "key_vault_id" {
  description = "The ID of the Key Vault associated with AzureML"
  value       = azurerm_key_vault.aml.id
}

output "application_insights_id" {
  description = "The ID of the Application Insights associated with AzureML"
  value       = azurerm_application_insights.aml.id
}

output "container_registry_id" {
  description = "The ID of the Container Registry associated with AzureML"
  value       = var.container_registry_id != "" ? var.container_registry_id : (length(azurerm_container_registry.acr) > 0 ? azurerm_container_registry.acr[0].id : null)
}

output "identity_principal_id" {
  description = "The Principal ID of the System Assigned Identity of AzureML"
  value       = azurerm_machine_learning_workspace.aml.identity[0].principal_id
}