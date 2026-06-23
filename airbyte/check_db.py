"""Check bronze table state."""

from sqlalchemy import create_engine, text

from common.config import postgres_settings

engine = create_engine(postgres_settings().dsn)

with engine.connect() as conn:
    tables = conn.execute(
        text(
            "SELECT table_name FROM information_schema.tables WHERE table_schema = 'raw' ORDER BY table_name"
        )
    ).fetchall()
    print("Tables in raw schema:")
    for t in tables:
        count = conn.execute(text(f"SELECT COUNT(*) FROM raw.{t[0]}")).scalar()
        print(f"  raw.{t[0]}: {count} rows")
