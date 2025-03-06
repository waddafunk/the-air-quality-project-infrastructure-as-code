include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path           = find_in_parent_folders("dev.hcl")
  expose         = true
  merge_strategy = "deep"
}

# Define explicit dependencies to ensure proper order
dependencies {
  paths = ["../data-lake", "../data-warehouse", "../aks-base"]
}

dependency "aks" {
  config_path = "../aks-base"
}

terraform {
  source = "../../../modules//azureml"
}

inputs = {
  # Integration with existing infrastructure
  subnet_id = dependency.aks.outputs.aks_subnet_id
  
  # Public access for dev environment
  public_network_access_enabled = true
  
  # No need for private endpoint in dev
  create_private_endpoint = false
  
  # Additional tags
  tags = merge(include.env.inputs.tags, {
    Component = "machine-learning"
  })
}