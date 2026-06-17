###############################################################################
# GCP: GKE + Helm (Airbyte + Dagster + Metabase)
# Replaces Cloud Run with K8s-based deployment.
#
# Remote state backend (uncomment and configure for production):
#   terraform {
#     backend "gcs" {
#       bucket = "nyc-taxi-tfstate"
#       prefix = "gcp/terraform.tfstate"
#     }
#   }
###############################################################################
terraform {
  required_providers {
    google     = { source = "hashicorp/google", version = "~> 5.20" }
    helm       = { source = "hashicorp/helm",   version = "~> 2.12" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.23" }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ============================================================================
# APIs
# ============================================================================
resource "google_project_service" "apis" {
  for_each = toset([
    "container.googleapis.com",
    "sqladmin.googleapis.com",
    "artifactregistry.googleapis.com",
    "vpcaccess.googleapis.com",
    "compute.googleapis.com",
  ])
  service            = each.value
  disable_on_destroy = false
}

# ============================================================================
# Artifact Registry
# ============================================================================
resource "google_artifact_registry_repository" "main" {
  location      = var.region
  repository_id = var.project
  format        = "DOCKER"
  depends_on    = [google_project_service.apis]
}

# ============================================================================
# VPC + Subnet
# ============================================================================
resource "google_compute_network" "main" {
  name                    = "${var.project}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "main" {
  name          = "${var.project}-subnet"
  ip_cidr_range = "10.0.0.0/16"
  region        = var.region
  network       = google_compute_network.main.id
}

# ============================================================================
# Cloud SQL PostgreSQL
# ============================================================================
resource "google_sql_database_instance" "main" {
  name             = "${var.project}-pg"
  database_version = "POSTGRES_16"
  region           = var.region

  settings {
    tier = var.pg_tier
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.main.id
    }
  }

  deletion_protection = true
  depends_on          = [google_project_service.apis]
}

resource "google_sql_user" "admin" {
  name     = var.pg_admin_user
  instance = google_sql_database_instance.main.name
  password = var.pg_admin_password
}

resource "google_sql_database" "warehouse" {
  name     = "warehouse"
  instance = google_sql_database_instance.main.name
}

resource "google_sql_database" "dagster" {
  name     = "dagster"
  instance = google_sql_database_instance.main.name
}

resource "google_sql_database" "metabase" {
  name     = "metabase"
  instance = google_sql_database_instance.main.name
}

resource "google_sql_database" "airbyte" {
  name     = "airbyte"
  instance = google_sql_database_instance.main.name
}

# ============================================================================
# GKE Cluster
# ============================================================================
resource "google_container_cluster" "main" {
  name     = "${var.project}-gke"
  location = var.region

  network    = google_compute_network.main.name
  subnetwork = google_compute_subnetwork.main.name

  deletion_protection = false
  initial_node_count  = 1
  remove_default_node_pool = true

  depends_on = [google_project_service.apis]
}

resource "google_container_node_pool" "main" {
  name       = "${var.project}-nodes"
  location   = var.region
  cluster    = google_container_cluster.main.name
  node_count = var.gke_node_count

  node_config {
    machine_type = var.gke_machine_type
    disk_size_gb = 50
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  depends_on = [google_project_service.apis]
}

# ============================================================================
# Helm provider
# ============================================================================
data "google_client_config" "default" {}

provider "kubernetes" {
  host  = "https://${google_container_cluster.main.endpoint}"
  token = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(
    google_container_cluster.main.master_auth[0].cluster_ca_certificate
  )
}

provider "helm" {
  kubernetes {
    host  = "https://${google_container_cluster.main.endpoint}"
    token = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(
      google_container_cluster.main.master_auth[0].cluster_ca_certificate
    )
  }
}

# ============================================================================
# Namespaces
# ============================================================================
resource "kubernetes_namespace" "airbyte" {
  metadata { name = "airbyte" }
  depends_on = [google_container_node_pool.main]
}

resource "kubernetes_namespace" "dagster" {
  metadata { name = "dagster" }
  depends_on = [google_container_node_pool.main]
}

# ============================================================================
# Secrets
# ============================================================================
resource "kubernetes_secret" "dagster_postgres" {
  metadata { name = "dagster-postgres-secret"; namespace = "dagster" }
  data = { password = var.pg_admin_password }
  type = "Opaque"
  depends_on = [kubernetes_namespace.dagster]
}

resource "kubernetes_secret" "dagster_airbyte" {
  metadata { name = "dagster-airbyte-secret"; namespace = "dagster" }
  data = {
    workspace_id = var.airbyte_workspace_id
    username     = var.airbyte_username
    password     = var.airbyte_password
  }
  type       = "Opaque"
  depends_on = [kubernetes_namespace.dagster]
}

resource "kubernetes_secret" "dagster_epa" {
  metadata { name = "dagster-epa-secret"; namespace = "dagster" }
  data = {
    api_key = var.epa_api_key
    email   = var.epa_email
  }
  type       = "Opaque"
  depends_on = [kubernetes_namespace.dagster]
}

resource "kubernetes_secret" "airbyte_postgres" {
  metadata { name = "airbyte-postgres-secret"; namespace = "airbyte" }
  data = { password = var.pg_admin_password }
  type = "Opaque"
  depends_on = [kubernetes_namespace.airbyte]
}

# ============================================================================
# Helm — Airbyte OSS
# ============================================================================
resource "helm_release" "airbyte" {
  name             = "airbyte"
  repository       = "https://airbytehq.github.io/helm-charts"
  chart            = "airbyte"
  namespace        = "airbyte"
  create_namespace = false
  wait             = true
  timeout          = 600

  values = [
    templatefile("${path.module}/../k8s/airbyte/values.yaml", {
      pg_host           = google_sql_database_instance.main.private_ip_address
      pg_admin_user     = var.pg_admin_user
      pg_admin_password = var.pg_admin_password
      domain            = var.domain
    })
  ]

  depends_on = [kubernetes_secret.airbyte_postgres]
}

# ============================================================================
# Helm — Dagster
# ============================================================================
resource "helm_release" "dagster" {
  name             = "dagster"
  repository       = "https://dagster-io.github.io/helm"
  chart            = "dagster"
  namespace        = "dagster"
  create_namespace = false
  wait             = true
  timeout          = 600

  values = [
    templatefile("${path.module}/../k8s/dagster/values.yaml", {
      pg_host             = google_sql_database_instance.main.private_ip_address
      pg_admin_user       = var.pg_admin_user
      container_registry  = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.main.repository_id}"
      container_image_tag = var.container_image_tag
      domain              = var.domain
    })
  ]

  depends_on = [
    kubernetes_secret.dagster_postgres,
    kubernetes_secret.dagster_airbyte,
    kubernetes_secret.dagster_epa,
    helm_release.airbyte,
  ]
}
