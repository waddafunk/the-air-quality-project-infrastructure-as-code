locals {
  env_vars = yamldecode(file("env.yaml"))
}

inputs = {
  environment = local.env_vars.environment
  location   = local.env_vars.location
  prefix     = local.env_vars.prefix
  
  tags = {
    Environment = local.env_vars.environment
    Terraform   = "true"
  }
}