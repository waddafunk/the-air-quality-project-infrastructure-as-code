output "postgresql_server_name" {
  value = azurerm_postgresql_flexible_server.airflow.name
}

output "postgresql_server_id" {
  value = azurerm_postgresql_flexible_server.airflow.id
}

output "postgresql_server_fqdn" {
  value = azurerm_postgresql_flexible_server.airflow.fqdn
}

output "postgresql_admin_username" {
  value = azurerm_postgresql_flexible_server.airflow.administrator_login
}

output "key_vault_id" {
  value = data.azurerm_key_vault.kv.id
}

output "key_vault_name" {
  value = data.azurerm_key_vault.kv.name
}