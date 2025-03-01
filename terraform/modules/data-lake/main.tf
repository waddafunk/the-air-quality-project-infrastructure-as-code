# modules/data-lake/main.tf
data "azurerm_client_config" "current" {}


resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "storage" {
  name                      = replace("${var.prefix}dls${var.environment}", "-", "")
  resource_group_name       = azurerm_resource_group.rg.name
  location                  = azurerm_resource_group.rg.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  is_hns_enabled          = true  # Hierarchical namespace for Data Lake Gen2
  
  tags = var.tags
}

# Create containers in the Data Lake
resource "azurerm_storage_container" "containers" {
  for_each              = toset(var.data_lake_containers)
  name                  = each.key
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "private"
}

resource "azurerm_key_vault" "kv" {
  name                       = replace("${var.prefix}dbkv${var.environment}", "-", "")
  location                   = var.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = false
  enable_rbac_authorization  = true  # Enable RBAC instead of access policies

  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  tags = var.tags
}
