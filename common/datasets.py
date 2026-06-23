"""Central registry of ingestion datasets and Airbyte connection names.

Single source of truth for the Socrata dataset roster and the Airbyte
connection names, imported by both the setup/sync scripts (``airbyte/``)
and the Dagster asset graph (``orchestration/``).  Previously this roster
was copy-pasted across three files.
"""

from __future__ import annotations

from pydantic import BaseModel

# ── Public dataset endpoints (stable, non-environment-specific) ─────────────
NYC_OPEN_DATA_DOMAIN = "data.cityofnewyork.us"
AZURE_STORAGE_ACCOUNT = "azureopendatastorage"
AZURE_TAXI_CONTAINER = "nyctlc"
TAXI_ZONE_LOOKUP_URL = "https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv"


class SocrataDataset(BaseModel):
    """One NYC Open Data (Socrata) dataset wired through the generic connector."""

    name: str  # Airbyte connection name
    resource_id: str  # Socrata 4x4 resource identifier
    cursor_field: str  # datetime field used for incremental sync
    table_prefix: str  # raw.{prefix}socrata_records
    domain: str = NYC_OPEN_DATA_DOMAIN


SOCRATA_DATASETS: list[SocrataDataset] = [
    SocrataDataset(
        name="socrata-311-complaints",
        resource_id="erm2-nwe9",
        cursor_field="created_date",
        table_prefix="socrata_311_",
    ),
    SocrataDataset(
        name="socrata-nypd-complaints",
        resource_id="qgea-i56i",
        cursor_field="cmplnt_fr_dt",
        table_prefix="socrata_nypd_",
    ),
    SocrataDataset(
        name="socrata-event-permits",
        resource_id="tvpp-9vvx",
        cursor_field="start_date_time",
        table_prefix="socrata_events_",
    ),
    SocrataDataset(
        name="socrata-restaurant-inspections",
        resource_id="43nn-pn8j",
        cursor_field="inspection_date",
        table_prefix="socrata_restaurants_",
    ),
]

# Airbyte connection names for the file/blob-backed sources.
TAXI_CONNECTION_NAMES: list[str] = [
    "nyc-taxi-trips",
    "nyc-citibike-trips",
    "nyc-taxi-zone-lookup",
]

SOCRATA_CONNECTION_NAMES: list[str] = [d.name for d in SOCRATA_DATASETS]

# Every connection Dagster should surface / the sync script may trigger.
ALL_AIRBYTE_CONNECTION_NAMES: list[str] = [
    *TAXI_CONNECTION_NAMES,
    *SOCRATA_CONNECTION_NAMES,
]
