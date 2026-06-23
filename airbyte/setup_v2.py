#!/usr/bin/env python3
"""
Airbyte Connection Setup for v2.0.2-alpha API.
Idempotent — check-then-create. Uses POST endpoints and v2 field names.
"""

import json
import sys

from airbyte.airbyte_client import AirbyteAPIError, api
from common.config import airbyte_workspace_settings, postgres_settings
from common.datasets import (
    AZURE_STORAGE_ACCOUNT,
    AZURE_TAXI_CONTAINER,
    SOCRATA_DATASETS,
    TAXI_ZONE_LOOKUP_URL,
)

_pg = postgres_settings()
_ws = airbyte_workspace_settings()
WS_ID = _ws.workspace_id


def try_api(method, endpoint, body=None):
    """Lenient API call for non-fatal setup steps.

    Returns the parsed JSON on success, or ``None`` (after logging) on any
    API error.  This preserves the script's "warn and continue" behavior
    while still surfacing HTTP errors that the old curl helper swallowed.
    """
    try:
        return api(method, endpoint, body)
    except AirbyteAPIError as exc:
        print(f"  ERROR: {exc}")
        return None


def list_resources(resource_type):
    """List resources of given type. Returns dict keyed by name -> id."""
    endpoint = f"/{resource_type}/list"
    data = try_api("POST", endpoint, {"workspaceId": WS_ID})
    if not data:
        return {}
    # Response keys: "sources", "destinations", "connections"
    key = resource_type
    items = data.get(key, [])
    result = {}
    id_field = resource_type[:-1] + "Id"  # sources -> sourceId
    for item in items:
        result[item.get("name")] = item.get(id_field)
    return result


def create_or_reuse(resource_type, name, config):
    """Create resource if not exists, return its ID."""
    existing = list_resources(resource_type)
    if name in existing:
        rid = existing[name]
        print(f"  {resource_type[:-1]} '{name}' already exists ({rid}), reusing.")
        return rid

    # Build create body — v1 API uses "connectionConfiguration"
    if resource_type == "sources":
        body = {
            "workspaceId": WS_ID,
            "name": name,
            "sourceDefinitionId": config["sourceDefinitionId"],
            "connectionConfiguration": config["connectionConfiguration"],
        }
    elif resource_type == "destinations":
        body = {
            "workspaceId": WS_ID,
            "name": name,
            "destinationDefinitionId": config["destinationDefinitionId"],
            "connectionConfiguration": config["connectionConfiguration"],
        }
    elif resource_type == "connections":
        body = config  # already built with all fields
    else:
        raise ValueError(f"Unknown resource type: {resource_type}")

    endpoint = f"/{resource_type}/create"
    data = try_api("POST", endpoint, body)
    if not data:
        print(f"  ERROR: Failed to create {resource_type[:-1]} '{name}'")
        return None

    id_field = resource_type[:-1] + "Id"
    rid = data.get(id_field)
    if rid:
        print(f"  {resource_type[:-1]} '{name}' created: {rid}")
        return rid
    else:
        print(f"  ERROR: No {id_field} in response: {json.dumps(data, indent=2)[:500]}")
        return None


# ── 1. Postgres Destination ──
print("=== 1. PostgreSQL Destination ===")
DEST_ID = create_or_reuse(
    "destinations",
    "warehouse-postgres",
    {
        # Stable published connector-definition id (same across OSS installs).
        "destinationDefinitionId": "25c5221d-dce2-4163-ade9-739ef790f503",
        "connectionConfiguration": {
            # Host as seen *from the Airbyte process* (env-specific).
            "host": _ws.dest_postgres_host,
            "port": _pg.port,
            "database": _pg.db,
            "schema": "raw",
            "username": _pg.user,
            "password": _pg.password,
            "ssl_mode": {"mode": "disable"},
            "tunnel_method": {"tunnel_method": "NO_TUNNEL"},
        },
    },
)
if not DEST_ID:
    print("FATAL: Could not create destination")
    sys.exit(1)

