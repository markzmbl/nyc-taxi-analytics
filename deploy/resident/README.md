# Resident tier

Cloud / Kubernetes deployment — the "in residence" production footprint.
Driven by the [`resident.yml`](../../.github/workflows/resident.yml) workflow,
which calls the reusable `_deploy.yml` with `tier: resident` and your chosen
`warehouse` / `ingestion` / `serving` / `cloud` inputs.

## Shape
- **Warehouse:** managed engine — MotherDuck (token) or ClickHouse Cloud /
  self-managed ClickHouse. No data-path Postgres.
- **Ingestion:** dlt (or Airbyte) running as a scheduled job / Dagster deployment.
- **Orchestration:** Dagster, with Postgres-backed run/event storage (operational,
  not the warehouse) — the Atelier/Resident override of `dagster_home/dagster.yaml`.
- **Serving:** the selected BI/semantic tools deployed as services / managed.
- **IaC:** reuse the Terraform under [`infra/`](../../infra) (`aws` | `azure` | `gcp`),
  selected by the workflow's `cloud` input.

## Status / TODO
The Terraform in `infra/` was written for the legacy Postgres + Airbyte + Kind
stack and **must be adapted** to the blueprint (managed warehouse, dlt job,
serving services). The `_deploy.yml` resident step currently echoes the plan;
wire `terraform init/plan/apply` against `infra/<cloud>` once the modules are
updated. Tracked under Phase 4 polish.
