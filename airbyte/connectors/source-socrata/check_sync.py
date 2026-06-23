"""Search all schemas for socrata-related tables (pilot sync verification)."""
import json
import psycopg2

conn = psycopg2.connect(
    host="localhost", port=5432, dbname="warehouse", user="dagster", password="dagster"
)
cur = conn.cursor()

# Check row count
cur.execute("SELECT COUNT(*) FROM raw.socrata_records")
total = cur.fetchone()[0]
print(f"Total rows in raw.socrata_records: {total}")

# Compare with existing complaints_311
cur.execute("SELECT COUNT(*) FROM raw.complaints_311")
existing = cur.fetchone()[0]
print(f"Existing raw.complaints_311 row count: {existing}")

# Find all socrata/airbyte tables
cur.execute(
    "SELECT table_schema, table_name FROM information_schema.tables "
    "WHERE table_schema NOT IN ('information_schema','pg_catalog','pg_toast') "
    "AND (table_name LIKE '%%socrata%%' OR table_name LIKE '%%airbyte%%') "
    "ORDER BY table_schema, table_name"
)
print("\nSocrata/Airbyte tables:", cur.fetchall())

# Get all columns
cur.execute(
    "SELECT column_name, data_type FROM information_schema.columns "
    "WHERE table_schema='raw' AND table_name='socrata_records' "
    "ORDER BY ordinal_position"
)
cols = cur.fetchall()
print(f"\nColumns: {cols}")

# Select a full row to see the data
cur.execute("SELECT * FROM raw.socrata_records LIMIT 1")
row = cur.fetchone()
if row:
    for i, v in enumerate(row):
        val_str = str(v)[:500] if v else "NULL"
        col_name = cols[i][0] if i < len(cols) else "?"
        print(f"  col[{i}] ({col_name}): {val_str}")

# Check if there's a _airbyte_data column in any format
cur.execute(
    "SELECT column_name FROM information_schema.columns "
    "WHERE table_schema='raw' AND table_name='socrata_records' "
    "AND column_name LIKE '%%data%%'"
)
data_cols = cur.fetchall()
print(f"\nData columns: {data_cols}")

cur.close()
conn.close()
