resource "azurerm_resource_group" "databricks_rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_databricks_workspace" "databricks" {
  name                = "${var.prefix}-databricks-${var.environment}"
  resource_group_name = azurerm_resource_group.databricks_rg.name
  location            = azurerm_resource_group.databricks_rg.location
  sku                 = var.sku
  
  custom_parameters {
    virtual_network_id                                   = data.azurerm_virtual_network.vnet.id
    private_subnet_name                                  = azurerm_subnet.private.name
    public_subnet_name                                   = azurerm_subnet.public.name
    private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.private.id
    public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.public.id
    no_public_ip                                         = var.no_public_ip
  }

  tags = var.tags
}

# Create a new set of subnets for Databricks
resource "azurerm_subnet" "public" {
  name                 = "databricks-public"
  resource_group_name  = data.azurerm_virtual_network.vnet.resource_group_name
  virtual_network_name = data.azurerm_virtual_network.vnet.name
  address_prefixes     = var.databricks_public_subnet_address_prefix
  
  # Required delegation for Databricks
  delegation {
    name = "databricks-delegation"
    service_delegation {
      name    = "Microsoft.Databricks/workspaces"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action", "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action", "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"]
    }
  }

  service_endpoints = ["Microsoft.Storage"]
}

resource "azurerm_subnet" "private" {
  name                 = "databricks-private"
  resource_group_name  = data.azurerm_virtual_network.vnet.resource_group_name
  virtual_network_name = data.azurerm_virtual_network.vnet.name
  address_prefixes     = var.databricks_private_subnet_address_prefix
  
  # Required delegation for Databricks
  delegation {
    name = "databricks-delegation"
    service_delegation {
      name    = "Microsoft.Databricks/workspaces"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action", "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action", "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"]
    }
  }

  service_endpoints = ["Microsoft.Storage"]
}

# Create NSG for Databricks
resource "azurerm_network_security_group" "databricks_nsg" {
  name                = "${var.prefix}-databricks-nsg"
  location            = var.location
  resource_group_name = data.azurerm_virtual_network.vnet.resource_group_name
  tags                = var.tags
}

# Associate NSG with subnets
resource "azurerm_subnet_network_security_group_association" "public" {
  subnet_id                 = azurerm_subnet.public.id
  network_security_group_id = azurerm_network_security_group.databricks_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "private" {
  subnet_id                 = azurerm_subnet.private.id
  network_security_group_id = azurerm_network_security_group.databricks_nsg.id
}

# Data sources for existing resources
data "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  resource_group_name = "${var.prefix}-${var.environment}"
}

data "azurerm_storage_account" "data_lake" {
  name                = replace("${var.prefix}dls${var.environment}", "-", "")
  resource_group_name = "air-quality-data-${var.environment}"
}

data "azurerm_key_vault" "kv" {
  name                = replace("${var.prefix}dbkv${var.environment}", "-", "")
  resource_group_name = "air-quality-data-${var.environment}"
}

data "azurerm_postgresql_flexible_server" "postgres" {
  name                = "${var.prefix}-airflow-pg-${var.environment}"
  resource_group_name = "air-quality-db-${var.environment}"
}

# Create Managed Identity for Databricks
resource "azurerm_user_assigned_identity" "databricks_identity" {
  name                = "${var.prefix}-databricks-identity"
  resource_group_name = azurerm_resource_group.databricks_rg.name
  location            = azurerm_resource_group.databricks_rg.location
  tags                = var.tags
}

# Role Assignment for Data Lake access
resource "azurerm_role_assignment" "databricks_data_lake_role" {
  scope                = data.azurerm_storage_account.data_lake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.databricks_identity.principal_id
}

# Role Assignment for Key Vault access
resource "azurerm_role_assignment" "databricks_key_vault_role" {
  scope                = data.azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.databricks_identity.principal_id
}