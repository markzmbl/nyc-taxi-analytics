#!/bin/bash
###############################################################################
# Kind cluster init script — runs inside the kind-init Docker Compose service.
# Creates a Kind K8s cluster and deploys Airbyte + Dagster via Helm.
#
# Postgres is reachable at host.docker.internal:5432 (Docker Compose).
###############################################################################
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-nyc-taxi-dev}"
AIRBYTE_NS="${AIRBYTE_NS:-airbyte}"
DAGSTER_NS="${DAGSTER_NS:-dagster}"
PG_HOST="${PG_HOST:-host.docker.internal}"
PG_USER="${PG_USER:-dagster}"
PG_PASSWORD="${PG_PASSWORD:-dagster}"

echo "=== 1. Wait for Postgres ==="
until docker run --rm --network host postgres:16-alpine \
    psql "postgresql://${PG_USER}:${PG_PASSWORD}@${PG_HOST}:5432/dagster" -c "SELECT 1" >/dev/null 2>&1; do
    echo "  Waiting for Postgres..."
    sleep 3
done
echo "Postgres is ready."

# ── Ensure databases exist ──────────────────────────────────────────────────
docker run --rm --network host postgres:16-alpine \
    psql "postgresql://${PG_USER}:${PG_PASSWORD}@${PG_HOST}:5432/dagster" \
    -c "CREATE DATABASE warehouse;" 2>/dev/null || true
docker run --rm --network host postgres:16-alpine \
    psql "postgresql://${PG_USER}:${PG_PASSWORD}@${PG_HOST}:5432/dagster" \
    -c "CREATE DATABASE airbyte;"   2>/dev/null || true
docker run --rm --network host postgres:16-alpine \
    psql "postgresql://${PG_USER}:${PG_PASSWORD}@${PG_HOST}:5432/warehouse" \
    -c "CREATE SCHEMA IF NOT EXISTS raw; CREATE SCHEMA IF NOT EXISTS staging; CREATE SCHEMA IF NOT EXISTS marts;" 2>/dev/null || true

# ── Kind cluster ────────────────────────────────────────────────────────────
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "=== 2. Kind cluster '${CLUSTER_NAME}' already exists — reusing ==="
else
    echo "=== 2. Creating Kind cluster '${CLUSTER_NAME}' ==="
    kind create cluster --name "${CLUSTER_NAME}" --config - <<YAML
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30080
        hostPort: 3000
        protocol: TCP
      - containerPort: 30082
        hostPort: 8000
        protocol: TCP
      - containerPort: 30083
        hostPort: 8006
        protocol: TCP
YAML
fi

# ── Fix kubeconfig for Docker-in-Docker ─────────────────────────────────
# When running inside a container, Kind generates a kubeconfig pointing to
# 127.0.0.1, but the API server is actually on the Kind node container.
# Rewrite the server address to use the Kind node's Docker network IP.
CP_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${CLUSTER_NAME}-control-plane" 2>/dev/null || echo "")
if [ -n "${CP_IP}" ]; then
    # Regenerate kubeconfig if missing (fresh container reusing existing cluster)
    if [ ! -f ~/.kube/config ]; then
        echo "  Regenerating kubeconfig for existing cluster"
        kind export kubeconfig --name "${CLUSTER_NAME}" 2>/dev/null || true
        # If that failed, create minimal kubeconfig from docker exec
        if [ ! -f ~/.kube/config ]; then
            mkdir -p ~/.kube
            docker exec "${CLUSTER_NAME}-control-plane" cat /etc/kubernetes/admin.conf > ~/.kube/config
            sed -i "s|server: https://[^:]*:6443|server: https://${CP_IP}:6443|g" ~/.kube/config
        fi
    fi
    echo "  Kind control-plane IP: ${CP_IP} — fixing kubeconfig server address"
    sed -i "s|server: https://127.0.0.1:[0-9]*|server: https://${CP_IP}:6443|g" ~/.kube/config || true
fi

# ── Helm repos ──────────────────────────────────────────────────────────────
echo "=== 3. Adding Helm repos ==="
helm repo add airbyte https://airbytehq.github.io/helm-charts 2>/dev/null || true
helm repo add dagster https://dagster-io.github.io/helm 2>/dev/null || true
helm repo update

