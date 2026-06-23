# Local Development Architecture

This document explains the local dev stack so you understand what you see in Docker Desktop, how the pieces connect, and how to troubleshoot common issues.

---

## 1. Architecture Overview

The local stack has **two layers** working together:

### Docker Compose (project: `nyc-taxi-analytics`)

Three containers managed by `docker compose`:

| Container | Purpose |
|-----------|---------|
| **postgres** | PostgreSQL 16 — the central data warehouse. Holds four databases: `dagster`, `warehouse`, `metabase`, `airbyte`. Every service reads/writes through this single Postgres instance. |
| **metabase** | Business intelligence dashboard on port 3001. Connects to the `metabase` database inside Postgres. |
| **kind-init** | Bootstraps and manages a Kind Kubernetes cluster. This container bundles `kind`, `kubectl`, and `helm` so you don't need them on your host. It creates the cluster, deploys Airbyte and Dagster via Helm, then stays alive to keep the cluster managed. |

### Kind Kubernetes Cluster (`nyc-taxi-dev`)

A single-node K8s cluster running inside a sibling Docker container (created by `kind-init` via the Docker socket). It hosts:

| Namespace | What Runs |
|-----------|-----------|
| `airbyte` | Airbyte OSS server, workers, workload launcher, MinIO, Temporal — handles data ingestion from sources into the warehouse |
| `dagster` | Dagster webserver, daemon, and the `nyc-taxi-analytics` user deployment — the orchestration layer that triggers Airbyte syncs and runs dbt transformations |

### Why Two Layers?

- **Postgres and Metabase** are simple stateful services — Docker Compose handles them with minimal overhead.
- **Airbyte and Dagster** are complex, multi-pod applications that benefit from Kubernetes scheduling, health checks, and the Helm chart ecosystem. Running them in Kind gives you a realistic K8s environment that mirrors production without needing a cloud cluster.

The bridge between layers: Kind pods reach the Compose Postgres via `host.docker.internal:5432`, and the Kind node's ports are mapped to `localhost` so Dagster and Airbyte are reachable from your browser.

---

## 2. What You'll See in Docker Desktop

After running `docker compose up -d`:

1. **The `nyc-taxi-analytics` project** appears in Docker Desktop's Containers tab with three containers:
   - `nyc-taxi-analytics-postgres-1`
   - `nyc-taxi-analytics-metabase-1`
   - `nyc-taxi-analytics-kind-init-1`

2. **`nyc-taxi-dev-control-plane`** — a sibling Kind node container. It shows up in Docker Desktop alongside the Compose containers because Kind creates it via the Docker socket mounted into `kind-init`. It is _not_ part of the Compose project.

> **Note:** The `kind-init` container may take 2–5 minutes to finish setup on first run. Watch its logs (`docker compose logs -f kind-init`) to see progress through the Kind creation, Helm installs, and image build.

---

## 3. Service Map

| Service | Layer | Port | How to Access |
|---------|-------|------|---------------|
| Postgres | Compose | 5432 | `psql -h localhost -U dagster -d warehouse` |
| Metabase | Compose | 3001 | `http://localhost:3001` |
| Airbyte API | Kind | 8006 | `http://localhost:8006` (mapped via NodePort) |
| Airbyte Web UI | Kind | 8000 | `kubectl port-forward -n airbyte svc/airbyte-webapp 8000:80` |
| Dagster | Kind | 3000 | `http://localhost:3000` (mapped via NodePort) |

**Postgres databases** (all hosted on the single Postgres container):

| Database | Used By |
|----------|---------|
| `dagster` | Dagster (runs, event log, schedules) |
| `warehouse` | dbt transformations (schemas: `raw`, `staging`, `marts`) |
| `metabase` | Metabase application state |
| `airbyte` | Airbyte internal state DB |

### Why Airbyte Web UI Needs Port-Forward

The Kind init script deploys Airbyte with `webapp.enabled=false` to keep the local footprint small. The Airbyte **API server** is exposed directly on port 8006 (NodePort 30083), which Dagster uses to trigger syncs programmatically. If you need the Airbyte web dashboard for manual connector setup, enable and port-forward the webapp:

```bash
# Option A: Temporary port-forward (no Helm change needed after enabling)
kubectl port-forward -n airbyte svc/airbyte-webapp 8000:80

# Option B: Enable webapp via Helm
helm upgrade airbyte airbyte/airbyte -n airbyte --set webapp.enabled=true
```

---

## 4. Startup & Teardown

### Start the Full Stack

```bash
# Recommended — thin wrapper around docker compose
bash infra/k8s/local-kind.sh up

# Equivalent to:
docker compose up -d
```

