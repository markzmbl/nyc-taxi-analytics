"""Ingestion slot. dlt is the default; Airbyte is an optional plugin.

The active warehouse (from ``common.stack``) determines the dlt destination,
so a source is written once and lands in whichever engine the stack selects.
"""
