include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path           = find_in_parent_folders("dev.hcl")
  expose         = true
  merge_strategy = "deep"
}

terraform {
  source = "../../../modules//aks-base"
}

inputs = {
  resource_group_name = "air-quality-kube-${include.env.inputs.environment}"
  
  # AKS specific configurations
  kubernetes_version     = "1.30"
  node_count            = 2
  node_count_min        = 1
  node_count_max        = 5
  node_size             = "Standard_D2s_v3"
  os_disk_size_gb       = 128
  
  # Networking
  vnet_address_space       = ["10.0.0.0/16"]
  aks_subnet_address_prefix = ["10.0.1.0/24"]
  service_cidr             = "172.16.0.0/16"
  dns_service_ip           = "172.16.0.10"
}