The wrapper script:
1. Runs `docker compose up -d` (starts Postgres → Metabase → kind-init in dependency order)
2. Postgres health check passes before Metabase and kind-init start
3. `kind-init` creates the Kind cluster, builds the Dagster image, installs Airbyte and Dagster via Helm
4. Prints a summary of URLs when ready

**First run takes 2–5 minutes.** Subsequent starts reuse the existing Kind cluster and skip creation.

### Rebuild After Code Changes

When you change Dagster pipeline code (`orchestration/`) or the Dockerfile:

```bash
bash infra/k8s/local-kind.sh rebuild
```

This rebuilds the Dagster image, loads it into Kind, and restarts the Dagster deployment.

### Stop Everything

```bash
bash infra/k8s/local-kind.sh down
```

This:
1. Runs `docker compose down` — stops and removes Postgres, Metabase, and kind-init containers
2. Runs `kind delete cluster --name nyc-taxi-dev` — destroys the K8s cluster and its node container
3. **Preserves volumes** (`pgdata`) so your data survives restarts unless you explicitly prune

### Stop Without Losing Kind

```bash
docker compose down    # Stops Compose containers, Kind node keeps running
docker compose up -d   # Restart — kind-init detects existing cluster, skips creation
```

---

## 5. Common Issues

### Airbyte Web UI Not Reachable

The web UI (`http://localhost:8000`) won't work out of the box because the Kind init script sets `webapp.enabled=false`. Use the Airbyte API directly at `http://localhost:8006` for programmatic access, or port-forward as described in the Service Map above.

### Kind Cluster Conflicts

If you see errors about port 3000, 8000, or 8006 already in use, a previous Kind cluster may still be running:

```bash
kind get clusters
kind delete cluster --name nyc-taxi-dev
```

Then restart with `bash infra/k8s/local-kind.sh up`.

### Metabase "Downgrade" Error

After a Metabase image update, you may see: `Metabase has detected that it is running an older version than it was last started with`. This happens because the Metabase application data in the `pgdata` volume was written by a newer version. Fix:

```bash
docker compose down
docker volume rm nyc-taxi-analytics_pgdata
docker compose up -d
```

> ⚠️ This wipes all Postgres data — including the warehouse. Only do this in development.

### kind-init Container Exits Immediately

Check logs to find the failure:

```bash
docker compose logs kind-init
```

Common causes:
- **Docker socket not mounted** — ensure Docker Desktop is running
- **Port conflict** — ports 3000, 5432, or 8006 are in use
- **Out of memory** — Kind needs ~2 GB free RAM; increase Docker Desktop's memory allocation

### Dagster Pods CrashLoopBackOff

The Dagster user deployment may fail if the image isn't found in Kind:

```bash
# Check if image is loaded
docker exec nyc-taxi-dev-control-plane crictl images | grep nyc-taxi-analytics

# Reload and restart
bash infra/k8s/local-kind.sh rebuild
```

---

## 6. Prerequisites

| Tool | Required? | Notes |
|------|-----------|-------|
| Docker Desktop | **Yes** | The only hard requirement. Everything else runs in containers. |
| kind | No | Bundled inside `kind-init` container |
| kubectl | No | Bundled inside `kind-init`; install on host for convenience |
| Helm | No | Bundled inside `kind-init` |

**Recommended host tools** (not required, but useful for debugging):

```bash
# Install kind, kubectl, helm on your host for direct cluster access
# The kind-init container auto-generates ~/.kube/config, which you can also use from the host
kind get clusters
kubectl get pods -n dagster
kubectl get pods -n airbyte
helm list -n dagster
helm list -n airbyte
```

### Resource Requirements

- **RAM:** 4 GB minimum, 6 GB recommended (Postgres ~256 MB, Metabase ~512 MB, Kind node ~2 GB, Airbyte pods ~1.5 GB, Dagster pods ~1 GB)
- **Disk:** ~10 GB for images and volumes
- **Docker Desktop settings:** Enable Kubernetes (optional — Kind runs its own K8s), allocate at least 4 GB RAM in Resources

---

## Quick Reference

```bash
# Start
bash infra/k8s/local-kind.sh up

# View logs
docker compose logs -f kind-init

# Check K8s pods
kubectl get pods -A --context kind-nyc-taxi-dev

# Rebuild Dagster after code changes
bash infra/k8s/local-kind.sh rebuild

# Stop everything
bash infra/k8s/local-kind.sh down

# URLs
# Dagster:    http://localhost:3000
# Metabase:   http://localhost:3001
# Airbyte API: http://localhost:8006
# Postgres:   localhost:5432 (user: dagster, password: dagster)
```
