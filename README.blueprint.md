# Analytics blueprint

A Copier template for spinning up a customer analytics stack with
**interchangeable** components and **footprint tiers**. Orchestration (Dagster)
and transformation (dbt) are constant; the warehouse engine, ingestion tool,
and serving layer are pluggable.

## Generate a project

```bash
copier copy gh:your-org/analytics-blueprint my-customer
# or from a local checkout:
copier copy . ../my-customer
```

You'll be asked for `project_name`, `warehouse_engine`, `ingestion_tool`,
`serving`, `default_tier`, and `include_demo`. Answers are saved to
`.copier-answers.yml` so `copier update` can pull later blueprint improvements.

## The stack model

A deployment is `tier × warehouse × ingestion × serving`, selected by
`STACK_*` env (see `.env.example`) and resolved in `common/config.py` +
`common/stack.py`.

| Slot | Options | Default | Selected by |
|------|---------|---------|-------------|
| **Tier** (footprint) | studio / atelier / resident | studio | GitHub workflow |
| **Warehouse** | duckdb / motherduck / clickhouse | duckdb | `STACK_WAREHOUSE` |
| **Ingestion** | dlt / airbyte | dlt | `STACK_INGESTION` |
| **Serving** | metabase / superset / cube | metabase | `STACK_SERVING` |

One switch — `STACK_WAREHOUSE` — drives dlt (`ingestion/pipeline.py`), dbt
(`transform/profiles.yml`), and config together.

## Tiers (footprint) — run locally or via GitHub workflow

| Tier | Footprint | Local | Workflow |
|------|-----------|-------|----------|
| **Studio** | local single process | `make studio` (DuckDB, no Docker) | `studio.yml` |
| **Atelier** | Docker Compose | `make atelier` (ClickHouse) | `atelier.yml` |
| **Resident** | cloud / k8s (IaC) | — | `resident.yml` |

Each workflow takes `warehouse` / `ingestion` / `serving` (`+ cloud` for
Resident) inputs and calls the reusable `_deploy.yml`.

## Entrypoints

```bash
make studio                 # dlt -> DuckDB -> dbt, locally
make dagster                # Dagster dev UI on the active stack
make atelier                # ClickHouse via Compose + pipeline   (needs .[clickhouse])
make serve SERVE="metabase cube"   # start serving tools
```

## Ingestion: dlt (default) and Airbyte (optional)

dlt is the default — Python-native, lands data in any engine. **Airbyte** is the
optional heavy-tier plugin (`STACK_INGESTION=airbyte`); its setup/sync scripts
live in `airbyte/` and target a server-backed warehouse. Use it when you need
Airbyte's connector catalog; otherwise dlt keeps the laptop tier dependency-free.

## Status / remaining

- **Studio (DuckDB + dlt + dbt + Dagster):** complete, verified end-to-end.
- **Engines:** all three parse + build (DuckDB verified live; ClickHouse/MotherDuck
  via `make atelier` / a MotherDuck token).
- **Serving & Resident:** scaffolded (compose + workflows); live wiring and the
  cloud IaC (`infra/`, currently legacy) are the remaining work.
- **Demo decoupling:** `include_demo` is recorded; fully removing NYC from core
  (so a no-demo project is NYC-free) is a pending refactor.