# ── 2. Azure Blob Storage Source (TLC taxi) ──
print("\n=== 2. Azure Blob Storage Source (TLC Taxi) ===")
AZURE_SOURCE_ID = create_or_reuse(
    "sources",
    "azure-blob-storage",
    {
        "sourceDefinitionId": "fdaaba68-4875-4ed9-8fcd-4ae1e0a25093",
        "connectionConfiguration": {
            "azure_blob_storage_account_name": AZURE_STORAGE_ACCOUNT,
            "azure_blob_storage_container_name": AZURE_TAXI_CONTAINER,
            "azure_blob_storage_endpoint": "blob.core.windows.net",
            "credentials": {
                "auth_type": "storage_account_key",
                "azure_blob_storage_account_key": "dummy-key-for-public-container",
            },
            "start_date": "2009-01-01T00:00:00Z",
            "streams": [
                {
                    "name": "taxi_trips",
                    "format": {"filetype": "parquet"},
                    "globs": ["yellow/puYear=*/puMonth=*/*.parquet"],
                    "schemaless": True,
                },
                {
                    "name": "taxi_trips_green",
                    "format": {"filetype": "parquet"},
                    "globs": ["green/puYear=*/puMonth=*/*.parquet"],
                    "schemaless": True,
                },
                {
                    "name": "taxi_trips_fhv",
                    "format": {"filetype": "parquet"},
                    "globs": ["fhv/puYear=*/puMonth=*/*.parquet"],
                    "schemaless": True,
                },
                {
                    "name": "taxi_trips_fhvhv",
                    "format": {"filetype": "parquet"},
                    "globs": ["fhvhv/puYear=*/puMonth=*/*.parquet"],
                    "schemaless": True,
                },
            ],
        },
    },
)
if not AZURE_SOURCE_ID:
    print("WARNING: Could not create Azure source, continuing...")

# ── 3. File Source (Taxi Zone Lookup) ──
print("\n=== 3. File Source (Taxi Zone Lookup) ===")
ZONE_SOURCE_ID = create_or_reuse(
    "sources",
    "tlc-zone-lookup",
    {
        "sourceDefinitionId": "778daa7c-feaf-4db6-96f3-70fd645acc77",
        "connectionConfiguration": {
            "url": TAXI_ZONE_LOOKUP_URL,
            "format": "csv",
            "dataset_name": "taxi_zone_lookup",
            "provider": {"storage": "HTTPS"},
        },
    },
)
if not ZONE_SOURCE_ID:
    print("WARNING: Could not create zone lookup source, continuing...")

# ── 3b. Socrata Custom Source Definition ──
print("\n=== 3b. Socrata Custom Source Definition ===")
# Register the custom Socrata connector (built from airbyte/connectors/source-socrata/).
# The Docker image must be built and loaded into Kind before running this script:
#   docker build -t source-socrata:dev airbyte/connectors/source-socrata/
#   kind load docker-image source-socrata:dev --name nyc-taxi-dev
SOCRATA_DEF_ID = None
existing_defs = try_api("POST", "/source_definitions/list", {"workspaceId": WS_ID})
if existing_defs:
    for sd in existing_defs.get("sourceDefinitions", []):
        if sd.get("name") == "Socrata":
            SOCRATA_DEF_ID = sd["sourceDefinitionId"]
            print(
                f"  Socrata source definition already exists ({SOCRATA_DEF_ID}), reusing."
            )
            break
if not SOCRATA_DEF_ID:
    resp = try_api(
        "POST",
        "/source_definitions/create_custom",
        {
            "workspaceId": WS_ID,
            "sourceDefinition": {
                "name": "Socrata",
                "dockerRepository": "source-socrata",
                "dockerImageTag": "dev",
                "documentationUrl": "https://dev.socrata.com/docs/queries/",
            },
        },
    )
    if resp:
        SOCRATA_DEF_ID = resp.get("sourceDefinition", {}).get("sourceDefinitionId")
        if SOCRATA_DEF_ID:
            print(f"  Socrata source definition created: {SOCRATA_DEF_ID}")
        else:
            print(f"  ERROR: unexpected response: {json.dumps(resp)[:300]}")
    else:
        print("  ERROR: Could not create Socrata source definition")

# ── 3c. Socrata Sources (roster lives in common.datasets) ──
print("\n=== 3c. Socrata Sources ===")
SOCRATA_SOURCE_IDS: dict[str, str] = {}
if SOCRATA_DEF_ID:
    for ds in SOCRATA_DATASETS:
        sid = create_or_reuse(
            "sources",
            ds.name,
            {
                "sourceDefinitionId": SOCRATA_DEF_ID,
                "connectionConfiguration": {
                    "domain": ds.domain,
                    "resource_id": ds.resource_id,
                    "cursor_field": ds.cursor_field,
                    "start_date": "2023-01-01T00:00:00",
                },
            },
        )
        if sid:
            SOCRATA_SOURCE_IDS[ds.name] = sid
        else:
            print(f"  WARNING: Could not create source '{ds.name}'")
else:
    print("  SKIP Socrata sources: no source definition")

