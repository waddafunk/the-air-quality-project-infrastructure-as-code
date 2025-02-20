# modules/data-lake/outputs.tf

output "storage_account_name" {
  value = azurerm_storage_account.storage.name
}

output "storage_account_id" {
  value = azurerm_storage_account.storage.id
}

output "primary_dfs_endpoint" {
  value = azurerm_storage_account.storage.primary_dfs_endpoint
}

output "containers" {
  value = [for container in azurerm_storage_container.containers : container.name]
}