-- For-Hire Vehicle trips: traditional black cars, livery, limousines.
-- Airbyte normalized all columns to lowercase without underscores.
-- No fare/passenger/distance data in TLC FHV feed.

with source as (

    select * from {{ source('raw', 'taxi_trips_fhv') }}

)

select
    dispatchbasenum                             as dispatching_base_num,
    pickupdatetime::timestamp                   as pickup_datetime,
    dropoffdatetime::timestamp                  as dropoff_datetime,
    pulocationid::int                           as pickup_location_id,
    dolocationid::int                           as dropoff_location_id,
    srflag                                      as shared_ride_flag,
    null::text                                  as affiliated_base_num
from source
where pickupdatetime is not null
  and (pulocationid is null or pulocationid::int > 0)
