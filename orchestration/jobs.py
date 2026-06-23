from dagster import AssetSelection, define_asset_job

daily_pipeline = define_asset_job(
    name="daily_pipeline",
    selection=AssetSelection.all(),
)
