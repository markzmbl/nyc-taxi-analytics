#!/usr/bin/env python3
"""
Direct TLC taxi data ingestion into Postgres bronze (raw schema).
Bypasses Airbyte for Azure Blob Storage public containers
since Airbyte v2.0.2-alpha connector lacks anonymous access support.

Reads parquet from: https://azureopendatastorage.blob.core.windows.net/nyctlc/
Writes to: raw.{yellow,green,fhv,fhvhv}_trips in warehouse Postgres
"""
import argparse
import os
import sys

# Install azure-storage-blob if needed
try:
    from azure.storage.blob import ContainerClient
except ImportError:
    print("Installing azure-storage-blob...")
    import subprocess

    subprocess.check_call(
        [sys.executable, "-m", "pip", "install", "azure-storage-blob", "-q"]
    )
    from azure.storage.blob import ContainerClient

import pandas as pd
from sqlalchemy import create_engine, text

# ── Config ──
from common.config import postgres_settings  # noqa: E402
from common.datasets import AZURE_STORAGE_ACCOUNT, AZURE_TAXI_CONTAINER  # noqa: E402

_pg = postgres_settings()
ACCOUNT_URL = f"https://{AZURE_STORAGE_ACCOUNT}.blob.core.windows.net"
CONTAINER = AZURE_TAXI_CONTAINER
PG_SCHEMA = "raw"
LIMIT_FILES = int(os.environ.get("TLC_LIMIT_FILES", "2"))  # files per stream for demo

STREAMS = {
    "yellow": {
        "prefixes": [f"yellow/puYear=2019/puMonth={m}/" for m in range(1, 3)],
        "table": "taxi_trips",
    },
    "green": {
        "prefixes": [f"green/puYear=2019/puMonth={m}/" for m in range(1, 3)],
        "table": "taxi_trips_green",
    },
    "fhv": {
        "prefixes": [f"fhv/puYear=2019/puMonth={m}/" for m in range(1, 3)],
        "table": "taxi_trips_fhv",
    },
    "fhvhv": {
        "prefixes": [f"fhvhv/puYear=2019/puMonth={m}/" for m in range(1, 3)],
        "table": "taxi_trips_fhvhv",
    },
}

# ── Connect ──
engine = create_engine(_pg.dsn)

# Ensure raw schema exists
with engine.connect() as conn:
    conn.execute(text(f"CREATE SCHEMA IF NOT EXISTS {PG_SCHEMA}"))
    conn.commit()

# ── Container client (anonymous access for public containers) ──
container_client = ContainerClient(
    account_url=ACCOUNT_URL,
    container_name=CONTAINER,
    credential=None,  # anonymous access
)

print(f"Connected to {ACCOUNT_URL}/{CONTAINER}")
print(f"Postgres: {_pg.host}:{_pg.port}/{_pg.db}.{PG_SCHEMA}")
print(f"Files per stream: {LIMIT_FILES} (set TLC_LIMIT_FILES env var to change)")
print()

# ── CL args ──
parser = argparse.ArgumentParser(
    description="Ingest TLC taxi data into Postgres bronze"
)
parser.add_argument(
    "--dataset",
    type=str,
    default=None,
    help="Dataset to ingest: yellow, green, fhv, fhvhv (omit for all)",
)
args = parser.parse_args()

# Filter streams if --dataset specified
streams_to_run = STREAMS
if args.dataset:
    if args.dataset in STREAMS:
        streams_to_run = {args.dataset: STREAMS[args.dataset]}
    else:
        print(
            f"ERROR: Unknown dataset '{args.dataset}'. Choices: {list(STREAMS.keys())}"
        )
        sys.exit(1)

results = {}

for stream_key, cfg in streams_to_run.items():
    prefixes = cfg["prefixes"]
    table_name = cfg["table"]
    print(f"=== {stream_key} -> {PG_SCHEMA}.{table_name} ===")

    # List blobs across all prefixes
    blobs = []
    for prefix in prefixes:
        blob_iter = container_client.list_blobs(name_starts_with=prefix)
        for i, blob in enumerate(blob_iter):
            if blob.name.endswith(".parquet"):
                blobs.append(blob)
            if len(blobs) >= LIMIT_FILES:
                break
            if i > 100:
                break
        if len(blobs) >= LIMIT_FILES:
            break
    print(f"  Parquet files found: {len(blobs)}")

    if not blobs:
        print("  No parquet files found, skipping.")
        results[stream_key] = 0
        continue

    # Read parquet files
    dfs = []
    for blob in blobs:
        blob_name = blob.name
        blob_url = f"{ACCOUNT_URL}/{CONTAINER}/{blob_name}"
        print(f"  Reading: {blob_name} ({blob.size / 1024 / 1024:.1f} MB)")
        try:
            df = pd.read_parquet(blob_url)
            dfs.append(df)
        except Exception as e:
            print(f"  ERROR reading {blob_name}: {e}")
            continue

    if not dfs:
        print("  No data read, skipping.")
        results[stream_key] = 0
        continue

    combined = pd.concat(dfs, ignore_index=True)
    print(f"  Total rows: {len(combined)}")

    # Write to Postgres using COPY for speed
    import io as _io

    import psycopg2

    # Drop + recreate table with schema from dataframe
    dtypes_map = {
        "int64": "BIGINT",
        "float64": "DOUBLE PRECISION",
        "object": "TEXT",
        "bool": "BOOLEAN",
        "datetime64[ns]": "TIMESTAMP",
    }
    columns_sql = []
    for col in combined.columns:
        pg_type = dtypes_map.get(str(combined[col].dtype), "TEXT")
        col_clean = col.lower().replace(" ", "_").replace("-", "_")
        columns_sql.append(f'"{col_clean}" {pg_type}')

    with engine.connect() as conn:
        conn.execute(text(f"DROP TABLE IF EXISTS {PG_SCHEMA}.{table_name}"))
    engine.dispose()

    pg_conn = psycopg2.connect(_pg.dsn)
    pg_conn.autocommit = True
    pg_cur = pg_conn.cursor()
    pg_cur.execute(f"CREATE TABLE {PG_SCHEMA}.{table_name} ({', '.join(columns_sql)})")

    # Write CSV to buffer and COPY
    buf = _io.StringIO()
    combined.to_csv(buf, index=False, header=False, na_rep="")
    buf.seek(0)
    cols = [
        f'"{c.lower().replace(" ", "_").replace("-", "_")}"' for c in combined.columns
    ]
    pg_cur.copy_expert(
        f"COPY {PG_SCHEMA}.{table_name} ({', '.join(cols)}) FROM STDIN WITH CSV", buf
    )
    pg_cur.close()
    pg_conn.close()

    print(f"  Wrote to {PG_SCHEMA}.{table_name} [OK] via COPY")
    results[stream_key] = len(combined)

print()
print("=== Ingestion Results ===")
for stream_key, count in results.items():
    print(f"  {stream_key}: {count} rows")

# ── Verify ──
print()
print("=== Postgres Tables ===")
with engine.connect() as conn:
    tables = conn.execute(
        text(
            f"SELECT table_name FROM information_schema.tables WHERE table_schema = '{PG_SCHEMA}' ORDER BY table_name"
        )
    ).fetchall()
    for t in tables:
        print(f"  {t[0]}")

print()
print("Done! TLC data loaded directly into bronze.")
