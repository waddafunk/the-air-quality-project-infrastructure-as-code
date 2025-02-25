data "azurerm_key_vault" "kv" {
  name                = replace("${var.prefix}dbkv${var.environment}", "-", "")
  resource_group_name = "air-quality-data-${var.environment}"
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  resource_group_name = azurerm_resource_group.rg.name
  location           = azurerm_resource_group.rg.location
  address_space      = var.vnet_address_space
  tags               = var.tags
}

# AKS Subnet
resource "azurerm_subnet" "aks" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = var.aks_subnet_address_prefix

  # Enable private endpoint network policies
  private_endpoint_network_policies = "Enabled" 

  # Service endpoints for PostgreSQL
  service_endpoints = ["Microsoft.Storage", "Microsoft.Sql"]
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.prefix}-aks"
  location           = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix         = "${var.prefix}-aks"
  kubernetes_version = var.kubernetes_version

  oidc_issuer_enabled = true

  default_node_pool {
    name           = "default"
    vm_size        = var.node_size
    vnet_subnet_id = azurerm_subnet.aks.id
    max_pods       = 50
    os_disk_size_gb = var.os_disk_size_gb
    temporary_name_for_rotation = "tempnodepool" 

    enable_auto_scaling = true

    # Add autoscaling configuration
    min_count          = var.node_count_min
    max_count          = var.node_count_max
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin     = "azure"
    network_policy     = "calico"
    service_cidr       = var.service_cidr
    dns_service_ip     = var.dns_service_ip
    load_balancer_sku  = "standard"
  }

  tags = var.tags
}
