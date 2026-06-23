#!/usr/bin/env python3
"""Trigger Airbyte syncs and monitor jobs.

Connections are resolved by name against the workspace, so this works in
any environment without hardcoded connection UUIDs.  Override the target
set with the AIRBYTE_SYNC_CONNECTIONS env var (comma-separated names).
"""

import os
import sys

from airbyte.airbyte_client import AirbyteAPIError, post
from common.config import airbyte_workspace_settings
from common.datasets import ALL_AIRBYTE_CONNECTION_NAMES

WORKSPACE_ID = airbyte_workspace_settings().workspace_id

# Connection names to sync, in order. Override via env (comma-separated);
# defaults to the full roster in common.datasets.
CONNECTION_NAMES = [
    n.strip()
    for n in os.environ.get(
        "AIRBYTE_SYNC_CONNECTIONS", ",".join(ALL_AIRBYTE_CONNECTION_NAMES)
    ).split(",")
    if n.strip()
]


def resolve_connection_ids():
    """Return {name: connectionId} for connections in the workspace."""
    data = post("/connections/list", {"workspaceId": WORKSPACE_ID})
    return {c.get("name"): c.get("connectionId") for c in data.get("connections", [])}


def activate_and_sync(conn_id, conn_name):
    """Activate connection and trigger a sync."""
    print(f"\n--- {conn_name} ({conn_id}) ---")

    update = post("/connections/update", {"connectionId": conn_id, "status": "active"})
    print(f"  Status: {update.get('status', '?')}")

    print("  Triggering sync...")
    job = post("/connections/sync", {"connectionId": conn_id})
    info = job.get("job", {})
    print(f"  Job: {info.get('id', '?')} status={info.get('status', '?')}")
    return job


def check_jobs(conn_id):
    """Check recent jobs for a connection."""
    data = post(
        "/jobs/list",
        {"configTypes": ["sync"], "configId": conn_id, "pagination": {"pageSize": 5}},
    )
    jobs = data.get("jobs", [])
    for j in jobs:
        job = j.get("job", {})
        print(
            f"  Job {job.get('id')}: status={job.get('status')} "
            f"bytes={job.get('bytesSynced', 0)} recs={job.get('rowsSynced', 0)}"
        )
    return jobs


def main():
    try:
        available = resolve_connection_ids()
    except AirbyteAPIError as exc:
        print(f"FATAL: could not list connections: {exc}")
        return 1

    for cname in CONNECTION_NAMES:
        print(f"\n=== {cname} ===")
        cid = available.get(cname)
        if not cid:
            print("  SKIP: connection not found in workspace")
            continue

        try:
            jobs = check_jobs(cid)
            if jobs and any(
                j.get("job", {}).get("status") in ("running", "pending") for j in jobs
            ):
                print("  Already syncing, skipping trigger.")
                continue
            activate_and_sync(cid, cname)
        except AirbyteAPIError as exc:
            print(f"  ERROR: {exc}")

    print("\n=== Done triggering syncs ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
