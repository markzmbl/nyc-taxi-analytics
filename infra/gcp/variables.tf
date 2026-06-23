variable "project_id" {
  description = "GCP project ID"
}

variable "project" {
  default = "nyc-taxi"
}

variable "region" {
  default = "us-east1"
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

variable "pg_tier" {
  default = "db-custom-2-4096"
}

variable "container_image_tag" {
  default = "latest"
}

# ---------- GKE ----------
variable "gke_node_count" {
  description = "GKE node pool count"
  default     = 3
}

variable "gke_machine_type" {
  description = "GKE node machine type"
  default     = "e2-standard-4"
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
