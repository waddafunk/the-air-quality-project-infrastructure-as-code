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
  paths = ["../data-lake", "../aks-base"]
}

# Add these to make dependency errors more obvious
dependency "data_lake" {
  config_path = "../data-lake"
  skip_outputs = true  # We're not using outputs, just ensuring order
}

dependency "aks_base" {
  config_path = "../aks-base"
  skip_outputs = true  # We're not using outputs, just ensuring order
}

terraform {
  source = "../../../modules//databricks"
}

inputs = {
  resource_group_name = "air-quality-analytics-${include.env.inputs.environment}"
  
  # Databricks configurations
  sku = "standard"
  
  # Networking
  databricks_public_subnet_address_prefix = ["10.0.3.0/24"]
  databricks_private_subnet_address_prefix = ["10.0.4.0/24"]
  no_public_ip = false  # Set to true for production environments
  
  # Additional tags specific to Databricks
  tags = merge(include.env.inputs.tags, {
    Component = "analytics"
  })
}