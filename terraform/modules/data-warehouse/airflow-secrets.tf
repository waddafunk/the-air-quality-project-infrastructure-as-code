# Add this to your data-warehouse module or create a new airflow module

# Generate Airflow admin credentials
resource "random_password" "airflow_admin_password" {
  length  = 16
  special = true
  min_lower = 1
  min_upper = 1
  min_numeric = 1
  min_special = 1
}

# Store Airflow connection information in Key Vault
resource "azurerm_key_vault_secret" "airflow_postgres_host" {
  name         = "airflow-postgres-host"
  value        = azurerm_postgresql_flexible_server.airflow.fqdn
  key_vault_id = data.azurerm_key_vault.kv.id
  
  depends_on = [
    azurerm_role_assignment.kv_terraform
  ]
}

resource "azurerm_key_vault_secret" "airflow_postgres_port" {
  name         = "airflow-postgres-port"
  value        = "5432"
  key_vault_id = data.azurerm_key_vault.kv.id
  
  depends_on = [
    azurerm_role_assignment.kv_terraform
  ]
}

resource "azurerm_key_vault_secret" "airflow_postgres_db" {
  name         = "airflow-postgres-db"
  value        = azurerm_postgresql_flexible_server_database.airflow.name
  key_vault_id = data.azurerm_key_vault.kv.id
  
  depends_on = [
    azurerm_role_assignment.kv_terraform
  ]
}

resource "azurerm_key_vault_secret" "airflow_postgres_user" {
  name         = "airflow-postgres-user"
  value        = azurerm_postgresql_flexible_server.airflow.administrator_login
  key_vault_id = data.azurerm_key_vault.kv.id
  
  depends_on = [
    azurerm_role_assignment.kv_terraform
  ]
}

# Store Airflow admin credentials in Key Vault
resource "azurerm_key_vault_secret" "airflow_admin_user" {
  name         = "airflow-admin-user"
  value        = "admin"
  key_vault_id = data.azurerm_key_vault.kv.id
  
  depends_on = [
    azurerm_role_assignment.kv_terraform
  ]
}

resource "azurerm_key_vault_secret" "airflow_admin_password" {
  name         = "airflow-admin-password"
  value        = random_password.airflow_admin_password.result
  key_vault_id = data.azurerm_key_vault.kv.id
}

resource "azurerm_key_vault_secret" "airflow_admin_email" {
  name         = "airflow-admin-email"
  value        = "admin@example.com"
  key_vault_id = data.azurerm_key_vault.kv.id
  
  depends_on = [
    azurerm_role_assignment.kv_terraform
  ]
}