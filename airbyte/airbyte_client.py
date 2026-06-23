"""Shared client for the Airbyte configuration API (``/api/v1``).

Centralizes API access for the ``airbyte/`` helper scripts so they don't
each re-implement an HTTP client.  Configuration comes entirely from
``common.config`` (env-driven, no baked-in URL/credentials), and requests
go through ``requests`` with real HTTP-status error handling — a non-2xx
response raises instead of being mistaken for valid data.
"""

from __future__ import annotations

from typing import Any

import requests

from common.config import airbyte_api_settings

_settings = airbyte_api_settings()
API_URL = _settings.configuration_api_base_url.rstrip("/")

# Sync/list calls against a local Airbyte can be slow; give them headroom.
DEFAULT_TIMEOUT = 120  # seconds


class AirbyteAPIError(RuntimeError):
    """Raised on transport failure or any non-2xx Airbyte API response."""


_session = requests.Session()
_session.auth = (_settings.username, _settings.password)
_session.headers.update({"Content-Type": "application/json"})


def api(
    method: str,
    endpoint: str,
    body: dict[str, Any] | None = None,
    *,
    timeout: int = DEFAULT_TIMEOUT,
) -> dict[str, Any]:
    """Call the Airbyte config API and return parsed JSON (``{}`` if empty).

    Raises :class:`AirbyteAPIError` on connection failure, any non-2xx
    status, or an unparseable body — so a caller never mistakes an error
    response for valid data.
    """
    url = f"{API_URL}{endpoint}"
    try:
        resp = _session.request(method, url, json=body, timeout=timeout)
    except requests.RequestException as exc:
        raise AirbyteAPIError(f"{method} {endpoint} failed: {exc}") from exc

    if not resp.ok:
        raise AirbyteAPIError(
            f"{method} {endpoint} -> HTTP {resp.status_code}: {resp.text[:300]}"
        )
    if not resp.content:
        return {}
    try:
        return resp.json()  # type: ignore[no-any-return]
    except ValueError as exc:
        raise AirbyteAPIError(
            f"{method} {endpoint}: invalid JSON response: {resp.text[:200]}"
        ) from exc


def post(
    endpoint: str, body: dict[str, Any] | None = None, **kwargs: Any
) -> dict[str, Any]:
    """Convenience wrapper for the common POST case (body defaults to ``{}``)."""
    return api("POST", endpoint, {} if body is None else body, **kwargs)
