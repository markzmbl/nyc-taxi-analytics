from pathlib import Path

from dagster import AssetExecutionContext
from dagster_dbt import DagsterDbtTranslator, DbtCliResource, DbtProject, dbt_assets

# The dbt project lives in transform/ and targets the active warehouse engine
# (DuckDB/MotherDuck/ClickHouse) via its profiles.yml + DUCKDB_PATH/engine env.
DBT_PROJECT_DIR = Path(__file__).resolve().parent.parent.parent / "transform"

dbt_project = DbtProject(project_dir=DBT_PROJECT_DIR, profiles_dir=DBT_PROJECT_DIR)
dbt_project.prepare_if_dev()


@dbt_assets(
    manifest=dbt_project.manifest_path,
    dagster_dbt_translator=DagsterDbtTranslator(),
)
def analytics_dbt_assets(context: AssetExecutionContext, dbt: DbtCliResource):
    yield from dbt.cli(["build"], context=context).stream()
