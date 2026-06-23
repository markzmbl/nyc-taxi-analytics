"""Dagster Definitions entry point.

Blueprint orchestration: dlt ingestion → warehouse (DuckDB/MotherDuck/
ClickHouse) → dbt (transform/). The active stack (``common.config``) decides
the engine; the orchestration graph stays the same across engines and tiers.

Asset modules under ``assets/`` are **auto-discovered**, so demo assets (e.g.
the NYC dlt source) are optional — a project generated with ``include_demo=false``
simply has fewer asset modules and still loads cleanly.

The orchestration/ directory intentionally has no __init__.py — modules are
loaded by path via importlib so a local package can't shadow installed libs.
"""

import importlib.util
import os
import sys
from pathlib import Path

from dagster import Definitions, load_assets_from_modules
from dagster_dbt import DbtCliResource

HERE = Path(__file__).resolve().parent
TRANSFORM_DIR = HERE.parent / "transform"


def _load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"Could not load module {name!r} from {path}")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


# Auto-discover asset modules (dbt_assets is core; ingestion/demo assets optional).
_asset_modules = [
    _load(f"_proj_asset_{path.stem}", path)
    for path in sorted((HERE / "assets").glob("*.py"))
    if not path.name.startswith("_")
]

_jobs = _load("_proj_jobs", HERE / "jobs.py")
_schedules = _load("_proj_schedules", HERE / "schedules.py")

daily_schedule = _schedules.build_daily_schedule(_jobs.daily_pipeline)

defs = Definitions(
    assets=load_assets_from_modules(_asset_modules),
    resources={
        "dbt": DbtCliResource(
            project_dir=os.fspath(TRANSFORM_DIR),
            profiles_dir=os.fspath(TRANSFORM_DIR),
            dbt_executable=os.environ.get("DBT_EXECUTABLE", "dbt"),
        ),
    },
    jobs=[_jobs.daily_pipeline],
    schedules=[daily_schedule],
)
