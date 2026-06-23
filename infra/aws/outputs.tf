output "dagster_url" {
  value = "https://dagster.${var.domain}"
}

output "airbyte_url" {
  value = "https://airbyte.${var.domain}"
}

output "metabase_url" {
  value = "https://metabase.${var.domain}"
}

output "postgres_address" {
  value = aws_db_instance.postgres.address
}

output "ecr_repository" {
  value = aws_ecr_repository.app.repository_url
}

output "eks_cluster_name" {
  value = aws_eks_cluster.main.name
}

output "kube_config_command" {
  value = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${var.region}"
}
