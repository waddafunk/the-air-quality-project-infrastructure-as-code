# environments/root.hcl

locals {
  # Load environment variables
  env_vars = yamldecode(file(find_in_parent_folders("env.yaml")))
  env      = local.env_vars.environment
}

# Remote state configuration
remote_state {
  backend = "azurerm"
  config = {
    resource_group_name  = "terraform-state-${local.env}"
    storage_account_name = "aqtfstate${local.env}"
    container_name      = "tfstate"
    key                 = "${path_relative_to_include()}/terraform.tfstate"
  }
}

# Generate provider configuration
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "azurerm" {
  features {}
}

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
  required_version = ">= 1.0"
  
  backend "azurerm" {}
}
EOF
}