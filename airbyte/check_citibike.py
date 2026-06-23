"""Check citibike_trips schema."""

from sqlalchemy import create_engine, text

from common.config import postgres_settings

engine = create_engine(postgres_settings().dsn)
with engine.connect() as conn:
    cols = conn.execute(
        text(
            "SELECT column_name, data_type FROM information_schema.columns "
            "WHERE table_schema = 'raw' AND table_name = 'citibike_trips' "
            "ORDER BY ordinal_position"
        )
    ).fetchall()
    if cols:
        for c in cols:
            print(f"  {c[0]}: {c[1]}")
    else:
        print("  No columns found — table may be empty or schema not created")
    count = conn.execute(text("SELECT COUNT(*) FROM raw.citibike_trips")).scalar()
    print(f"  Row count: {count}")
