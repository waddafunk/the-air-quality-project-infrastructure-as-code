# Azure ML Workspace resource
resource "azurerm_machine_learning_workspace" "aml" {
  name                    = "${var.prefix}-ml-${var.environment}"
  location                = var.location
  resource_group_name     = azurerm_resource_group.rg.name
  application_insights_id = azurerm_application_insights.aml.id
  key_vault_id            = azurerm_key_vault.aml.id
  storage_account_id      = azurerm_storage_account.aml.id

  identity {
    type = "SystemAssigned"
  }

  # Container Registry will be created if not provided
  container_registry_id = var.container_registry_id != "" ? var.container_registry_id : null

  public_network_access_enabled = var.public_network_access_enabled
  
  tags = var.tags
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-ml-${var.environment}"
  location = var.location
  tags     = var.tags
}

# Storage Account for AzureML - WITHOUT hierarchical namespace
resource "azurerm_storage_account" "aml" {
  name                     = replace("${var.prefix}mlsa${var.environment}", "-", "")
  location                 = var.location
  resource_group_name      = azurerm_resource_group.rg.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
  is_hns_enabled           = false  # Changed from true to false - AzureML doesn't support HNS
  min_tls_version          = "TLS1_2"

  tags = var.tags
}

# Key Vault for AzureML
resource "azurerm_key_vault" "aml" {
  name                       = replace("${var.prefix}mlkv${var.environment}", "-", "")
  location                   = var.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = false
  enable_rbac_authorization  = true

  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  tags = var.tags
}

# Application Insights for AzureML
resource "azurerm_application_insights" "aml" {
  name                = "${var.prefix}-ml-ai-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "web"
  tags                = var.tags
}

# Optional Container Registry for AzureML
resource "azurerm_container_registry" "acr" {
  count               = var.container_registry_id == "" ? 1 : 0
  name                = replace("${var.prefix}mlcr${var.environment}", "-", "")
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  sku                 = "Standard"
  admin_enabled       = true
  tags                = var.tags
}

# Data sources
data "azurerm_client_config" "current" {}
data "azurerm_storage_account" "data_lake" {
  name                = replace("${var.prefix}dls${var.environment}", "-", "")
  resource_group_name = "air-quality-data-${var.environment}"
}

data "azurerm_postgresql_flexible_server" "db" {
  name                = "${var.prefix}-airflow-pg-${var.environment}"
  resource_group_name = "air-quality-db-${var.environment}"
}

# Grant AzureML access to Data Lake with Storage Blob Data Contributor role
resource "azurerm_role_assignment" "aml_data_lake_role" {
  scope                = data.azurerm_storage_account.data_lake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_machine_learning_workspace.aml.identity[0].principal_id
}

# Grant Key Vault role to AzureML workspace
resource "azurerm_role_assignment" "aml_kv_role" {
  scope                = azurerm_key_vault.aml.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = azurerm_machine_learning_workspace.aml.identity[0].principal_id
  name                 = uuid()
}

# Create a private endpoint for the PostgreSQL server if needed
resource "azurerm_private_endpoint" "postgres_pe" {
  count               = var.create_private_endpoint ? 1 : 0
  name                = "${var.prefix}-pg-pe-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "${var.prefix}-pg-psc-${var.environment}"
    private_connection_resource_id = data.azurerm_postgresql_flexible_server.db.id
    is_manual_connection           = false
    subresource_names              = ["postgresqlServer"]
  }

  tags = var.tags
}

# Generate config file for local development
resource "local_file" "ml_config" {
  content = jsonencode({
    subscription_id = data.azurerm_client_config.current.subscription_id
    resource_group  = azurerm_resource_group.rg.name
    workspace_name  = azurerm_machine_learning_workspace.aml.name
  })
  filename = "${path.module}/config.json"
}