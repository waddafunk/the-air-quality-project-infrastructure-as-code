include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path           = find_in_parent_folders("dev.hcl")
  expose         = true
  merge_strategy = "deep"
}

terraform {
  source = "../../../modules//data-warehouse"
}

inputs = {
  resource_group_name = "air-quality-db-${include.env.inputs.environment}"
  postgres_location   = "westeurope"
  
  postgres_sku_name    = "B_Standard_B1ms"
  postgres_version     = "15"
  postgres_storage_mb  = 32768
  
  # Network configuration
  enable_public_access = false
  
  tags = merge(include.env.inputs.tags, {
    Component = "data-warehouse"
  })
}