# ── 4. Connections ──
print("\n=== 4. Connections ===")


def build_sync_catalog(streams_config):
    """Build syncCatalog for v2 API from stream configurations."""
    streams = []
    for sc in streams_config:
        stream = {
            "stream": {
                "name": sc["name"],
                "jsonSchema": sc.get("jsonSchema", {}),
                "supportedSyncModes": ["full_refresh", "incremental"],
                "sourceDefinedCursor": "cursorField" in sc,
                "defaultCursorField": sc.get("cursorField", []),
                "sourceDefinedPrimaryKey": sc.get("primaryKey", []),
            },
            "config": {
                "selected": True,
                "syncMode": sc["syncMode"],
                "cursorField": sc.get("cursorField", []),
                "destinationSyncMode": sc["destinationSyncMode"],
                "primaryKey": sc.get("primaryKey", []),
                "aliasName": sc["name"],
                "suggested": False,
                "includeFiles": False,
                "fieldSelectionEnabled": False,
                "selectedFields": [],
                "hashedFields": [],
                "mappers": [],
            },
        }
        streams.append(stream)
    return {"streams": streams}


# Union of all Socrata field names across the 4 datasets. The Airbyte Postgres
# destination requires explicit jsonSchema properties to create typed columns;
# an empty properties:{} results in tables with only _airbyte_* metadata columns.
SOCRATA_JSON_SCHEMA = {
    "type": "object",
    "additionalProperties": True,
    "properties": {
        "unique_key": {"type": ["null", "string"]},
        "created_date": {"type": ["null", "string"]},
        "closed_date": {"type": ["null", "string"]},
        "complaint_type": {"type": ["null", "string"]},
        "descriptor": {"type": ["null", "string"]},
        "borough": {"type": ["null", "string"]},
        "agency": {"type": ["null", "string"]},
        "status": {"type": ["null", "string"]},
        "latitude": {"type": ["null", "string"]},
        "longitude": {"type": ["null", "string"]},
        "incident_zip": {"type": ["null", "string"]},
        "cmplnt_num": {"type": ["null", "string"]},
        "cmplnt_fr_dt": {"type": ["null", "string"]},
        "cmplnt_fr_tm": {"type": ["null", "string"]},
        "boro_nm": {"type": ["null", "string"]},
        "ofns_desc": {"type": ["null", "string"]},
        "start_date_time": {"type": ["null", "string"]},
        "end_date_time": {"type": ["null", "string"]},
        "event_id": {"type": ["null", "string"]},
        "event_name": {"type": ["null", "string"]},
        "event_type": {"type": ["null", "string"]},
        "camis": {"type": ["null", "string"]},
        "dba": {"type": ["null", "string"]},
        "inspection_date": {"type": ["null", "string"]},
        "inspection_type": {"type": ["null", "string"]},
        "violation_code": {"type": ["null", "string"]},
        "violation_description": {"type": ["null", "string"]},
        "critical_flag": {"type": ["null", "string"]},
        "grade": {"type": ["null", "string"]},
        "score": {"type": ["null", "string"]},
        "grade_date": {"type": ["null", "string"]},
        "record_date": {"type": ["null", "string"]},
        "cuisine_description": {"type": ["null", "string"]},
        "building": {"type": ["null", "string"]},
        "street": {"type": ["null", "string"]},
        "zipcode": {"type": ["null", "string"]},
        "phone": {"type": ["null", "string"]},
        "action": {"type": ["null", "string"]},
        "_socrata_resource_id": {"type": ["null", "string"]},
        "_socrata_domain": {"type": ["null", "string"]},
    },
}


