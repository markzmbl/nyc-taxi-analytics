#!/usr/bin/env python3
"""
Direct FHVHV taxi data ingestion from TLC CloudFront CDN into Postgres bronze.
FHVHV is NOT in Azure Open Datasets — data lives at d37ci6vzurychx.cloudfront.net.
"""
import argparse
import io
import os
import sys

import pandas as pd
import psycopg2
from sqlalchemy import create_engine, text

# ── Config ──
from common.config import postgres_settings  # noqa: E402

_pg = postgres_settings()
CDN_BASE = "https://d37ci6vzurychx.cloudfront.net/trip-data"
PG_SCHEMA = "raw"
TABLE_NAME = "taxi_trips_fhvhv"
LIMIT_FILES = int(os.environ.get("FHVHV_LIMIT_FILES", "1"))  # 513 MB each!

# ── CL args ──
parser = argparse.ArgumentParser()
parser.add_argument("--limit", type=int, default=LIMIT_FILES)
args = parser.parse_args()
LIMIT_FILES = args.limit

# ── Connect ──
engine = create_engine(_pg.dsn)
with engine.connect() as conn:
    conn.execute(text(f"CREATE SCHEMA IF NOT EXISTS {PG_SCHEMA}"))
    conn.commit()

print(f"FHVHV ingestion from {CDN_BASE}")
print(f"Postgres: {_pg.host}:{_pg.port}/{_pg.db}.{PG_SCHEMA}")
print(f"Files to load: {LIMIT_FILES}")
print()

# ── Build file URLs (2019-02 onward for FHVHV) ──
# FHVHV started Feb 2019
files = []
for m in range(2, 2 + LIMIT_FILES):
    fname = f"fhvhv_tripdata_2019-{m:02d}.parquet"
    files.append(f"{CDN_BASE}/{fname}")

# Read parquet with optional sampling
SAMPLE_ROWS = int(os.environ.get("FHVHV_SAMPLE_ROWS", "0"))  # 0 = all rows

dfs = []
for url in files:
    fname = url.split("/")[-1]
    print(f"Downloading: {fname} ...")
    try:
        df = pd.read_parquet(url)
        print(f"  Read {len(df)} rows, {len(df.columns)} columns")
        if SAMPLE_ROWS > 0 and len(df) > SAMPLE_ROWS:
            df = df.head(SAMPLE_ROWS)
            print(f"  Sampled down to {len(df)} rows")
        dfs.append(df)
    except Exception as e:
        print(f"  ERROR: {e}")
        import traceback

        traceback.print_exc()
        continue

if not dfs:
    print("No data loaded. Aborting.")
    sys.exit(1)

combined = pd.concat(dfs, ignore_index=True)
print(f"Total rows: {len(combined)}")

# ── Write via COPY ──
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

pg_conn = psycopg2.connect(_pg.dsn)
pg_conn.autocommit = True
pg_cur = pg_conn.cursor()
pg_cur.execute(f"DROP TABLE IF EXISTS {PG_SCHEMA}.{TABLE_NAME}")
pg_cur.execute(f"CREATE TABLE {PG_SCHEMA}.{TABLE_NAME} ({', '.join(columns_sql)})")

buf = io.StringIO()
combined.to_csv(buf, index=False, header=False, na_rep="")
buf.seek(0)
cols = [f'"{c.lower().replace(" ", "_").replace("-", "_")}"' for c in combined.columns]
print("Writing to Postgres via COPY...")
pg_cur.copy_expert(
    f"COPY {PG_SCHEMA}.{TABLE_NAME} ({', '.join(cols)}) FROM STDIN WITH CSV",
    buf,
)
pg_cur.close()
pg_conn.close()

print(f"Wrote to {PG_SCHEMA}.{TABLE_NAME} [OK]")

# Verify
with engine.connect() as conn:
    count = conn.execute(
        text(f"SELECT COUNT(*) FROM {PG_SCHEMA}.{TABLE_NAME}")
    ).scalar()
    print(f"Verified: {count} rows in {PG_SCHEMA}.{TABLE_NAME}")
