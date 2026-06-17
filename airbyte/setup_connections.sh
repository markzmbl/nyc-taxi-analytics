#!/bin/bash
###############################################################################
# Airbyte Connection Auto-Setup
#
# Creates sources, destination, and connections via the Airbyte REST API.
# Idempotent — safe to re-run; existing resources are reused.
# Reads .env for credentials.  Run after Airbyte is up and healthy.
#
# Usage:
#   source .env
#   bash airbyte/setup_connections.sh
###############################################################################
set -euo pipefail

: "${AIRBYTE_CONFIGURATION_API_BASE_URL:?Set AIRBYTE_CONFIGURATION_API_BASE_URL in .env}"
: "${AIRBYTE_USERNAME:?Set AIRBYTE_USERNAME}"
: "${AIRBYTE_PASSWORD:?Set AIRBYTE_PASSWORD}"
: "${PG_HOST:?Set PG_HOST}"
: "${PG_USER:?Set PG_USER}"
: "${PG_PASSWORD:?Set PG_PASSWORD}"

API="${AIRBYTE_CONFIGURATION_API_BASE_URL}"
AUTH="$(echo -n "${AIRBYTE_USERNAME}:${AIRBYTE_PASSWORD}" | base64)"

# ── helpers ─────────────────────────────────────────────────────────────────

airbyte_api() {
    # Make an Airbyte REST API call with optional retry.
    # Args: method url [json_body]
    local method="$1" url="$2" data="${3:-}"
    local max_retries=3 attempt=1 delay=2
    while [ $attempt -le $max_retries ]; do
        local resp
        if [ -z "$data" ]; then
            resp=$(curl -sSf -X "$method" "${API}${url}" \
                -H "Authorization: Basic ${AUTH}" \
                -H "Content-Type: application/json" 2>&1) && echo "$resp" && return 0
        else
            resp=$(curl -sSf -X "$method" "${API}${url}" \
                -H "Authorization: Basic ${AUTH}" \
                -H "Content-Type: application/json" \
                -d "$data" 2>&1) && echo "$resp" && return 0
        fi
        if [ $attempt -lt $max_retries ]; then
            echo "  Retry $attempt/$max_retries in ${delay}s: ${resp}" >&2
            sleep $delay
            delay=$((delay * 2))
        else
            echo "  ERROR after $max_retries attempts: ${resp}" >&2
            return 1
        fi
        attempt=$((attempt + 1))
    done
}

get_workspace_id() {
    airbyte_api GET "/workspaces" | python3 -c "import sys,json; print(json.load(sys.stdin)['data'][0]['workspaceId'])"
}

# ── idempotency helpers ─────────────────────────────────────────────────────

find_resource_id() {
    # Find an existing Airbyte resource (source/destination/connection) by name.
    # Args: endpoint name
    # Returns: resource ID on stdout (empty if not found), exit 0 either way.
    local endpoint="$1" name="$2"
    airbyte_api GET "${endpoint}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for item in data.get('data', []):
    if item.get('name') == '${name}':
        print(item.get('${endpoint%?}Id', ''))
        sys.exit(0)
" 2>/dev/null || true
}

create_resource() {
    # Create an Airbyte resource if it doesn't already exist.
    # Args: type("source"|"destination"|"connection") name json_body
    # Returns: resource ID on stdout.
    local type="$1" name="$2" body="$3"
    local endpoint="${type}s"          # sources, destinations, connections
    local id_field="${type}Id"         # sourceId, destinationId, connectionId

    local existing
    existing=$(find_resource_id "$endpoint" "$name")
    if [ -n "$existing" ]; then
        echo "  ${type} '${name}' already exists (${existing}), reusing." >&2
        echo "$existing"
        return 0
    fi

    local new_id
    new_id=$(airbyte_api POST "/${endpoint}" "$body" | python3 -c "import sys,json; print(json.load(sys.stdin)['${id_field}'])")
    echo "  ${type} '${name}' created: ${new_id}" >&2
    echo "$new_id"
}

# ── main ────────────────────────────────────────────────────────────────────

echo "=== Airbyte Connection Setup ==="

WORKSPACE_ID=$(get_workspace_id)
echo "Workspace: ${WORKSPACE_ID}"

# --- PostgreSQL destination ---
echo "Creating PostgreSQL destination..."
DEST_ID=$(create_resource "destination" "warehouse-postgres" '{
  "workspaceId": "'"${WORKSPACE_ID}"'",
  "name": "warehouse-postgres",
  "destinationDefinitionId": "25c5221d-dce2-4163-ade9-739ef790f503",
  "connectionConfiguration": {
    "host": "'"${PG_HOST}"'",
    "port": 5432,
    "database": "warehouse",
    "schema": "raw",
    "username": "'"${PG_USER}"'",
    "password": "'"${PG_PASSWORD}"'",
    "ssl_mode": { "mode": "disable" },
    "tunnel_method": { "tunnel_method": "NO_TUNNEL" }
  }
}')
echo "  Destination ID: ${DEST_ID}"

