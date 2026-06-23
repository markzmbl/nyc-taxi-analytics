variable "project" {
  default = "nyc-taxi"
}

variable "region" {
  default = "us-east-1"
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

variable "pg_instance_class" {
  default = "db.t4g.medium"
}

variable "container_image_tag" {
  default = "latest"
}

# ---------- EKS ----------
variable "eks_node_count" {
  description = "EKS managed node group desired count"
  default     = 3
}

variable "eks_instance_type" {
  description = "EKS node instance type"
  default     = "t3.xlarge"
}

variable "eks_endpoint_public" {
  description = "Enable public endpoint for the EKS API server (set to false in production)"
  default     = false
}

variable "eks_public_access_cidrs" {
  description = "CIDR blocks allowed to access the public EKS API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Restrict in production to office VPN / bastion CIDRs
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
