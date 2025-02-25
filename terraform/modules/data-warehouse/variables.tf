variable "prefix" {
  description = "Prefix for all resources"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region for most resources"
  type        = string
}

variable "postgres_location" {
  description = "Azure region for PostgreSQL (must be one that supports PostgreSQL)"
  type        = string
  default     = "westeurope"
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "postgres_admin_username" {
  description = "PostgreSQL administrator username"
  type        = string
  default     = "airflow_admin"
}

variable "postgres_sku_name" {
  description = "PostgreSQL Flexible Server SKU name"
  type        = string
  default     = "B_Standard_B1ms"  # Basic tier, most economical for dev
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15"  # Latest stable version
}

variable "postgres_storage_mb" {
  description = "PostgreSQL storage in MB (must be one of: 32768, 65536, 131072, 262144, 524288, 1048576, 2097152, 4194304, 8388608, 16777216, 33553408)"
  type        = number
  default     = 32768  # 32GB minimum for Flexible Server

  validation {
    condition = contains([
      32768, 65536, 131072, 262144, 524288, 1048576, 
      2097152, 4194304, 8388608, 16777216, 33553408
    ], var.postgres_storage_mb)
    error_message = "The storage_mb value must be one of the allowed values for Flexible Server."
  }
}

variable "postgres_backup_retention_days" {
  description = "PostgreSQL backup retention days"
  type        = number
  default     = 7
}

variable "postgres_subnet_prefix" {
  description = "Address prefix for PostgreSQL subnet"
  type        = list(string)
  default     = ["10.0.2.0/24"]  # Make sure this doesn't overlap with AKS subnet
}

variable "aks_subnet_cidr" {
  description = "CIDR of the AKS subnet for firewall rules"
  type        = string
  default     = "10.0.1.0/24"  # Should match AKS subnet CIDR
}

variable "enable_public_access" {
  description = "Enable public network access for PostgreSQL"
  type        = bool
  default     = false
}