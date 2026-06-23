output "dagster_url" {
  value = "https://dagster.${var.domain}"
}

output "airbyte_url" {
  value = "https://airbyte.${var.domain}"
}

output "metabase_url" {
  value = "https://metabase.${var.domain}"
}

output "postgres_fqdn" {
  value = azurerm_postgresql_flexible_server.main.fqdn
}

output "container_registry" {
  value = azurerm_container_registry.main.login_server
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "kube_config_command" {
  value = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name}"
}
