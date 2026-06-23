# Socrata Source Connector (Airbyte Low-Code CDK)

A generic Airbyte source connector for any [Socrata Open Data API](https://dev.socrata.com/) dataset. One connector, configurable per dataset — replaces the 4 custom Dagster Python assets that currently ingest Socrata data (311 Complaints, NYPD Complaints, Event Permits, Restaurant Inspections).

## Why This Connector Exists

Four NYC Open Data datasets are currently ingested via custom Dagster Python assets that call the Socrata API directly. All 4 use the same pattern: SoQL `$where` date filtering, `$limit`/`$offset` pagination, and JSONB landing in Postgres. This connector consolidates that pattern into a single reusable Airbyte source.

**Key benefit:** The 311 dataset (2.3M rows) OOMKills the Dagster run worker because the asset loads all records into memory before inserting. This connector streams records one batch at a time via the Airbyte CDK's offset paginator, fixing the OOM issue.

## How It Works

The connector uses the **Airbyte Low-Code CDK** (YAML manifest). No custom Python logic — the Socrata API pattern maps cleanly to declarative CDK components:

| Socrata API Feature | Low-Code CDK Component |
|---------------------|----------------------|
| `GET /resource/{id}.json` | `HttpRequester` with interpolated `url_base` + `path` |
| `$limit` + `$offset` pagination | `DefaultPaginator` + `OffsetIncrement` (page_size=50000) |
| `$where` date filtering | `DatetimeBasedCursor` with interpolated `$where` request parameter |
| `$order` for deterministic cursor | `requester_options` → `$order: {cursor_field} ASC` |
| `X-App-Token` header (rate limits) | `SelectiveAuthenticator` → `ApiKeyAuthenticator` (optional) |
| HTTP 429 / 503 retry | `CompositeErrorHandler` + `ExponentialBackoffStrategy` |
| Incremental sync / checkpointing | `DatetimeBasedCursor` (90-day windows, 7-day lookback) |

### Incremental Sync Strategy

The `DatetimeBasedCursor` partitions the date range `[start_date, now]` into 90-day windows (matching the Dagster assets' chunk strategy). Each window becomes a stream slice:

```
Window 1: 2023-01-01T00:00:00 → 2023-03-31T23:59:59
Window 2: 2023-04-01T00:00:00 → 2023-06-30T23:59:59
...
```

For each window, the connector:
1. Builds the SoQL `$where` clause: `{cursor_field} >= '{start_time}' AND {cursor_field} <= '{end_time}'`
2. Paginates with `$limit=50000` + `$offset` until the window is exhausted
3. Progresses the cursor to the next window

A 7-day lookback window (`P7D`) catches late-arriving records.

## Configuration

| Parameter | Required | Description | Example |
|-----------|----------|-------------|---------|
| `domain` | Yes | Socrata domain (without `https://`) | `data.cityofnewyork.us` |
| `resource_id` | Yes | Socrata 4x4 resource identifier | `erm2-nwe9` |
| `app_token` | No | Socrata app token (10k req/hr vs 1k req/hr) | Register at [dev.socrata.com](https://dev.socrata.com/docs/app-tokens.html) |
| `start_date` | Yes | ISO datetime for sync start | `2023-01-01T00:00:00` |
| `cursor_field` | Yes | Socrata field for incremental watermark | `created_date` |

### Pre-configured Datasets

| Dataset | Resource ID | Cursor Field | Rows |
|---------|-------------|--------------|------|
| 311 Complaints | `erm2-nwe9` | `created_date` | 2.3M |
| NYPD Complaints | `qgea-i56i` | `cmplnt_fr_dt` | 1.7M |
| Event Permits | `tvpp-9vvx` | `start_date_time` | 32K |
| Restaurant Inspections | `43nn-pn8j` | `inspection_date` | 65K |

## Local Development

### Prerequisites

- Python ≥ 3.11 (3.12 recommended; 3.13 works but airbyte-cdk wheels are not
  pre-built for it yet)
- `pip`

### Install

```bash
cd airbyte/connectors/source-socrata
python -m venv .venv
.venv\Scripts\activate    # Windows
# source .venv/bin/activate   # Linux/macOS
pip install -e .
```

> **Note:** The connector requires `airbyte-cdk>=6.0.0,<7.0.0`. The 0.x and
> 1.x–5.x series pin `pendulum<3.0.0`, which fails to build on Python 3.12+.
> Version 6.61.6 (the last 6.x) dropped that dependency and is the first
> version that installs cleanly on modern Python while retaining the Low-Code
> CDK YAML manifest engine.

### Test

```bash
# 1. Show the connector spec (JSON schema for config)
python main.py spec

# 2. Check connectivity (uses config.json in this directory)
python main.py check --config config.json

# 3. Discover streams
python main.py discover --config config.json

# 4. Read records (requires a catalog — see below)
python main.py read --config config.json --catalog catalog.json
```

> **Config format:** Airbyte connectors expect **JSON** config files, not YAML.
> Use `config.json` (not `config.yaml`) for all CLI commands. The `config.yaml`
> file is kept for human-readable reference only.

### Reading Records (Full Test)

A `catalog.json` is included in this directory. To test actual data extraction:

```bash
python main.py read --config config.json --catalog catalog.json 2>&1 | head -20
```

## Docker Build & Deploy

### Build

```bash
docker build -t source-socrata:dev airbyte/connectors/source-socrata/
```

### Test the Docker Image

```bash
docker run --rm source-socrata:dev spec
docker run --rm -v $(pwd)/airbyte/connectors/source-socrata/config.json:/secrets/config.json \
  source-socrata:dev check --config /secrets/config.json
```

### Deploy to Airbyte (Kind cluster)

```bash
# Load the image into the Kind cluster
kind load docker-image source-socrata:dev --name nyc-taxi-dev

# Register as a custom connector via the Airbyte API (webapp is disabled):
curl -X POST http://localhost:8006/api/v1/source_definitions/create_custom \
  -H "Content-Type: application/json" \
  -d '{
    "workspaceId": "<your-workspace-id>",
    "sourceDefinition": {
      "name": "Socrata",
      "dockerRepository": "source-socrata",
      "dockerImageTag": "dev",
      "documentationUrl": "https://dev.socrata.com/docs/queries/"
    }
  }'
```

Then create a source and connection via the API (see the decision file for
the full API call sequence).

## Socrata API Rate Limits

| Mode | Rate Limit | Notes |
|------|-----------|-------|
| Anonymous (no token) | 1000 req/hr | Sufficient for small datasets (events, inspections) |
| With app token | 10000 req/hr | Required for large datasets (311, NYPD complaints) |

The connector retries HTTP 429 (rate limited) with exponential backoff (factor=5s). Register for a free app token at [dev.socrata.com](https://dev.socrata.com/docs/app-tokens.html) if syncing large datasets.

## Limitations & TODOs

1. **Restaurant Inspections nested grouping:** The Dagster asset groups flat Socrata rows by `camis|inspection_date` into nested JSONB documents with a `violations` array. This connector lands flat rows (Airbyte doesn't do grouping at ingestion). The grouping logic must move to dbt (Katara's domain) during migration. See the decision file for details.

2. **Schema auto-discovery:** The connector uses a permissive schema (`additionalProperties: true`). All fields land as strings in the destination. Type normalization happens downstream in dbt staging models. A future enhancement could add per-dataset explicit schemas in `source_socrata/schemas/`.

3. **Primary keys:** No primary key is defined (Socrata datasets don't have a consistent natural PK across all datasets). Destination sync mode should be `append` (not `append_dedup`). Deduplication happens in dbt staging.

4. **Stream name is fixed:** The Low-Code CDK does not support Jinja interpolation in the `DeclarativeStream.name` field. The stream is always named `socrata_records` regardless of which dataset is configured. The `resource_id` is preserved in each record via the `_socrata_resource_id` metadata field so downstream consumers can distinguish datasets. If multiple Socrata datasets need to sync simultaneously, create separate Airbyte sources (one per dataset) — they will all write to `socrata_records` but with different `_socrata_resource_id` values. Use `append` destination mode and dedup in dbt.

5. **No app token in config.json:** The sample config omits `app_token` for anonymous testing. Add it for production syncs of large datasets. The connector uses `ApiKeyAuthenticator` with `{{ config['app_token'] | default('') }}` — when the token is absent, the `X-App-Token` header is empty and Socrata treats the request as anonymous (1k req/hr limit).

## File Structure

```
source-socrata/
├── source_socrata/
│   ├── __init__.py          # Package init, exports SourceSocrata
│   ├── source.py            # YamlDeclarativeSource wrapper
│   ├── manifest.yaml        # Low-Code CDK manifest (the core)
│   └── schemas/
│       └── socrata_record.json  # Fallback schema (inline schema used at runtime)
├── main.py                  # Airbyte entry point
├── setup.py                 # Package setup
├── requirements.txt         # Dependencies (airbyte-cdk)
├── config.yaml              # Sample config (311 dataset)
├── Dockerfile               # Airbyte deployment image
└── README.md                # This file
```

## References

- [Socrata API docs](https://dev.socrata.com/docs/queries/)
- [SoQL (Socrata Query Language)](https://dev.socrata.com/docs/queries/soql/)
- [Socrata app tokens](https://dev.socrata.com/docs/app-tokens.html)
- [Airbyte Low-Code CDK](https://docs.airbyte.com/platform/connector-development/config-based/low-code-cdk-overview)
- [Airbyte CDK YAML reference](https://github.com/airbytehq/airbyte-python-cdk/blob/main/airbyte_cdk/sources/declarative/declarative_component_schema.yaml)
