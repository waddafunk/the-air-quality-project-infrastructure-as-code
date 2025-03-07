variable "prefix" {
  description = "Prefix for all resources"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
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

variable "sku" {
  description = "The SKU to use for the Databricks Workspace"
  type        = string
  default     = "standard"
  validation {
    condition     = contains(["standard", "premium", "trial"], var.sku)
    error_message = "Allowed values for sku are 'standard', 'premium', or 'trial'."
  }
}

variable "databricks_public_subnet_address_prefix" {
  description = "Address prefix for Databricks public subnet"
  type        = list(string)
  default     = ["10.0.3.0/24"]
}

variable "databricks_private_subnet_address_prefix" {
  description = "Address prefix for Databricks private subnet"
  type        = list(string)
  default     = ["10.0.4.0/24"]
}

variable "no_public_ip" {
  description = "Specifies whether to deploy Databricks workspace with no public IP"
  type        = bool
  default     = false
}