"""Shared, first-party utilities (config, dataset registry).

This package is intentionally dependency-light so it can be imported from
both the Dagster ``orchestration`` code and the standalone ``airbyte``
scripts without pulling in either side's heavyweight deps.
"""
