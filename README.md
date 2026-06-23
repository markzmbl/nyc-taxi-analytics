# NYC Taxi Analytics

End-to-end multi-modal analytics pipeline for NYC transportation, environment,
and events data. Ingests 8 data sources, transforms through a medallion
architecture, and serves dashboards via Metabase.

| Component | Tool |
|-----------|------|
| Ingestion (taxi) | **Airbyte** via `dagster-airbyte` (Azure Blob Parquet) |
| Ingestion (citibike) | **Airbyte** via `dagster-airbyte` (S3 CSV) |
| Ingestion (weather, holidays) | Python + `azureml-opendatasets` |
| Ingestion (subway) | Python + MTA turnstile CSV |
| Ingestion (311, events) | Python + NYC Open Data Socrata API |
| Ingestion (air quality) | Python + EPA AQS REST API |
| Orchestration | **Dagster** |
| Transformation | **dbt-core** (PostgreSQL) |
| Warehouse | **PostgreSQL 16** |
| BI | **Metabase OSS** |
| IaC | **Terraform** (Azure / AWS / GCP) + Docker Compose (local) |

## Architecture

```
Azure Open Datasets
  ├─ taxi (Parquet)    ──► Airbyte  ─┐
  ├─ weather (SDK)     ──► Python  │
  └─ holidays (SDK)    ──► Python  │
Citi Bike S3                       │
  └─ trips (CSV)       ──► Airbyte  ─┼──► PostgreSQL ──► dbt ──► Metabase
MTA                                │       │
  └─ turnstiles (CSV)  ──► Python  │  Dagster orchestrates
NYC Open Data (Socrata)            │
  ├─ 311 complaints    ──► Python  │
  └─ event permits     ──► Python  │
EPA AQS                            │
  └─ air quality       ──► Python ─┘
```

| Schema | Layer | Materialization |
|--------|-------|-----------------|
| `raw` | Bronze — ingested data | Airbyte relational (taxi, citibike), JSONB (others) |
| `staging` | Silver — cleaned/typed | dbt views |
| `marts` | Gold — star schema | dbt tables (dims, facts, aggregations) |

---

## Quick Start (Local)

```
┌────────────── Local Dev ──────────────┐
│                                        │
│  docker compose up -d                  │
│  → Postgres :5432, Metabase :3001      │
│                                        │
│  bash infra/k8s/local-kind.sh          │
│  → Kind cluster + Helm                 │
│  → Airbyte :8000, Dagster :3000        │
│                                        │
│  Rebuild after code changes:           │
│  docker build & kind load & restart    │
└────────────────────────────────────────┘
```

### One-command setup

```bash
# 1. Start Postgres + Metabase
docker compose up -d

# 2. Start Airbyte + Dagster in Kind
bash infra/k8s/local-kind.sh
```

| Service | URL | Runs in |
|---------|-----|---------|
| Dagster | `http://localhost:3000` | Kind (namespace: `dagster`) |
| Airbyte | `http://localhost:8000` | Kind (namespace: `airbyte`) |
| Metabase | `http://localhost:3001` | Docker Compose |
| Postgres | `localhost:5432` | Docker Compose |

### Rebuild cycle (after code changes)

```bash
docker build -t nyc-taxi-analytics:dev -f docker/Dockerfile.dagster . && \
kind load docker-image nyc-taxi-analytics:dev --name nyc-taxi-dev && \
kubectl rollout restart deployment -n dagster -l app=nyc-taxi-analytics
```

> **For rapid asset development**, run `pip install -e ".[dev]" && dagster dev -w workspace.yaml`
> natively for hot-reload. Point `.env` at the same Postgres + Airbyte services.

### Configure Airbyte

Open **http://localhost:8000**, create sources (Azure Blob, S3) and a
PostgreSQL destination (host: `host.docker.internal`, port: `5432`),
then set up connections per the specs in `airbyte/`.

Get credentials:
```bash
kubectl exec -n airbyte deploy/airbyte-server -- \
  cat /workspace/default/admin@airbyte.io/default_user_credentials.txt
```

Update the `dagster-airbyte-secret` with your workspace ID, then materialize:

```bash
curl -s http://localhost:3000/graphql -H "Content-Type: application/json" \
  -d '{"query": "mutation { launchRun(executionParams: { selector: { repositoryLocationName: \"definitions.py\", repositoryName: \"__repository__\", jobName: \"daily_pipeline\" } }) { __typename ... on LaunchRunSuccess { run { runId } } } }"}'
```

