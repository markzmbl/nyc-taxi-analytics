variable "project" {
  default = "nyc-taxi"
}

variable "location" {
  default = "eastus"
}

variable "domain" {
  description = "Base domain for ingress hosts"
  default     = "nyctaxi.local"
}

variable "pg_admin_user" {
  default   = "pgadmin"
  sensitive = true
}

variable "pg_admin_password" {
  sensitive = true
}

variable "pg_sku" {
  default = "B_Standard_B1ms"
}

variable "container_image_tag" {
  default = "latest"
}

# ---------- AKS ----------
variable "aks_node_count" {
  description = "AKS default node pool count"
  default     = 3
}

variable "aks_vm_size" {
  description = "AKS node VM size"
  default     = "Standard_D4s_v5"
}

variable "aks_subnet_cidr" {
  description = "CIDR of the AKS subnet — used for PostgreSQL firewall rules"
  default     = "10.0.0.0/20"
}

# ---------- Airbyte ----------
variable "airbyte_workspace_id" {
  description = "Airbyte workspace UUID"
  sensitive   = true
}

variable "airbyte_username" {
  description = "Airbyte basic auth username"
  default     = "airbyte@example.com"
}

variable "airbyte_password" {
  description = "Airbyte basic auth password"
  sensitive   = true
}

# ---------- External APIs ----------
variable "epa_api_key" {
  description = "EPA AQS API key"
  default     = ""
  sensitive   = true
}

variable "epa_email" {
  description = "EPA AQS registered email"
  default     = "test@example.com"
}
