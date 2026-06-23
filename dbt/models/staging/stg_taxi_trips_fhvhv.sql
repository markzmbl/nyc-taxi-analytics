-- High-Volume For-Hire Vehicle trips: Uber, Lyft, Via, Juno.
-- Raw columns use underscores except for pulocationid/dolocationid.

with source as (

    select * from {{ source('raw', 'taxi_trips_fhvhv') }}

)

select
    hvfhs_license_num                           as hvfhs_license_num,
    dispatching_base_num                        as dispatching_base_num,
    originating_base_num                        as originating_base_num,
    request_datetime::timestamp                 as request_datetime,
    on_scene_datetime::timestamp                as on_scene_datetime,
    pickup_datetime::timestamp                  as pickup_datetime,
    dropoff_datetime::timestamp                 as dropoff_datetime,
    pulocationid::int                           as pickup_location_id,
    dolocationid::int                           as dropoff_location_id,
    trip_miles::numeric(10,2)                   as trip_miles,
    trip_time::int                              as trip_time_sec,
    base_passenger_fare::numeric(10,2)          as base_passenger_fare,
    tolls::numeric(10,2)                        as tolls_amount,
    bcf::numeric(10,2)                          as bcf_amount,
    sales_tax::numeric(10,2)                    as sales_tax,
    congestion_surcharge::numeric(10,2)         as congestion_surcharge,
    airport_fee::numeric(10,2)                  as airport_fee,
    tips::numeric(10,2)                         as tips_amount,
    driver_pay::numeric(10,2)                   as driver_pay,
    shared_request_flag                         as shared_request_flag,
    shared_match_flag                           as shared_match_flag,
    access_a_ride_flag                          as access_a_ride_flag,
    wav_request_flag                            as wav_request_flag,
    wav_match_flag                              as wav_match_flag
from source
where pickup_datetime is not null