## Metabase Setup

Metabase starts with `docker compose up -d`. First visit:

1. Open **http://localhost:3001**, create admin account
2. On the data prompt, click *"I'll add my data later"*

### Connect to the Warehouse

1. Go to **Settings** (gear icon) → **Admin** → **Databases** → **Add database**
2. Fill in:

| Field | Value |
|-------|-------|
| Database type | PostgreSQL |
| Display name | NYC Taxi Warehouse |
| Host | `postgres` (Docker Compose) or `localhost` (standalone) |
| Port | `5432` |
| Database name | `warehouse` |
| Username | `dagster` |
| Password | `dagster` |

3. Click **Save**. Metabase will sync the `marts` schema.

### 4. Build Dashboards

Key tables to explore in `marts`:

| Table | Use for |
|-------|---------|
| `fact_trips` | Taxi trip volume, fare analysis |
| `fact_subway_entries` | Subway ridership by station/day |
| `fact_citibike_trips` | Bike-share usage, durations, routes |
| `fact_311_complaints` | Service request patterns by type/zone |
| `fact_event_permits` | Event density and timing |
| `fact_air_quality` | EPA AQI, ozone, PM2.5 trends |
| `agg_modal_daily` | **Cross-modal daily summary** — all modes + weather + events |
| `dim_date` + `dim_weather` | Weather vs. trip correlation |
| `dim_holidays` | Holiday impact on ridership |
| `dim_subway_stations` | Station locations mapped to taxi zones |
| `dim_citibike_stations` | Bike station locations mapped to taxi zones |
| `agg_flow_zone` | Zone-to-zone Sankey / flow maps |
| `agg_flow_borough` | Borough-level flow summary |
| `dim_taxi_zones` | Zone names + centroids for map pins |

---

## Airbyte Integration

