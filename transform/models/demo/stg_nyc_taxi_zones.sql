-- Demo staging model. Reads the dlt-landed taxi-zone table from the raw schema.
select
    location_id,
    borough,
    zone        as zone_name,
    service_zone
from {{ source('raw', 'nyc_taxi_zones') }}
