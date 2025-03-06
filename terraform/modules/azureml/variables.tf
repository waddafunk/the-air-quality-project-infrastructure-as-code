variable "prefix" {
  description = "Prefix for all resources"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "container_registry_id" {
  description = "ID of an existing Container Registry to use with AzureML workspace"
  type        = string
  default     = ""
}

variable "public_network_access_enabled" {
  description = "Whether public network access is allowed for the AzureML workspace"
  type        = bool
  default     = true
}

variable "create_private_endpoint" {
  description = "Whether to create private endpoint for PostgreSQL"
  type        = bool
  default     = false
}

variable "subnet_id" {
  description = "Subnet ID for private endpoints"
  type        = string
  default     = ""
}