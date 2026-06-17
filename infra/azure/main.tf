###############################################################################
# Azure: AKS + Helm (Airbyte + Dagster + Metabase)
#
# Remote state backend (uncomment and configure for production):
#   terraform {
#     backend "azurerm" {
#       resource_group_name  = "rg-nyc-taxi-tfstate"
#       storage_account_name = "nyctaxitfstate"
#       container_name       = "tfstate"
#       key                  = "azure/terraform.tfstate"
#     }
#   }
###############################################################################
terraform {
  required_providers {
    azurerm    = { source = "hashicorp/azurerm", version = "~> 3.100" }
    helm       = { source = "hashicorp/helm",    version = "~> 2.12" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.23" }
  }
}

provider "azurerm" { features {} }

data "azurerm_kubernetes_service_versions" "current" {
  location       = var.location
  include_preview = false
}

# ============================================================================
# Resource Group
# ============================================================================
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project}"
  location = var.location
}

# ============================================================================
# VNet + Subnet (must exist before AKS)
# ============================================================================
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.project}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.0.0/20"]
}

# ============================================================================
# Container Registry
# ============================================================================
resource "azurerm_container_registry" "main" {
  name                = replace("cr${var.project}", "-", "")
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = true
}

# ============================================================================
# PostgreSQL Flexible Server
# ============================================================================
resource "azurerm_postgresql_flexible_server" "main" {
  name                   = "psql-${var.project}"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  version                = "16"
  administrator_login    = var.pg_admin_user
  administrator_password = var.pg_admin_password
  sku_name               = var.pg_sku
  storage_mb             = 32768
  zone                   = "1"
  # Note: Storage is encrypted at rest by default in Azure PostgreSQL Flexible Server.
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.main.id
  # NOTE: This allows all Azure services. For production, restrict to AKS subnet:
  # start_ip_address = cidrhost(azurerm_subnet.aks.address_prefixes[0], 0)
  # end_ip_address   = cidrhost(azurerm_subnet.aks.address_prefixes[0], -1)
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_postgresql_flexible_server_database" "warehouse" {
  name      = "warehouse"
  server_id = azurerm_postgresql_flexible_server.main.id
}

resource "azurerm_postgresql_flexible_server_database" "dagster" {
  name      = "dagster"
  server_id = azurerm_postgresql_flexible_server.main.id
}

resource "azurerm_postgresql_flexible_server_database" "metabase" {
  name      = "metabase"
  server_id = azurerm_postgresql_flexible_server.main.id
}

resource "azurerm_postgresql_flexible_server_database" "airbyte" {
  name      = "airbyte"
  server_id = azurerm_postgresql_flexible_server.main.id
}

# ============================================================================
# AKS Cluster
# ============================================================================
resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-${var.project}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = var.project
  kubernetes_version  = data.azurerm_kubernetes_service_versions.current.latest_version

  default_node_pool {
    name           = "default"
    node_count     = var.aks_node_count
    vm_size        = var.aks_vm_size
    vnet_subnet_id = azurerm_subnet.aks.id
  }

  identity { type = "SystemAssigned" }

  network_profile {
    network_plugin = "azure"
    network_policy = "calico"
  }

  depends_on = [azurerm_subnet.aks]
}

# ============================================================================
# K8s + Helm providers
# ============================================================================
provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.main.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.main.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.cluster_ca_certificate)
  }
}

# ============================================================================
# Namespaces
# ============================================================================
resource "kubernetes_namespace" "airbyte" {
  metadata { name = "airbyte" }
}

resource "kubernetes_namespace" "dagster" {
  metadata { name = "dagster" }
}

# ============================================================================
# Secrets
# ============================================================================
resource "kubernetes_secret" "dagster_postgres" {
  metadata { name = "dagster-postgres-secret"; namespace = kubernetes_namespace.dagster.metadata[0].name }
  data     = { password = var.pg_admin_password }
  type     = "Opaque"
}

resource "kubernetes_secret" "dagster_airbyte" {
  metadata { name = "dagster-airbyte-secret"; namespace = kubernetes_namespace.dagster.metadata[0].name }
  data = {
    workspace_id = var.airbyte_workspace_id
    username     = var.airbyte_username
    password     = var.airbyte_password
  }
  type = "Opaque"
}

resource "kubernetes_secret" "dagster_epa" {
  metadata { name = "dagster-epa-secret"; namespace = kubernetes_namespace.dagster.metadata[0].name }
  data = {
    api_key = var.epa_api_key
    email   = var.epa_email
  }
  type = "Opaque"
}

resource "kubernetes_secret" "airbyte_postgres" {
  metadata { name = "airbyte-postgres-secret"; namespace = kubernetes_namespace.airbyte.metadata[0].name }
  data     = { password = var.pg_admin_password }
  type     = "Opaque"
}

# ============================================================================
# Helm — Airbyte OSS
# ============================================================================
resource "helm_release" "airbyte" {
  name       = "airbyte"
  repository = "https://airbytehq.github.io/helm-charts"
  chart      = "airbyte"
  namespace  = kubernetes_namespace.airbyte.metadata[0].name
  timeout    = 600

  values = [
    templatefile("${path.module}/../k8s/airbyte/values.yaml", {
      pg_host           = azurerm_postgresql_flexible_server.main.fqdn
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
  name       = "dagster"
  repository = "https://dagster-io.github.io/helm"
  chart      = "dagster"
  namespace  = kubernetes_namespace.dagster.metadata[0].name
  timeout    = 600

  values = [
    templatefile("${path.module}/../k8s/dagster/values.yaml", {
      pg_host             = azurerm_postgresql_flexible_server.main.fqdn
      pg_admin_user       = var.pg_admin_user
      container_registry  = azurerm_container_registry.main.login_server
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
