---
name: repo
type: repo
---

# Repository guidance for OpenHands

This repo is a **pluggable analytics blueprint** (a Copier template). OpenHands is
a single agent — it doesn't run the multi-agent "squad", but it inherits the squad's
conventions below. Treat each squad role as a *hat* to wear for the matching work.

## Stack & flow
`dlt (ingestion/) → warehouse (DuckDB | MotherDuck | ClickHouse) → dbt (transform/) → Dagster (orchestration/) → serving (Metabase | Superset | Cube)`
One switch — `STACK_WAREHOUSE` — drives dlt, dbt (`transform/profiles.yml`), and config (`common/`).
Tiers: Studio (local, DuckDB) · Atelier (Compose, ClickHouse) · Resident (cloud).

## Ownership map (whose hat for what)
- `ingestion/` (dlt; Airbyte optional) — **Toph**
- `transform/` + engine targets — **Katara**
- `orchestration/` (Dagster) — **Zuko**
- `serving/` — **Suki**
- data quality / load-frequency / dashboard value, via the **5 Vs** — **Wan Shi Tong** (decides; the above implement)
- `deploy/`, `infra/`, `.github/workflows/`, Docker — **Iroh**
- `copier.yml`, `common/` stack config, `.env.example` — **Sokka**

## Hard rules
- **No environment-specific or dataset defaults baked into code** — required config fails loudly (pydantic-settings); `.env.example` is the source of truth.
- **Engine-portable SQL** — keep models running on every engine; push engine specifics into `profiles.yml`.
- **Tests/types in the same change** — `ruff check .`, `black --check .`, `isort --check-only .`, `mypy`, `pytest`; dbt via `make studio` / `dbt build --project-dir transform --profiles-dir transform`.
- Never read `.env*` or commit secrets.

## Commands
`make studio` (dlt→DuckDB→dbt) · `make dagster` · `make atelier` (ClickHouse) · `make serve SERVE="metabase cube"`.

> Full detail lives in `.copilot/skills/` (squad-conventions, data-quality, stack-and-tiers,
> warehouse-engines, copier-template) — read the relevant one before changing that area.
