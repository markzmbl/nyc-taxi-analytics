###############################################################################
# AWS: EKS + Helm (Airbyte + Dagster + Metabase)
# Replaces ECS Fargate with K8s-based deployment.
#
# Remote state backend (uncomment and configure for production):
#   terraform {
#     backend "s3" {
#       bucket         = "nyc-taxi-tfstate"
#       key            = "aws/terraform.tfstate"
#       region         = "us-east-1"
#       encrypt        = true
#       dynamodb_table = "nyc-taxi-tf-lock"
#     }
#   }
###############################################################################
terraform {
  required_providers {
    aws        = { source = "hashicorp/aws",  version = "~> 5.40" }
    helm       = { source = "hashicorp/helm", version = "~> 2.12" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.23" }
  }
}

provider "aws" { region = var.region }

data "aws_availability_zones" "available" {}

# ============================================================================
# VPC
# ============================================================================
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "${var.project}-vpc" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "${var.project}-pub-${count.index}" }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 100)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = { Name = "${var.project}-priv-${count.index}" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ============================================================================
# RDS PostgreSQL
# ============================================================================
resource "aws_security_group" "rds" {
  name   = "${var.project}-rds"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    # Restrict to EKS node group security group in production:
    # security_groups = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
    cidr_blocks = ["10.0.0.0/16"]
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-db"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_db_instance" "postgres" {
  identifier             = "${var.project}-pg"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = var.pg_instance_class
  allocated_storage      = 20
  storage_encrypted      = true
  db_name                = "warehouse"
  username               = var.pg_admin_user
  password               = var.pg_admin_password
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = false
  final_snapshot_identifier = "${var.project}-pg-final"
  deletion_protection    = true
  publicly_accessible    = false
}

# ============================================================================
# ECR
# ============================================================================
resource "aws_ecr_repository" "app" {
  name                 = var.project
  image_tag_mutability = "MUTABLE"
  force_delete         = false
}

# ============================================================================
# EKS Cluster
# ============================================================================
resource "aws_iam_role" "eks" {
  name = "${var.project}-eks"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role       = aws_iam_role.eks.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "main" {
  name     = "${var.project}-eks"
  role_arn = aws_iam_role.eks.arn
  version  = "1.31"

  vpc_config {
    subnet_ids              = aws_subnet.public[*].id
    endpoint_public_access  = true
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster]
}

# Node group
resource "aws_iam_role" "node" {
  name = "${var.project}-eks-node"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_registry" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project}-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.private[*].id
  instance_types  = [var.eks_instance_type]

  scaling_config {
    desired_size = var.eks_node_count
    max_size     = var.eks_node_count + 2
    min_size     = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_registry,
  ]
}

# ============================================================================
# K8s / Helm providers
# ============================================================================
provider "kubernetes" {
  host                   = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.main.name]
  }
}

provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.main.name]
    }
  }
}

# ============================================================================
# Namespaces
# ============================================================================
resource "kubernetes_namespace" "airbyte" {
  metadata { name = "airbyte" }
  depends_on = [aws_eks_node_group.main]
}

resource "kubernetes_namespace" "dagster" {
  metadata { name = "dagster" }
  depends_on = [aws_eks_node_group.main]
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
      pg_host           = aws_db_instance.postgres.address
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
      pg_host             = aws_db_instance.postgres.address
      pg_admin_user       = var.pg_admin_user
      container_registry  = aws_ecr_repository.app.repository_url
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
