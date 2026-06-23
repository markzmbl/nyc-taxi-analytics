"""dlt ingestion assets.

Each asset runs a dlt pipeline that lands a source into the active warehouse's
``raw`` schema. The asset key matches the dbt source key (``["raw", <table>]``),
so dagster-dbt automatically wires the dbt models downstream of ingestion.

Demo assets are NYC-flavored and are dropped from non-demo projects.
"""

import dagster as dg
from ingestion.pipeline import build_pipeline
from ingestion.sources.nyc_zones import nyc_taxi_zones


@dg.asset(
    key=["raw", "nyc_taxi_zones"],
    group_name="ingestion",
    compute_kind="dlt",
    description="NYC TLC taxi-zone lookup, loaded via dlt (demo source).",
)
def raw_nyc_taxi_zones(context: dg.AssetExecutionContext) -> None:
    info = build_pipeline().run(nyc_taxi_zones())
    context.log.info(str(info))
