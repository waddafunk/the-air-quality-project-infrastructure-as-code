# modules/data-warehouse/main.tf
data "azurerm_key_vault" "kv" {
  name                = replace("${var.prefix}dbkv${var.environment}", "-", "")
  resource_group_name = "air-quality-data-${var.environment}"
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_postgresql_flexible_server" "airflow" {
  name                   = "${var.prefix}-airflow-pg-${var.environment}"
  resource_group_name    = azurerm_resource_group.rg.name
  location              = var.postgres_location
  version               = var.postgres_version
  
  delegated_subnet_id    = azurerm_subnet.postgres.id
  private_dns_zone_id    = azurerm_private_dns_zone.postgres.id

  administrator_login    = var.postgres_admin_username
  administrator_password = random_password.postgres_password.result

  storage_mb = var.postgres_storage_mb
  sku_name   = var.postgres_sku_name

  public_network_access_enabled = false

  backup_retention_days        = var.postgres_backup_retention_days

  maintenance_window {
    day_of_week  = 0
    start_hour   = 0
    start_minute = 0
  }

  tags = var.tags

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.postgres
  ]

  lifecycle {
    ignore_changes = [
      zone
    ]
  }
}

# Update the database creation to handle recreation
resource "azurerm_postgresql_flexible_server_database" "airflow" {
  name      = "airflow"
  server_id = azurerm_postgresql_flexible_server.airflow.id
  charset   = "UTF8"
  collation = "en_US.utf8"

  # Important: In production, you might want to prevent accidental deletion
  lifecycle {
    prevent_destroy = false  # Set to true in production
  }
}

# Use role assignments instead of access policies
resource "azurerm_role_assignment" "kv_terraform" {
  scope                = data.azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "kv_aks" {
  scope                = data.azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = data.azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}

# Networking configuration for PostgreSQL
resource "azurerm_subnet" "postgres" {
  name                 = "postgres-subnet"
  resource_group_name  = data.azurerm_virtual_network.aks.resource_group_name
  virtual_network_name = data.azurerm_virtual_network.aks.name
  address_prefixes     = var.postgres_subnet_prefix

  delegation {
    name = "fs"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }

  private_endpoint_network_policies = "Enabled"
}

# Private DNS Zone for PostgreSQL
resource "azurerm_private_dns_zone" "postgres" {
  name                = "airflow-postgres.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "postgreslink"
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = data.azurerm_virtual_network.aks.id
  resource_group_name   = azurerm_resource_group.rg.name
  registration_enabled  = true
}


# Key Vault access policies
data "azurerm_client_config" "current" {}

# Ensure Terraform has Key Vault Administrator permissions
resource "azurerm_role_assignment" "terraform_keyvault_admin" {
  scope                = data.azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id

  lifecycle {
    create_before_destroy = true
  }
}

# Store PostgreSQL password in Key Vault
resource "azurerm_key_vault_secret" "postgres_password" {
  name         = "airflow-postgres-password"
  value        = random_password.postgres_password.result
  key_vault_id = data.azurerm_key_vault.kv.id

  depends_on = [
    azurerm_role_assignment.terraform_keyvault_admin
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# Generate random password for PostgreSQL
resource "random_password" "postgres_password" {
  length  = 16
  special = true
  
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
  min_special = 1
}

# Data sources for existing resources
data "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.prefix}-aks"
  resource_group_name = "${var.prefix}-${var.environment}"
}

data "azurerm_virtual_network" "aks" {
  name                = "${var.prefix}-vnet"
  resource_group_name = "${var.prefix}-${var.environment}"
}

# Configure firewall rules to allow AKS subnet
resource "azurerm_postgresql_flexible_server_firewall_rule" "aks" {
  name             = "allow-aks"
  server_id        = azurerm_postgresql_flexible_server.airflow.id
  start_ip_address = cidrhost(var.aks_subnet_cidr, 0)
  end_ip_address   = cidrhost(var.aks_subnet_cidr, -1)
}

# Add PostgreSQL extensions required by Airflow
resource "azurerm_postgresql_flexible_server_configuration" "extensions" {
  server_id = azurerm_postgresql_flexible_server.airflow.id
  name      = "azure.extensions"
  value     = "UUID-OSSP"  # Add any other required extensions
}