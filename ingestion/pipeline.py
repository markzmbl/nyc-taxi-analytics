"""Build a dlt pipeline whose destination follows the active stack."""

from __future__ import annotations

from typing import Any

import dlt

from common.config import (
    WarehouseEngine,
    clickhouse_settings,
    duckdb_settings,
    motherduck_settings,
    stack_settings,
)

# ClickHouse native protocol port (HTTP port comes from CLICKHOUSE_PORT).
_CLICKHOUSE_NATIVE_PORT = 9000


def _destination() -> Any:
    """Resolve the dlt destination for the active warehouse engine."""
    engine = stack_settings().warehouse
    if engine is WarehouseEngine.duckdb:
        return dlt.destinations.duckdb(duckdb_settings().path)
    if engine is WarehouseEngine.motherduck:
        return dlt.destinations.motherduck(motherduck_settings().duckdb_path)
    if engine is WarehouseEngine.clickhouse:
        ch = clickhouse_settings()
        return dlt.destinations.clickhouse(
            credentials={
                "host": ch.host,
                "port": _CLICKHOUSE_NATIVE_PORT,
                "http_port": ch.port,
                "username": ch.user,
                "password": ch.password,
                "database": ch.database,
                "secure": 1 if ch.secure else 0,
            }
        )
    raise ValueError(f"Unsupported warehouse engine: {engine}")


def build_pipeline(
    pipeline_name: str = "demo", dataset_name: str = "raw"
) -> dlt.Pipeline:
    """Create a dlt pipeline that lands data in the active warehouse's raw schema."""
    return dlt.pipeline(
        pipeline_name=pipeline_name,
        destination=_destination(),
        dataset_name=dataset_name,
    )
