-- Green taxi trips: borough/outer-borough service.
-- Airbyte normalized all columns to lowercase without underscores.

with source as (

    select * from {{ source('raw', 'taxi_trips_green') }}

)

select
    vendorid::int                               as vendor_id,
    lpeppickupdatetime::timestamp               as pickup_datetime,
    lpepdropoffdatetime::timestamp              as dropoff_datetime,
    passengercount::int                         as passenger_count,
    tripdistance::numeric(10,2)                 as trip_distance,
    pulocationid::int                           as pickup_location_id,
    dolocationid::int                           as dropoff_location_id,
    ratecodeid::int                             as ratecode_id,
    trim(storeandfwdflag)                       as store_and_fwd_flag,
    paymenttype::int                            as payment_type,
    fareamount::numeric(10,2)                   as fare_amount,
    extra::numeric(10,2)                        as extra,
    mtatax::numeric(10,2)                       as mta_tax,
    tipamount::numeric(10,2)                    as tip_amount,
    tollsamount::numeric(10,2)                  as tolls_amount,
    ehailfee::numeric(10,2)                     as ehail_fee,
    improvementsurcharge::numeric(10,2)         as improvement_surcharge,
    totalamount::numeric(10,2)                  as total_amount,
    null::numeric(10,2)                         as congestion_surcharge,
    triptype::int                               as trip_type
from source
where lpeppickupdatetime is not null
  and lpepdropoffdatetime is not null
