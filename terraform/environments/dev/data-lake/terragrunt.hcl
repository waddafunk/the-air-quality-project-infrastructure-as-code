include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path           = find_in_parent_folders("dev.hcl")
  expose         = true
  merge_strategy = "deep"
}

terraform {
  source = "../../../modules//data-lake"
}

inputs = {
  resource_group_name = "air-quality-data-${include.env.inputs.environment}"
  
  # Storage Account configurations
  storage_account_tier = "Standard"
  storage_account_replication_type = "LRS"
  
  # Data Lake Gen2 configurations
  data_lake_containers = [
    "raw",
    "processed",
    "curated"
  ]
  
  # Additional tags specific to data lake
  tags = merge(include.env.inputs.tags, {
    Component = "data-lake"
  })
}