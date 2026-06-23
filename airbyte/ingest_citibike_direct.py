#!/usr/bin/env python3
"""
Direct Citi Bike trip data ingestion from the public S3 bucket (tripdata)
into Postgres bronze (raw.citibike_trips).

Airbyte connection `nyc-citibike-trips` is currently not loading data
(Airbyte pods flaky — see Iroh's stability work).  This script bypasses
Airbyte entirely and loads directly from S3.

The S3 bucket `tripdata` publishes:
  - Annual NYC zip files (2013-2023): 200MB-1.5GB, old column format
  - Monthly NYC zip files (2024+): 350MB-960MB, new column format
  - Monthly JC (Jersey City) zip files: 0.1-3.3MB

The existing raw.citibike_trips table uses the OLD column format
(spaces in names: "start station id", "starttime", etc.).  JC files
from 2015-2020 use this same format, so we load those for schema
compatibility.  Even a few months of JC data is sufficient for demo
purposes (the dbt source only requires `starttime` to be not_null).

Usage:
    python airbyte/ingest_citibike_direct.py
    python airbyte/ingest_citibike_direct.py --months 6
    python airbyte/ingest_citibike_direct.py --start 2019-01 --end 2019-06
"""
import argparse
import csv
import io
import sys
import zipfile

import psycopg2
import requests
from sqlalchemy import create_engine, text

# ── Config ──
from common.config import postgres_settings  # noqa: E402

_pg = postgres_settings()
S3_BASE = "https://s3.amazonaws.com/tripdata"
PG_SCHEMA = "raw"
TABLE_NAME = "citibike_trips"

# Old-format JC files (pre-2021) match the existing table schema exactly.
# These are the columns in the existing raw.citibike_trips table:
#   tripduration, starttime, stoptime, start station id, start station name,
#   start station latitude, start station longitude, end station id,
#   end station name, end station latitude, end station longitude,
#   bikeid, usertype, birth year, gender
EXPECTED_COLUMNS = [
    "tripduration",
    "starttime",
    "stoptime",
    "start station id",
    "start station name",
    "start station latitude",
    "start station longitude",
    "end station id",
    "end station name",
    "end station latitude",
    "end station longitude",
    "bikeid",
    "usertype",
    "birth year",
    "gender",
]

# Default: load 2 months of JC data (2019-01, 2019-02)
DEFAULT_MONTHS = [
    "201901",
    "201902",
]


def build_file_list(start: str | None, end: str | None, months: int) -> list[str]:
    """Build list of JC file keys to download."""
    if start and end:
        # Parse YYYY-MM format
        sy, sm = map(int, start.split("-"))
        ey, em = map(int, end.split("-"))
        result = []
        y, m = sy, sm
        while (y, m) <= (ey, em):
            result.append(f"{y:04d}{m:02d}")
            m += 1
            if m > 12:
                m = 1
                y += 1
        return result
    else:
        return DEFAULT_MONTHS[:months]


def download_and_extract(key: str) -> list[dict] | None:
    """Download a JC zip file from S3 and return rows as dicts."""
    # Try .csv.zip extension first, then .zip
    for ext in [".csv.zip", ".zip"]:
        url = f"{S3_BASE}/JC-{key}-citibike-tripdata{ext}"
        r = requests.get(url, timeout=120)
        if r.status_code == 200:
            break
    else:
        print(f"  ERROR: Could not download JC-{key} (tried .csv.zip and .zip)")
        return None

    size_mb = len(r.content) / 1024 / 1024
    print(f"  Downloaded JC-{key}-citibike-tripdata ({size_mb:.1f} MB)")

    try:
        zf = zipfile.ZipFile(io.BytesIO(r.content))
    except zipfile.BadZipFile as e:
        print(f"  ERROR: Bad zip file: {e}")
        return None

    # Find the CSV file inside the zip
    csv_names = [
        n for n in zf.namelist() if n.endswith(".csv") and not n.startswith("__MACOSX")
    ]
    if not csv_names:
        print("  ERROR: No CSV file found in zip")
        return None

    csv_name = csv_names[0]
    with zf.open(csv_name) as f:
        reader = csv.DictReader(io.TextIOWrapper(f, encoding="utf-8"))
        # Verify header matches expected schema
        actual_cols = reader.fieldnames
        if actual_cols != EXPECTED_COLUMNS:
            print("  WARNING: Column mismatch!")
            print(f"    Expected: {EXPECTED_COLUMNS}")
            print(f"    Actual:   {actual_cols}")
            # Try to map anyway if it's the new format
            if actual_cols and "started_at" in actual_cols:
                print("  Detected new-format file — mapping columns...")
                rows = []
                for row in reader:
                    mapped = {
                        "tripduration": "",
                        "starttime": row.get("started_at", ""),
                        "stoptime": row.get("ended_at", ""),
                        "start station id": row.get("start_station_id", ""),
                        "start station name": row.get("start_station_name", ""),
                        "start station latitude": row.get("start_lat", ""),
                        "start station longitude": row.get("start_lng", ""),
                        "end station id": row.get("end_station_id", ""),
                        "end station name": row.get("end_station_name", ""),
                        "end station latitude": row.get("end_lat", ""),
                        "end station longitude": row.get("end_lng", ""),
                        "bikeid": row.get("ride_id", ""),
                        "usertype": row.get("member_casual", ""),
                        "birth year": "",
                        "gender": "",
                    }
                    rows.append(mapped)
                return rows
            return None

        rows = list(reader)
        return rows


