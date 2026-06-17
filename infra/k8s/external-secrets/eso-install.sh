#!/usr/bin/env bash
###############################################################################
# External Secrets Operator — Helm installation
#
# ESO syncs secrets from cloud provider secret stores (AWS Secrets Manager,
# Azure Key Vault, GCP Secret Manager) into native Kubernetes Secrets.
#
# Prerequisites:
#   - Helm 3.x installed
#   - kubectl configured with cluster admin access
#
# Usage:
#   ./eso-install.sh
#
# After installation, apply your cloud-specific ClusterSecretStore:
#   kubectl apply -f cluster-secret-store-aws.yaml    # or azure / gcp
# Then apply ExternalSecret resources:
#   kubectl apply -f external-secrets.yaml -n dagster
#   kubectl apply -f external-secrets.yaml -n airbyte
###############################################################################
set -euo pipefail

NAMESPACE="external-secrets"
CHART_VERSION="${ESO_CHART_VERSION:-0.14.3}"

echo "==> Adding External Secrets Operator Helm repo..."
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

echo "==> Installing ESO in namespace '${NAMESPACE}'..."
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --version "${CHART_VERSION}" \
  --set installCRDs=true \
  --wait \
  --timeout 5m

echo "==> Verifying installation..."
kubectl get pods -n "${NAMESPACE}"
kubectl get crd clustersecretstores.external-secrets.io
kubectl get crd externalsecrets.external-secrets.io

echo "==> ESO installed successfully."
