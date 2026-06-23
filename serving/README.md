# Serving slot

Pluggable BI / semantic layer over the marts. Pick any subset via
`STACK_SERVING` (e.g. `["metabase"]`, `["cube","superset"]`) and start them:

```bash
make serve SERVE="metabase cube"     # or: docker compose -f serving/docker-compose.yml --profile metabase --profile cube up -d
```

Cube is positioned as an optional **semantic layer**; Metabase/Superset are
dashboards that can sit on the warehouse directly or on Cube's SQL API.

## Per-engine connection notes

| Tool | DuckDB (Studio) | ClickHouse (Atelier/Resident) | MotherDuck |
|------|-----------------|-------------------------------|------------|
| **Metabase** | community DuckDB driver JAR in `serving/metabase/plugins/`; mount the file read-only | community ClickHouse driver JAR; host/port/user/pass | DuckDB driver + `md:` path |
| **Superset** | `duckdb-engine`: `duckdb:////data/warehouse.duckdb` | `clickhouse-connect`: `clickhousedb://user:pass@host:8123/warehouse` | `duckdb:///md:warehouse?motherduck_token=…` |
| **Cube** | `CUBE_DB_TYPE=duckdb` + file path | `CUBE_DB_TYPE=clickhouse` + host/port | `CUBE_DB_TYPE=duckdb` + `MOTHERDUCK_TOKEN` |

`CUBE_DB_TYPE` is `duckdb` for both DuckDB and MotherDuck (MotherDuck is DuckDB
+ a token), and `clickhouse` for ClickHouse — set it from the active engine.

## Caveats
- **DuckDB is single-writer.** BI tools must open the file **read-only** (mounts
  above use `:ro`); don't run `make studio`/`ingest` while a BI tool holds it, or
  serve from MotherDuck/ClickHouse instead for concurrent read+write.
- **Metabase has no built-in DuckDB/ClickHouse driver** — drop the community JAR
  into `serving/metabase/plugins/` before first boot.
- **Superset needs init** on first run (admin user + `superset init`) and the DB
  driver installed in the image (`duckdb-engine` / `clickhouse-connect`).

> Live-wiring of these tools is environment-specific and is validated when you
> run `make serve` with a warehouse populated — not covered by CI smoke yet.
