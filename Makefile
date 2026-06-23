# Analytics blueprint — task entrypoints.
#
# Tiers are footprints; the tech (warehouse/ingestion/serving) is chosen via
# env / STACK_* settings. Studio = local single process on DuckDB.

# Single source of truth for the local DuckDB file (shared by dlt and dbt).
export DUCKDB_PATH ?= $(CURDIR)/warehouse.duckdb
# Local Dagster instance (SQLite storage under this dir).
export DAGSTER_HOME ?= $(CURDIR)/dagster_home

.PHONY: help studio ingest build dagster clean atelier atelier-down serve serve-down

ATELIER_COMPOSE := deploy/atelier/docker-compose.yml
SERVING_COMPOSE := serving/docker-compose.yml
# Serving tools to start, space-separated (compose profiles): make serve SERVE="metabase cube"
SERVE ?= metabase

help:  ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

## ── Studio tier (local, DuckDB, dlt) ────────────────────────────────────────
studio: ingest build  ## Run the full Studio pipeline locally on DuckDB
	@echo "Studio ready — DuckDB at $(DUCKDB_PATH)"

ingest:  ## Load demo data into the active warehouse via dlt
	python -m ingestion.run

build:  ## Build dbt models on the active warehouse
	dbt build --project-dir transform --profiles-dir transform

dagster:  ## Launch the Dagster dev UI on the DuckDB stack (http://localhost:3000)
	dagster dev -f orchestration/definitions.py

clean:  ## Remove the local DuckDB file
	rm -f "$(DUCKDB_PATH)"

## ── Atelier tier (Docker Compose, ClickHouse) ───────────────────────────────
# Needs the clickhouse extra: pip install -e ".[clickhouse]"
atelier:  ## Bring up ClickHouse and run the pipeline against it
	docker compose -f $(ATELIER_COMPOSE) up -d --wait
	STACK_WAREHOUSE=clickhouse CLICKHOUSE_HOST=localhost python -m ingestion.run
	STACK_WAREHOUSE=clickhouse CLICKHOUSE_HOST=localhost \
		dbt build --project-dir transform --profiles-dir transform

atelier-down:  ## Stop the Atelier stack
	docker compose -f $(ATELIER_COMPOSE) down

## ── Serving slot (BI / semantic) ────────────────────────────────────────────
serve:  ## Start serving tools (SERVE="metabase cube")
	docker compose -f $(SERVING_COMPOSE) $(foreach p,$(SERVE),--profile $(p)) up -d

serve-down:  ## Stop the serving tools
	docker compose -f $(SERVING_COMPOSE) $(foreach p,$(SERVE),--profile $(p)) down

# NOTE: serving (Metabase/Superset/Cube) is wired in the Phase 3 serving slot —
# Metabase↔DuckDB needs the community driver, handled with the other BI tools.
