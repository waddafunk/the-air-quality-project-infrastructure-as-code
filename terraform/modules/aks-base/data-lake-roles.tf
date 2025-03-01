# Data source for the Data Lake Storage Account
data "azurerm_storage_account" "data_lake" {
  name                = replace("${var.prefix}dls${var.environment}", "-", "")
  resource_group_name = "air-quality-data-${var.environment}"
}

# Role assignment for AKS to access Data Lake
resource "azurerm_role_assignment" "aks_data_lake_role" {
  scope                = data.azurerm_storage_account.data_lake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id
}