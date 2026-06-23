#!/bin/bash
###############################################################################
# Local K8s dev setup — thin wrapper around docker compose.
#
#   bash infra/k8s/local-kind.sh       # Start the full stack
#   bash infra/k8s/local-kind.sh down  # Tear down everything
###############################################################################
set -euo pipefail

cd "$(dirname "$0")/../.."

case "${1:-up}" in
    down|stop)
        echo "Stopping containers and deleting Kind cluster..."
        docker compose down
        kind delete cluster --name nyc-taxi-dev 2>/dev/null || true
        echo "Done."
        ;;
    rebuild)
        echo "Rebuilding Dagster image and redeploying..."
        docker build -t nyc-taxi-analytics:dev -f docker/Dockerfile.dagster .
        kind load docker-image nyc-taxi-analytics:dev --name nyc-taxi-dev
        kubectl rollout restart deployment -n dagster -l app=nyc-taxi-analytics
        echo "Done."
        ;;
    *)
        echo "Starting full stack (Postgres + Metabase + Kind)..."
        docker compose up -d
        echo ""
        echo "Waiting for Kind cluster to be ready... (this may take 2-5 minutes)"
        echo ""
        echo "╔══════════════════════════════════════════════════════╗"
        echo "║  Dagster:   http://localhost:3000  (orchestration)   ║"
        echo "║  Airbyte:   http://localhost:8000  (ingestion)        ║"
        echo "║  Metabase:  http://localhost:3001  (analytics)        ║"
        echo "║  Postgres:  localhost:5432         (warehouse)        ║"
        echo "╚══════════════════════════════════════════════════════╝"
        ;;
esac