# --- Azure Blob Storage source (all TLC taxi) ---
echo "Creating Azure Blob Storage source..."
AZURE_SOURCE_ID=$(create_resource "source" "azure-blob-storage" '{
  "workspaceId": "'"${WORKSPACE_ID}"'",
  "name": "azure-blob-storage",
  "sourceDefinitionId": "b5fe08a8-3be3-4ee5-b927-07aabda0cfcb",
  "connectionConfiguration": {
    "account_name": "azureopendatastorage",
    "container": "nyctlc",
    "credentials": { "auth_type": "public" },
    "streams": [
      {
        "name": "taxi_trips",
        "format": { "filetype": "parquet" },
        "globs": ["yellow/puYear=*/puMonth=*/*.parquet"],
        "schemaless": true
      },
      {
        "name": "taxi_trips_green",
        "format": { "filetype": "parquet" },
        "globs": ["green/puYear=*/puMonth=*/*.parquet"],
        "schemaless": true
      },
      {
        "name": "taxi_trips_fhv",
        "format": { "filetype": "parquet" },
        "globs": ["fhv/puYear=*/puMonth=*/*.parquet"],
        "schemaless": true
      },
      {
        "name": "taxi_trips_fhvhv",
        "format": { "filetype": "parquet" },
        "globs": ["fhvhv/puYear=*/puMonth=*/*.parquet"],
        "schemaless": true
      }
    ]
  }
}')
echo "  Azure source ID: ${AZURE_SOURCE_ID}"

# --- S3 source (citibike) ---
echo "Creating S3 source..."
S3_SOURCE_ID=$(create_resource "source" "citibike-s3" '{
  "workspaceId": "'"${WORKSPACE_ID}"'",
  "name": "citibike-s3",
  "sourceDefinitionId": "e87eea07-91e3-4fc7-b4e1-eb3ac60b701b",
  "connectionConfiguration": {
    "bucket": "tripdata",
    "region": "us-east-1",
    "provider": { "storage": "HTTPS" },
    "streams": [
      {
        "name": "citibike-trips",
        "format": {
          "filetype": "csv",
          "delimiter": ",",
          "header_definition": { "header_definition_type": "From CSV" },
          "compression": { "compression_type": "zip" }
        },
        "globs": ["*-citibike-tripdata.csv.zip"],
        "schemaless": true
      }
    ]
  }
}')
echo "  S3 source ID: ${S3_SOURCE_ID}"

# --- Connections ---
echo "Creating taxi connection (yellow + green + fhv + fhvhv)..."
create_resource "connection" "nyc-taxi-trips" '{
  "workspaceId": "'"${WORKSPACE_ID}"'",
  "name": "nyc-taxi-trips",
  "sourceId": "'"${AZURE_SOURCE_ID}"'",
  "destinationId": "'"${DEST_ID}"'",
  "namespaceDefinition": "custom_format",
  "namespaceFormat": "raw",
  "prefix": "",
  "schedule": { "scheduleType": "cron", "cronExpression": "0 3 3 * *" },
  "scheduleData": { "cron": { "cronExpression": "0 3 3 * *", "cronTimeZone": "UTC" } },
  "syncMode": "full_refresh_append",
  "streamConfigurations": [
    {
      "name": "taxi_trips",
      "syncMode": "full_refresh",
      "destinationSyncMode": "overwrite"
    },
    {
      "name": "taxi_trips_green",
      "syncMode": "full_refresh",
      "destinationSyncMode": "overwrite"
    },
    {
      "name": "taxi_trips_fhv",
      "syncMode": "full_refresh",
      "destinationSyncMode": "overwrite"
    },
    {
      "name": "taxi_trips_fhvhv",
      "syncMode": "full_refresh",
      "destinationSyncMode": "overwrite"
    }
  ]
}' > /dev/null
echo "  Connection: nyc-taxi-trips ✓"

echo "Creating citibike connection..."
create_resource "connection" "nyc-citibike-trips" '{
  "workspaceId": "'"${WORKSPACE_ID}"'",
  "name": "nyc-citibike-trips",
  "sourceId": "'"${S3_SOURCE_ID}"'",
  "destinationId": "'"${DEST_ID}"'",
  "namespaceDefinition": "custom_format",
  "namespaceFormat": "raw",
  "prefix": "",
  "schedule": { "scheduleType": "cron", "cronExpression": "0 3 5 * *" },
  "scheduleData": { "cron": { "cronExpression": "0 3 5 * *", "cronTimeZone": "UTC" } },
  "syncMode": "full_refresh_append",
  "streamConfigurations": [
    {
      "name": "citibike-trips",
      "syncMode": "full_refresh",
      "destinationSyncMode": "overwrite"
    }
  ]
}' > /dev/null
echo "  Connection: nyc-citibike-trips ✓"

# --- Update .env with workspace ID ---
ENV_FILE="$(dirname "$0")/../.env"
if grep -q "AIRBYTE_WORKSPACE_ID=" "$ENV_FILE" 2>/dev/null; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/^AIRBYTE_WORKSPACE_ID=.*/AIRBYTE_WORKSPACE_ID=${WORKSPACE_ID}/" "$ENV_FILE"
    else
        sed -i "s/^AIRBYTE_WORKSPACE_ID=.*/AIRBYTE_WORKSPACE_ID=${WORKSPACE_ID}/" "$ENV_FILE"
    fi
    echo "Updated AIRBYTE_WORKSPACE_ID in .env"
else
    echo "AIRBYTE_WORKSPACE_ID=${WORKSPACE_ID}" >> "$ENV_FILE"
    echo "Added AIRBYTE_WORKSPACE_ID to .env"
fi

echo ""
echo "=== Done! ==="
echo "Workspace ID:  ${WORKSPACE_ID}"
echo "Azure source:  ${AZURE_SOURCE_ID}  (4 streams: yellow, green, fhv, fhvhv)"
echo "S3 source:     ${S3_SOURCE_ID}  (1 stream: citibike)"
echo "Destination:   ${DEST_ID}"
echo ""
echo "Connections:"
echo "  nyc-taxi-trips       — scheduled monthly on 3rd at 03:00 UTC"
echo "  nyc-citibike-trips   — scheduled monthly on 5th at 03:00 UTC"
echo ""
echo "Now run:  dagster dev -w workspace.yaml"
