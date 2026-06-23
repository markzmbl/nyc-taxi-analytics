"""Typed, centralized configuration via ``pydantic-settings``.

Every value here is read from the environment (and ``.env`` for local dev)
with **no environment-specific fallbacks** — required fields raise at
construction time if unset, so a missing config fails loudly instead of
silently defaulting to ``localhost``/``dagster``/a baked-in workspace.

Settings are split by concern so a consumer only pays for what it needs:
listing Airbyte connector definitions, for example, needs the API
connection but not a workspace id or the destination Postgres host.

Env var names match the existing ``.env.example`` exactly:

  PG_HOST / PG_PORT / PG_USER / PG_PASSWORD / PG_DB
  AIRBYTE_CONFIGURATION_API_BASE_URL / AIRBYTE_REST_API_BASE_URL
  AIRBYTE_USERNAME / AIRBYTE_PASSWORD
  AIRBYTE_WORKSPACE_ID / AIRBYTE_DEST_POSTGRES_HOST
  EPA_API_KEY / EPA_EMAIL
"""

from __future__ import annotations

from enum import StrEnum
from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

_ENV_FILE = ".env"


# ── Stack vocabulary ────────────────────────────────────────────────────────
class Tier(StrEnum):
    """Deployment footprint. Tech components are chosen independently."""

    studio = "studio"  # local single process
    atelier = "atelier"  # docker compose
    resident = "resident"  # cloud / k8s


class WarehouseEngine(StrEnum):
    duckdb = "duckdb"
    motherduck = "motherduck"
    clickhouse = "clickhouse"


class IngestionTool(StrEnum):
    dlt = "dlt"
    airbyte = "airbyte"


class ServingTool(StrEnum):
    metabase = "metabase"
    superset = "superset"
    cube = "cube"


class PostgresSettings(BaseSettings):
    """Warehouse Postgres connection.

    ``host``/``user``/``password`` are environment-specific and required.
    ``port``/``db`` have conventional, non-environment-specific defaults.
    """

    model_config = SettingsConfigDict(
        env_prefix="PG_", env_file=_ENV_FILE, env_file_encoding="utf-8", extra="ignore"
    )

    host: str
    user: str
    password: str
    port: int = 5432
    db: str = "warehouse"

    @property
    def dsn(self) -> str:
        """Connection URL accepted by both psycopg2 and SQLAlchemy."""
        return (
            f"postgresql://{self.user}:{self.password}"
            f"@{self.host}:{self.port}/{self.db}"
        )


class AirbyteApiSettings(BaseSettings):
    """Connection to the Airbyte configuration API (used by ``airbyte_client``)."""

    model_config = SettingsConfigDict(
        env_prefix="AIRBYTE_",
        env_file=_ENV_FILE,
        env_file_encoding="utf-8",
        extra="ignore",
    )

    configuration_api_base_url: str
    username: str
    password: str
    rest_api_base_url: str | None = None


class AirbyteWorkspaceSettings(BaseSettings):
    """Workspace-scoped Airbyte values needed only by setup/sync scripts."""

    model_config = SettingsConfigDict(
        env_prefix="AIRBYTE_",
        env_file=_ENV_FILE,
        env_file_encoding="utf-8",
        extra="ignore",
    )

    workspace_id: str
    # Host the Airbyte process uses to reach the warehouse Postgres. This is
    # environment-specific (e.g. ``host.docker.internal`` on Docker Desktop,
    # a service DNS name on K8s) and therefore required.
    dest_postgres_host: str


class EpaSettings(BaseSettings):
    """EPA AQS API credentials. Empty key means 'air quality not configured'."""

    model_config = SettingsConfigDict(
        env_prefix="EPA_", env_file=_ENV_FILE, env_file_encoding="utf-8", extra="ignore"
    )

    api_key: str = ""
    email: str = "test@example.com"


# ── Stack selection (which components are active) ───────────────────────────
class StackSettings(BaseSettings):
    """Active stack: tier x warehouse x ingestion x serving.

    Defaults target the Studio tier (laptop). These are *choices*, not
    environment-specific secrets, so sensible defaults are appropriate.
    """

    model_config = SettingsConfigDict(
        env_prefix="STACK_",
        env_file=_ENV_FILE,
        env_file_encoding="utf-8",
        extra="ignore",
    )

    tier: Tier = Tier.studio
    warehouse: WarehouseEngine = WarehouseEngine.duckdb
    ingestion: IngestionTool = IngestionTool.dlt
    serving: list[ServingTool] = Field(default_factory=lambda: [ServingTool.metabase])


# ── Warehouse engines (Postgres is no longer a data-path option) ────────────
class DuckDBSettings(BaseSettings):
    """Local DuckDB file. ``path`` default is a project-relative file."""

    model_config = SettingsConfigDict(
        env_prefix="DUCKDB_",
        env_file=_ENV_FILE,
        env_file_encoding="utf-8",
        extra="ignore",
    )

    path: str = "warehouse.duckdb"


class MotherDuckSettings(BaseSettings):
    """MotherDuck (managed DuckDB). ``token`` is a required secret."""

    model_config = SettingsConfigDict(
        env_prefix="MOTHERDUCK_",
        env_file=_ENV_FILE,
        env_file_encoding="utf-8",
        extra="ignore",
    )

    token: str
    database: str = "warehouse"

    @property
    def duckdb_path(self) -> str:
        """``md:`` path consumed by both dlt and dbt-duckdb."""
        return f"md:{self.database}?motherduck_token={self.token}"


class ClickHouseSettings(BaseSettings):
    """ClickHouse connection. ``host`` is environment-specific and required."""

    model_config = SettingsConfigDict(
        env_prefix="CLICKHOUSE_",
        env_file=_ENV_FILE,
        env_file_encoding="utf-8",
        extra="ignore",
    )

    host: str
    port: int = 8123
    user: str = "default"
    password: str = ""
    database: str = "warehouse"
    secure: bool = False


@lru_cache
def stack_settings() -> StackSettings:
    return StackSettings()


@lru_cache
def duckdb_settings() -> DuckDBSettings:
    return DuckDBSettings()


@lru_cache
def motherduck_settings() -> MotherDuckSettings:
    return MotherDuckSettings()


@lru_cache
def clickhouse_settings() -> ClickHouseSettings:
    return ClickHouseSettings()


@lru_cache
def postgres_settings() -> PostgresSettings:
    return PostgresSettings()


@lru_cache
def airbyte_api_settings() -> AirbyteApiSettings:
    return AirbyteApiSettings()


@lru_cache
def airbyte_workspace_settings() -> AirbyteWorkspaceSettings:
    return AirbyteWorkspaceSettings()


@lru_cache
def epa_settings() -> EpaSettings:
    return EpaSettings()
