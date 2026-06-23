{{ config(materialized="table") }}

-- Demo marts model: a clean taxi-zone dimension a BI tool can sit on.
select
    location_id,
    borough,
    zone_name,
    service_zone
from {{ ref('stg_nyc_taxi_zones') }}
where location_id is not null
