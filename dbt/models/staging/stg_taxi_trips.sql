-- Yellow taxi trips. Airbyte preserved the original Parquet camelCase column names.
-- Actual columns: vendorID, tpepPickupDateTime, tpepDropoffDateTime, passengerCount,
-- tripDistance, puLocationId (text), doLocationId (text), rateCodeId, storeAndFwdFlag,
-- paymentType (text), fareAmount, extra, mtaTax, tipAmount, tollsAmount,
-- improvementSurcharge (text), totalAmount. No congestion_surcharge column present.

with source as (

    select * from {{ source('raw', 'taxi_trips') }}

)

select
    "vendorID"::int                              as vendor_id,
    "tpepPickupDateTime"::timestamp              as pickup_datetime,
    "tpepDropoffDateTime"::timestamp             as dropoff_datetime,
    "passengerCount"::int                        as passenger_count,
    "tripDistance"::numeric(10,2)                as trip_distance,
    "puLocationId"::int                          as pickup_location_id,
    "doLocationId"::int                          as dropoff_location_id,
    "rateCodeId"::int                            as ratecode_id,
    trim("storeAndFwdFlag")                      as store_and_fwd_flag,
    "paymentType"::int                           as payment_type,
    "fareAmount"::numeric(10,2)                  as fare_amount,
    "extra"::numeric(10,2)                       as extra,
    "mtaTax"::numeric(10,2)                      as mta_tax,
    "tipAmount"::numeric(10,2)                   as tip_amount,
    "tollsAmount"::numeric(10,2)                 as tolls_amount,
    "improvementSurcharge"::numeric(10,2)        as improvement_surcharge,
    "totalAmount"::numeric(10,2)                 as total_amount,
    null::numeric(10,2)                          as congestion_surcharge
from source
where "tpepPickupDateTime" is not null
  and "tpepDropoffDateTime" is not null