Taxi and Citi Bike data ingestion is powered by [Airbyte](https://airbyte.com/) via
[`dagster-airbyte`](https://docs.dagster.io/api/libraries/dagster-airbyte).

### Architecture

Airbyte OSS and Dagster run in the **same Kubernetes cluster**, in separate namespaces.
Dagster triggers Airbyte syncs via the in-cluster REST API. Scalability is managed by
K8s — Airbyte workers and Dagster runs scale as K8s Jobs/Pods.

```
                    ┌─────────────────────────────────────────┐
                    │           Kubernetes Cluster             │
                    │                                          │
  namespace/airbyte │  ┌──────────────┐  ┌────────────────┐   │
                    │  │ Airbyte      │  │ Airbyte Worker │   │
                    │  │ Server :8006 │  │ (connectors)   │   │
                    │  └──────┬───────┘  └────────┬───────┘   │
                    │         │                    │           │
  namespace/dagster │  ┌──────┴────────────────────┴───────┐  │
                    │  │           Dagster                  │  │
                    │  │  ┌──────────┐  ┌──────────────┐   │  │
                    │  │  │Webserver │  │    Daemon     │   │  │
                    │  │  │  :3000   │  │ (triggers     │   │  │
                    │  │  └──────────┘  │  Airbyte API) │   │  │
                    │  │                └──────────────┘   │  │
                    │  └───────────────────────────────────┘  │
                    │                                          │
                    │  ┌──────────┐                            │
                    │  │ Metabase │  ┌──────────────────────┐  │
                    │  │  :3000   │  │  Postgres (external  │  │
                    │  └──────────┘  │  or in-cluster)      │  │
                    │                └──────────────────────┘  │
                    └─────────────────────────────────────────┘
```

### Setup

**Local (Docker Compose):** `docker compose up -d` — see Quick Start above.

**Local K8s (Kind):**

```bash
bash infra/k8s/local-kind.sh
# Dagster → http://localhost:3000
# Airbyte → http://localhost:8000
# Metabase → http://localhost:3001
```

**Production (Terraform + Helm):**

```bash
cd infra/azure   # or aws/ or gcp/
terraform init
terraform apply -var="pg_admin_password=..." -var="airbyte_password=..."
# Creates: AKS/EKS/GKE + Helm releases for Airbyte + Dagster
```

After deployment, configure Airbyte connections via the Airbyte UI, then
materialize via Dagster.

Airbyte connection reference specs live in `airbyte/` — use these to configure
connections in the Airbyte UI:

---

## Cloud Deployment (Terraform + Helm)

All three clouds deploy the same topology: **managed K8s cluster + Postgres**.
Airbyte and Dagster are installed via Helm charts from Terraform. Scalability is
handled by K8s HPA and node auto-scaling instead of cloud-specific container services.

```
infra/
├── k8s/                 # Helm values (cloud-agnostic)
│   ├── airbyte/values.yaml
│   ├── dagster/values.yaml
│   └── local-kind.sh    # local K8s dev setup
├── azure/               # AKS + PostgreSQL Flexible Server
├── aws/                 # EKS + RDS PostgreSQL
└── gcp/                 # GKE + Cloud SQL
```

### Deploy to Azure

```bash
cd infra/azure
terraform init
terraform plan -var="pg_admin_password=YourSecurePassword"
terraform apply -var="pg_admin_password=YourSecurePassword"
```

### Deploy to AWS

```bash
cd infra/aws
terraform init
terraform plan -var="pg_admin_password=YourSecurePassword"
terraform apply -var="pg_admin_password=YourSecurePassword"
```

### Deploy to GCP

```bash
cd infra/gcp
terraform init
terraform plan \
  -var="project_id=your-gcp-project" \
  -var="pg_admin_password=YourSecurePassword"
terraform apply \
  -var="project_id=your-gcp-project" \
  -var="pg_admin_password=YourSecurePassword"
```

> After `terraform apply`, get kubeconfig from outputs, push images to the
> container registry, then configure Airbyte connections via the UI.

---

## Project Structure

```
nyc-taxi-analytics/
├── orchestration/        Dagster assets, jobs, schedules
│   └── assets/
│       ├── raw_taxi.py           Python — NYC taxi (Azure Open Datasets)
│       ├── raw_citibike.py       Python — Citi Bike (HTTPS)
│       ├── raw_weather.py        Python — NOAA weather (Azure Open Datasets)
│       ├── raw_holidays.py       Python — holidays (Azure Open Datasets)
│       ├── raw_subway.py         Python — MTA turnstile CSV
│       ├── raw_311.py            Python — 311 complaints (Socrata)
│       ├── raw_events.py         Python — event permits (Socrata)
│       ├── raw_air_quality.py    Python — EPA AQS air quality
│       ├── raw_taxi.py           Python fallback for taxi
│       └── dbt_assets.py         dagster-dbt integration
├── dbt/                  dbt project
│   ├── models/staging/   Views: JSONB extraction + cleaning
│   ├── models/marts/     Tables: star schema + aggregations
│   ├── macros/           Reusable macros (map_to_taxi_zone, etc.)
│   └── seeds/            Lookups: taxi zones, stations, granularity
├── airbyte/              Airbyte connection + replication configs
├── infra/                Terraform IaC
│   ├── k8s/              Helm values + local K8s scripts
│   ├── azure/            AKS + PG Flexible Server
│   ├── aws/              EKS + RDS
│   └── gcp/              GKE + Cloud SQL
├── docker/               Dockerfiles
├── docker-compose.yml    Full local stack
├── docker-compose.dev.yml  Dev: Postgres + Metabase only
└── scripts/init_db.sql   Schema bootstrap
```

## Data Quality

Trip data from **2019-07-01 onward** is unreliable (counts collapse to near-zero).
The `fact_trips` model enforces `WHERE pickup_datetime < '2019-07-01'` upstream.
This filter lives in dbt, not in report-level filters or DAX guards.

## Environment Variables

| Variable | Used by | Description |
|----------|---------|-------------|
| `PG_HOST` | Dagster, dbt | PostgreSQL hostname |
| `PG_USER` | Dagster, dbt | PostgreSQL user |
| `PG_PASSWORD` | Dagster, dbt | PostgreSQL password |
| `AIRBYTE_REST_API_BASE_URL` | Dagster → Airbyte | Airbyte public REST API endpoint |
| `AIRBYTE_CONFIGURATION_API_BASE_URL` | Dagster → Airbyte | Airbyte configuration API endpoint |
| `AIRBYTE_WORKSPACE_ID` | Dagster → Airbyte | Airbyte workspace UUID |
| `AIRBYTE_USERNAME` | Dagster → Airbyte | Airbyte basic auth username |
| `AIRBYTE_PASSWORD` | Dagster → Airbyte | Airbyte basic auth password |
| `EPA_API_KEY` | Air quality asset | Free key from [EPA AQS](https://aqs.epa.gov/aqsweb/documents/data_api.html) |
| `EPA_EMAIL` | Air quality asset | Email registered with EPA AQS (default: test@example.com) |