# ── Wait for K8s API ────────────────────────────────────────────────────────
echo "=== 4. Waiting for K8s API server ==="
for i in $(seq 1 30); do
    if kubectl cluster-info --context "kind-${CLUSTER_NAME}" >/dev/null 2>&1; then
        echo "API server ready."
        break
    fi
    echo "  Waiting for API server... (attempt $i/30)"
    sleep 5
done

# ── Namespaces ──────────────────────────────────────────────────────────────
echo "=== 5. Creating namespaces ==="
kubectl create namespace "${AIRBYTE_NS}" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "${DAGSTER_NS}" --dry-run=client -o yaml | kubectl apply -f -

# ── Secrets ─────────────────────────────────────────────────────────────────
echo "=== 6. Creating secrets ==="
kubectl create secret generic airbyte-postgres-secret \
    -n "${AIRBYTE_NS}" \
    --from-literal=password="${PG_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic dagster-postgres-secret \
    -n "${DAGSTER_NS}" \
    --from-literal=password="${PG_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic dagster-airbyte-secret \
    -n "${DAGSTER_NS}" \
    --from-literal=workspace_id="${AIRBYTE_WORKSPACE_ID:-}" \
    --from-literal=username="${AIRBYTE_USERNAME:-airbyte@example.com}" \
    --from-literal=password="${AIRBYTE_PASSWORD:-password}" \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic dagster-epa-secret \
    -n "${DAGSTER_NS}" \
    --from-literal=api_key="${EPA_API_KEY:-}" \
    --from-literal=email="${EPA_EMAIL:-test@example.com}" \
    --dry-run=client -o yaml | kubectl apply -f -

# MinIO credentials for Airbyte — needed by post-install hooks
kubectl create secret generic airbyte-config-secrets \
    -n "${AIRBYTE_NS}" \
    --from-literal=minio-access-key-id=minio \
    --from-literal=minio-secret-access-key=minio123 \
    --dry-run=client -o yaml | kubectl apply -f -

# ── Build Dagster image → load into Kind ────────────────────────────────────
echo "=== 7. Building Dagster image ==="
docker build -t nyc-taxi-analytics:dev -f /workspace/docker/Dockerfile.dagster /workspace/
for attempt in 1 2 3; do
    echo "  Loading image into Kind (attempt ${attempt}/3)..."
    if kind load docker-image nyc-taxi-analytics:dev --name "${CLUSTER_NAME}" 2>&1; then
        echo "  Image loaded successfully."
        break
    else
        echo "  Load attempt ${attempt} failed."
        if [ "${attempt}" -lt 3 ]; then
            echo "  Retrying in 15s..."
            sleep 15
        else
            echo "  WARNING: Failed to load image after 3 attempts."
            echo "  Checking if image is already present in Kind..."
            if docker exec "${CLUSTER_NAME}-control-plane" crictl images 2>/dev/null | grep -q "nyc-taxi-analytics"; then
                echo "  Image is already present in Kind — continuing."
            else
                echo "  ERROR: Image not found in Kind. Exiting."
                exit 1
            fi
        fi
    fi
done

# ── Install Airbyte ─────────────────────────────────────────────────────────
echo "=== 7. Installing Airbyte OSS ==="
helm upgrade --install airbyte airbyte/airbyte \
    -n "${AIRBYTE_NS}" \
    -f /workspace/infra/k8s/airbyte/values.yaml \
    --set global.deploymentMode=oss \
    --set global.edition=community \
    --set global.database.host="${PG_HOST}" \
    --set global.database.port=5432 \
    --set global.database.database=airbyte \
    --set global.database.username="${PG_USER}" \
    --set global.database.password="${PG_PASSWORD}" \
    --set global.storage.type=minio \
    --set global.storage.minio.enabled=true \
    --set global.ingress.enabled=false \
    --set server.service.type=NodePort \
    --set server.service.nodePort=30083 \
    --set webapp.enabled=false \
    --wait --timeout 15m || true  # Don't fail if Airbyte needs a few retries

# ── Install Dagster ─────────────────────────────────────────────────────────
echo "=== 8. Installing Dagster ==="
helm upgrade --install dagster dagster/dagster \
    -n "${DAGSTER_NS}" \
    -f /workspace/infra/k8s/dagster/values.yaml \
    --set postgresql.enabled=false \
    --set postgresql.postgresqlHost="${PG_HOST}" \
    --set postgresql.postgresqlPassword="${PG_PASSWORD}" \
    --set postgresql.postgresqlDatabase=dagster \
    --set postgresql.postgresqlUsername="${PG_USER}" \
    --set dagster-user-deployments.enabled=true \
    --set dagster-user-deployments.deployments[0].name=nyc-taxi-analytics \
    --set dagster-user-deployments.deployments[0].image.repository=nyc-taxi-analytics \
    --set dagster-user-deployments.deployments[0].image.tag=dev \
    --set dagster-user-deployments.deployments[0].image.pullPolicy=IfNotPresent \
    --set dagster-user-deployments.deployments[0].port=3030 \
    --set dagster-user-deployments.deployments[0].dagsterApiGrpcArgs[0]="--python-file" \
    --set dagster-user-deployments.deployments[0].dagsterApiGrpcArgs[1]="/app/orchestration/definitions.py" \
    --set dagster-user-deployments.deployments[0].env[0].name=PG_HOST \
    --set dagster-user-deployments.deployments[0].env[0].value="${PG_HOST}" \
    --set dagster-user-deployments.deployments[0].env[1].name=PG_USER \
    --set dagster-user-deployments.deployments[0].env[1].value="${PG_USER}" \
    --set dagster-user-deployments.deployments[0].env[2].name=PG_PASSWORD \
    --set dagster-user-deployments.deployments[0].env[2].value="${PG_PASSWORD}" \
    --set dagster-user-deployments.deployments[0].env[3].name=AIRBYTE_REST_API_BASE_URL \
    --set dagster-user-deployments.deployments[0].env[3].value="http://airbyte-server.${AIRBYTE_NS}.svc.cluster.local:8006/api/public/v1" \
    --set dagster-user-deployments.deployments[0].env[4].name=AIRBYTE_CONFIGURATION_API_BASE_URL \
    --set dagster-user-deployments.deployments[0].env[4].value="http://airbyte-server.${AIRBYTE_NS}.svc.cluster.local:8006/api/v1" \
    --set dagster-user-deployments.deployments[0].env[5].name=AIRBYTE_WORKSPACE_ID \
    --set dagster-user-deployments.deployments[0].env[5].value="${AIRBYTE_WORKSPACE_ID:-}" \
    --set dagster-user-deployments.deployments[0].env[6].name=AIRBYTE_USERNAME \
    --set dagster-user-deployments.deployments[0].env[6].value="${AIRBYTE_USERNAME:-airbyte@example.com}" \
    --set dagster-user-deployments.deployments[0].env[7].name=AIRBYTE_PASSWORD \
    --set dagster-user-deployments.deployments[0].env[7].value="${AIRBYTE_PASSWORD:-password}" \
    --set dagster-user-deployments.deployments[0].env[8].name=DAGSTER_POSTGRES_HOST \
    --set dagster-user-deployments.deployments[0].env[8].value="${PG_HOST}" \
    --set dagster-user-deployments.deployments[0].env[9].name=DAGSTER_POSTGRES_USER \
    --set dagster-user-deployments.deployments[0].env[9].value="${PG_USER}" \
    --set dagster-user-deployments.deployments[0].env[10].name=DAGSTER_POSTGRES_PASSWORD \
    --set dagster-user-deployments.deployments[0].env[10].value="${PG_PASSWORD}" \
    --set dagster-user-deployments.deployments[0].env[11].name=DAGSTER_POSTGRES_DB \
    --set dagster-user-deployments.deployments[0].env[11].value=dagster \
    --set dagster-webserver.service.type=NodePort \
    --set dagster-webserver.service.nodePort=30080 \
    --set dagster-webserver.enableReadOnly=false \
    --wait --timeout 10m || true  # Don't fail if Dagster needs a few retries

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Kind cluster ready!                                         ║"
echo "║                                                              ║"
echo "║  Dagster:   http://localhost:3000  (orchestration)            ║"
echo "║  Airbyte:   http://localhost:8006  (ingestion API)             ║"
echo "║  Metabase:  http://localhost:3001  (analytics)                ║"
echo "║  Postgres:  localhost:5432         (warehouse)                ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# ── Sleep to keep the container running (for docker compose) ───────────────
echo "Setup complete. Container stays alive to maintain the cluster."
echo "Use Ctrl+C to stop, then run: kind delete cluster --name ${CLUSTER_NAME}"
echo ""
exec sleep infinity
