# modules/data-lake/main.tf

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

# Add RBAC for AKS to access Data Lake
resource "azurerm_role_assignment" "aks_storage_role" {
  scope                = azurerm_storage_account.storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_kubernetes_cluster.aks.identity[0].principal_id
}

# Data source for AKS cluster
data "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.prefix}-aks"
  resource_group_name = "${var.prefix}-${var.environment}"
}