#!/usr/bin/env python3
"""Direct taxi zone lookup CSV ingestion into Postgres."""
import pandas as pd
from sqlalchemy import create_engine, text

from common.config import postgres_settings
from common.datasets import TAXI_ZONE_LOOKUP_URL

_pg = postgres_settings()
PG_SCHEMA = "raw"
URL = TAXI_ZONE_LOOKUP_URL

engine = create_engine(_pg.dsn)

with engine.connect() as conn:
    conn.execute(text(f"CREATE SCHEMA IF NOT EXISTS {PG_SCHEMA}"))
    conn.commit()

print(f"Loading {URL}...")
df = pd.read_csv(URL)
print(f"  Rows: {len(df)}, Columns: {list(df.columns)}")

df.to_sql(
    "taxi_zone_lookup",
    engine,
    schema=PG_SCHEMA,
    if_exists="replace",
    index=False,
)
print(f"  Wrote to {PG_SCHEMA}.taxi_zone_lookup ✓")

# Verify
with engine.connect() as conn:
    count = conn.execute(
        text(f"SELECT COUNT(*) FROM {PG_SCHEMA}.taxi_zone_lookup")
    ).scalar()
    print(f"  Verified: {count} rows in {PG_SCHEMA}.taxi_zone_lookup")
