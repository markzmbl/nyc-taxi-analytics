"""Demo dlt source: NYC TLC taxi-zone lookup (small, public, no API key)."""

from __future__ import annotations

import csv
import io
from collections.abc import Iterator

import dlt
import requests

from common.datasets import TAXI_ZONE_LOOKUP_URL


@dlt.resource(name="nyc_taxi_zones", write_disposition="replace")
def nyc_taxi_zones() -> Iterator[dict[str, str]]:
    """Yield taxi-zone rows from the public TLC CSV."""
    resp = requests.get(TAXI_ZONE_LOOKUP_URL, timeout=60)
    resp.raise_for_status()
    yield from csv.DictReader(io.StringIO(resp.text))
