from dagster import ScheduleDefinition


# Constructed with job object in definitions.py
def build_daily_schedule(job):
    return ScheduleDefinition(
        name="daily_schedule",
        job=job,
        cron_schedule="0 6 * * *",
    )