def main():
    parser = argparse.ArgumentParser(
        description="Ingest Citi Bike trips from S3 into Postgres bronze"
    )
    parser.add_argument(
        "--months", type=int, default=2, help="Number of months to load (default: 2)"
    )
    parser.add_argument(
        "--start", type=str, default=None, help="Start month YYYY-MM (e.g., 2019-01)"
    )
    parser.add_argument(
        "--end", type=str, default=None, help="End month YYYY-MM (e.g., 2019-06)"
    )
    args = parser.parse_args()

    # ── Connect ──
    engine = create_engine(_pg.dsn)
    with engine.connect() as conn:
        conn.execute(text(f"CREATE SCHEMA IF NOT EXISTS {PG_SCHEMA}"))
        conn.commit()

    print("Citi Bike direct ingestion from S3 bucket: tripdata")
    print(f"Postgres: {_pg.host}:{_pg.port}/{_pg.db}.{PG_SCHEMA}.{TABLE_NAME}")
    print()

    # Build file list
    keys = build_file_list(args.start, args.end, args.months)
    print(f"Files to load: {len(keys)} months")
    print(f"  Keys: {keys}")
    print()

    # Download and collect all rows
    all_rows = []
    for key in keys:
        print(f"=== JC-{key} ===")
        rows = download_and_extract(key)
        if rows is None:
            continue
        print(f"  Rows: {len(rows)}")
        all_rows.extend(rows)

    if not all_rows:
        print("\nNo data loaded. Aborting.")
        sys.exit(1)

    print(f"\nTotal rows: {len(all_rows)}")

    # ── Write to Postgres via COPY ──
    # The table already exists with the old-format column names (with spaces).
    # We use psycopg2 COPY for fast bulk insert.
    pg_conn = psycopg2.connect(_pg.dsn)
    pg_conn.autocommit = True
    pg_cur = pg_conn.cursor()

    # Truncate existing data (full refresh for demo)
    pg_cur.execute(f"TRUNCATE TABLE {PG_SCHEMA}.{TABLE_NAME}")
    print(f"Truncated {PG_SCHEMA}.{TABLE_NAME}")

    # Build CSV buffer and COPY
    buf = io.StringIO()
    writer = csv.DictWriter(buf, fieldnames=EXPECTED_COLUMNS, extrasaction="ignore")
    for row in all_rows:
        writer.writerow(row)
    buf.seek(0)

    # Column names with spaces need double-quoting
    cols_sql = ", ".join(f'"{c}"' for c in EXPECTED_COLUMNS)
    pg_cur.copy_expert(
        f"COPY {PG_SCHEMA}.{TABLE_NAME} ({cols_sql}) FROM STDIN WITH CSV",
        buf,
    )
    pg_cur.close()
    pg_conn.close()

    print(f"Wrote {len(all_rows)} rows to {PG_SCHEMA}.{TABLE_NAME} [OK]")

    # ── Verify ──
    with engine.connect() as conn:
        count = conn.execute(
            text(f"SELECT COUNT(*) FROM {PG_SCHEMA}.{TABLE_NAME}")
        ).scalar()
        print(f"\nVerified: {count} rows in {PG_SCHEMA}.{TABLE_NAME}")

        # Check starttime not_null
        null_count = conn.execute(
            text(
                f"SELECT COUNT(*) FROM {PG_SCHEMA}.{TABLE_NAME} WHERE starttime IS NULL OR starttime = ''"
            )
        ).scalar()
        print(f"Null/empty starttime: {null_count}")

        # Sample
        sample = conn.execute(
            text(
                f'SELECT starttime, "start station name", "end station name" '
                f"FROM {PG_SCHEMA}.{TABLE_NAME} LIMIT 3"
            )
        ).fetchall()
        print("\nSample rows:")
        for s in sample:
            print(f"  {s[0]} | {s[1]} -> {s[2]}")

    print("\nDone! Citi Bike data loaded directly into bronze.")


if __name__ == "__main__":
    main()
