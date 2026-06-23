output "dagster_url" {
  value = "https://dagster.${var.domain}"
}

output "airbyte_url" {
  value = "https://airbyte.${var.domain}"
}

output "metabase_url" {
  value = "https://metabase.${var.domain}"
}

output "postgres_private_ip" {
  value = google_sql_database_instance.main.private_ip_address
}

output "artifact_registry" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.main.repository_id}"
}

output "gke_cluster_name" {
  value = google_container_cluster.main.name
}

output "kube_config_command" {
  value = "gcloud container clusters get-credentials ${google_container_cluster.main.name} --region ${var.region}"
}
