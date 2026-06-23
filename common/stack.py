"""Active-stack resolution.

``common.config`` holds the raw per-engine settings; this module answers
"which warehouse is active and what are its settings" in one place, so code
that needs the live engine (e.g. an Atelier bootstrap creating a ClickHouse
database, a health check) doesn't re-implement the engine switch.

The two consumer-specific mappings live where their dependency lives, not here:
  * dbt target  -> ``transform/profiles.yml`` (selected by ``STACK_WAREHOUSE``)
  * dlt destination -> ``ingestion/pipeline.py`` (owns the dlt dependency)
"""

from __future__ import annotations

from common.config import (
    ClickHouseSettings,
    DuckDBSettings,
    MotherDuckSettings,
    WarehouseEngine,
    clickhouse_settings,
    duckdb_settings,
    motherduck_settings,
    stack_settings,
)

WarehouseSettings = DuckDBSettings | MotherDuckSettings | ClickHouseSettings


def active_warehouse() -> WarehouseSettings:
    """Return the settings object for the currently selected engine."""
    engine = stack_settings().warehouse
    if engine is WarehouseEngine.duckdb:
        return duckdb_settings()
    if engine is WarehouseEngine.motherduck:
        return motherduck_settings()
    if engine is WarehouseEngine.clickhouse:
        return clickhouse_settings()
    raise ValueError(f"Unsupported warehouse engine: {engine}")
