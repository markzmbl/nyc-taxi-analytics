#!/usr/bin/env python3
"""Airbyte connector entry point for the Socrata source.

Usage:
    # Show the connector spec (JSON schema for config)
    python main.py spec

    # Check connectivity (requires a JSON config file)
    python main.py check --config config.json

    # Discover available streams
    python main.py discover --config config.json

    # Read records (requires config + catalog)
    python main.py read --config config.json --catalog catalog.json
"""

import sys

from airbyte_cdk import AirbyteEntrypoint

from source_socrata import SourceSocrata

if __name__ == "__main__":
    source = SourceSocrata()
    entrypoint = AirbyteEntrypoint(source)
    parsed_args = entrypoint.parse_args(sys.argv[1:])
    for message in entrypoint.run(parsed_args):
        print(f"{message}\n", end="")