# 4a. NYC Taxi Trips
if AZURE_SOURCE_ID:
    print("Creating nyc-taxi-trips connection...")
    CONN1_ID = create_or_reuse(
        "connections",
        "nyc-taxi-trips",
        {
            "workspaceId": WS_ID,
            "name": "nyc-taxi-trips",
            "sourceId": AZURE_SOURCE_ID,
            "destinationId": DEST_ID,
            "scheduleType": "manual",
            "syncCatalog": build_sync_catalog(
                [
                    {
                        "name": "taxi_trips",
                        "syncMode": "incremental",
                        "cursorField": ["tpep_pickup_datetime"],
                        "destinationSyncMode": "append_dedup",
                        "primaryKey": [
                            ["VendorID"],
                            ["tpep_pickup_datetime"],
                            ["PULocationID"],
                        ],
                    },
                    {
                        "name": "taxi_trips_green",
                        "syncMode": "incremental",
                        "cursorField": ["lpep_pickup_datetime"],
                        "destinationSyncMode": "append_dedup",
                        "primaryKey": [
                            ["VendorID"],
                            ["lpep_pickup_datetime"],
                            ["PULocationID"],
                        ],
                    },
                    {
                        "name": "taxi_trips_fhv",
                        "syncMode": "incremental",
                        "cursorField": ["pickup_datetime"],
                        "destinationSyncMode": "append_dedup",
                        "primaryKey": [
                            ["dispatching_base_num"],
                            ["pickup_datetime"],
                            ["PULocationID"],
                        ],
                    },
                    {
                        "name": "taxi_trips_fhvhv",
                        "syncMode": "incremental",
                        "cursorField": ["pickup_datetime"],
                        "destinationSyncMode": "append_dedup",
                        "primaryKey": [
                            ["hvfhs_license_num"],
                            ["pickup_datetime"],
                            ["PULocationID"],
                        ],
                    },
                ]
            ),
        },
    )
    if CONN1_ID:
        print(f"  nyc-taxi-trips: {CONN1_ID}")
else:
    print("  SKIP nyc-taxi-trips: no Azure source")

# 4b. Taxi Zone Lookup
if ZONE_SOURCE_ID:
    print("Creating nyc-taxi-zone-lookup connection...")
    CONN2_ID = create_or_reuse(
        "connections",
        "nyc-taxi-zone-lookup",
        {
            "workspaceId": WS_ID,
            "name": "nyc-taxi-zone-lookup",
            "sourceId": ZONE_SOURCE_ID,
            "destinationId": DEST_ID,
            "scheduleType": "manual",
            "syncCatalog": build_sync_catalog(
                [
                    {
                        "name": "taxi_zone_lookup",
                        "syncMode": "full_refresh",
                        "cursorField": [],
                        "destinationSyncMode": "overwrite",
                        "primaryKey": [],
                    }
                ]
            ),
        },
    )
    if CONN2_ID:
        print(f"  nyc-taxi-zone-lookup: {CONN2_ID}")
else:
    print("  SKIP nyc-taxi-zone-lookup: no zone source")

# 4c. Citi Bike — skipped (no S3 connector)
print("\n  SKIP nyc-citibike-trips: S3 source connector not installed in this Airbyte")

# 4d. Socrata Connections (4 datasets)
print("\n=== 4d. Socrata Connections ===")
# Each Socrata source gets its own connection with a unique prefix so data
# lands in separate tables (aliasName is not respected by the API in this
# Airbyte version; prefix is the workaround).
# Tables created: raw.{prefix}socrata_records
# Katara's dbt staging models need updating to read from these flat tables.
for ds in SOCRATA_DATASETS:
    src_id = SOCRATA_SOURCE_IDS.get(ds.name)
    if not src_id:
        print(f"  SKIP {ds.name}: no source")
        continue
    print(f"Creating {ds.name} connection...")
    conn_id = create_or_reuse(
        "connections",
        ds.name,
        {
            "workspaceId": WS_ID,
            "name": ds.name,
            "sourceId": src_id,
            "destinationId": DEST_ID,
            "scheduleType": "manual",
            "namespaceDefinition": "source",
            "namespaceFormat": "raw",
            "prefix": ds.table_prefix,
            "syncCatalog": build_sync_catalog(
                [
                    {
                        "name": "socrata_records",
                        "jsonSchema": SOCRATA_JSON_SCHEMA,
                        "syncMode": "incremental",
                        "cursorField": [ds.cursor_field],
                        "destinationSyncMode": "append",
                        "primaryKey": [["unique_key"]],
                    }
                ]
            ),
        },
    )
    if conn_id:
        # Connections created via API start inactive — activate them.
        try_api(
            "POST",
            "/connections/update",
            {
                "connectionId": conn_id,
                "status": "active",
            },
        )
        print(f"  {ds.name}: {conn_id} (prefix={ds.table_prefix})")

print("\n=== Setup Complete ===")
print(f"  Destination: {DEST_ID}")
print(f"  Azure source: {AZURE_SOURCE_ID}")
print(f"  Zone source:  {ZONE_SOURCE_ID}")
print(f"  Socrata sources: {', '.join(SOCRATA_SOURCE_IDS.keys())}")
print(
    f"  Connections: nyc-taxi-trips, nyc-taxi-zone-lookup, "
    f"{', '.join(SOCRATA_SOURCE_IDS.keys())}"
)
print("  Skipped: nyc-citibike-trips (S3 connector unavailable)")
