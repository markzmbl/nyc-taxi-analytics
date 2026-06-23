"""Run the demo ingestion into the active warehouse.

    python -m ingestion.run

In a project generated without the demo (``include_demo=false``) there are no
sources yet, so this is a friendly no-op until you add your own under
``ingestion/sources/``.
"""

from __future__ import annotations

from ingestion.pipeline import build_pipeline


def main() -> None:
    try:
        from ingestion.sources.nyc_zones import nyc_taxi_zones
    except ImportError:
        print(
            "No ingestion sources configured — add dlt sources under "
            "ingestion/sources/ and wire them here."
        )
        return

    info = build_pipeline().run(nyc_taxi_zones())
    print(info)


if __name__ == "__main__":
    main()
