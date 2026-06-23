"""Socrata source connector — main source class.

Loads the YAML manifest (Low-Code CDK) and delegates all behavior to the
declarative framework. The manifest defines:
  - Spec (user config: domain, resource_id, app_token, start_date, cursor_field)
  - Streams (single generic stream with DatetimeBasedCursor + OffsetIncrement)
  - Check (read 1 record to verify connectivity)
  - Error handling (retry/backoff on 429, 500, 503)

No custom Python logic is needed — the Socrata API pattern (SoQL $where
date filtering, $limit/$offset pagination, X-App-Token auth) maps cleanly
to the Low-Code CDK components.
"""

from pathlib import Path

from airbyte_cdk.sources.declarative.yaml_declarative_source import YamlDeclarativeSource

MANIFEST_PATH = Path(__file__).parent / "manifest.yaml"


class SourceSocrata(YamlDeclarativeSource):
    """Socrata source connector backed by a YAML manifest."""

    def __init__(self):
        super().__init__(path_to_yaml=str(MANIFEST_PATH))
