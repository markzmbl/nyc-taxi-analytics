{{
  config(
    materialized='incremental',
    unique_key='trip_surrogate_key',
    incremental_strategy='delete+insert'
  )
}}

with trips as (

    -- -----------------------------------------------------------------------
    -- Yellow taxi: standard medallion cabs
    -- -----------------------------------------------------------------------
    select
        {{ dbt_utils.generate_surrogate_key([
            "'yellow'",
            'vendor_id',
            'pickup_datetime',
            'dropoff_datetime',
            'pickup_location_id',
            'dropoff_location_id',
            'total_amount'
        ]) }} as trip_surrogate_key,
        'yellow'                        as taxi_type,
        vendor_id                       as vendor_id,
        vendor_id::text                 as base_identifier,
        pickup_datetime,
        dropoff_datetime,
        pickup_datetime::date           as pickup_date,
        dropoff_datetime::date          as dropoff_date,
        passenger_count,
        trip_distance,
        pickup_location_id,
        dropoff_location_id,
        ratecode_id,
        store_and_fwd_flag,
        payment_type,
        fare_amount,
        extra,
        mta_tax,
        tip_amount,
        tolls_amount,
        improvement_surcharge,
        total_amount,
        congestion_surcharge
    from {{ ref('stg_taxi_trips') }}
    where 1=1
    {% if is_incremental() %}
      and pickup_datetime > (select max(pickup_datetime) from {{ this }})
    {% endif %}

    union all

    -- -----------------------------------------------------------------------
    -- Green taxi: borough / outer-borough street-hail liveries
    -- -----------------------------------------------------------------------
    select
        {{ dbt_utils.generate_surrogate_key([
            "'green'",
            'vendor_id',
            'pickup_datetime',
            'dropoff_datetime',
            'pickup_location_id',
            'dropoff_location_id',
            'total_amount'
        ]) }} as trip_surrogate_key,
        'green'                         as taxi_type,
        vendor_id                       as vendor_id,
        vendor_id::text                 as base_identifier,
        pickup_datetime,
        dropoff_datetime,
        pickup_datetime::date           as pickup_date,
        dropoff_datetime::date          as dropoff_date,
        passenger_count,
        trip_distance,
        pickup_location_id,
        dropoff_location_id,
        ratecode_id,
        store_and_fwd_flag,
        payment_type,
        fare_amount,
        extra,
        mta_tax,
        tip_amount,
        tolls_amount,
        improvement_surcharge,
        total_amount,
        congestion_surcharge
    from {{ ref('stg_taxi_trips_green') }}
    where 1=1
    {% if is_incremental() %}
      and pickup_datetime > (select max(pickup_datetime) from {{ this }})
    {% endif %}

    union all

    -- -----------------------------------------------------------------------
    -- FHV: traditional for-hire vehicles (black cars, livery, limousines)
    -- No fare / passenger / distance data available in TLC feed.
    -- -----------------------------------------------------------------------
    select
        {{ dbt_utils.generate_surrogate_key([
            "'fhv'",
            'dispatching_base_num',
            'pickup_datetime',
            'dropoff_datetime',
            'pickup_location_id',
            'dropoff_location_id'
        ]) }} as trip_surrogate_key,
        'fhv'                           as taxi_type,
        null::int                       as vendor_id,
        dispatching_base_num            as base_identifier,
        pickup_datetime,
        dropoff_datetime,
        pickup_datetime::date           as pickup_date,
        dropoff_datetime::date          as dropoff_date,
        null::int                       as passenger_count,
        null::numeric(10,2)             as trip_distance,
        pickup_location_id,
        dropoff_location_id,
        null::int                       as ratecode_id,
        null                            as store_and_fwd_flag,
        null::int                       as payment_type,
        null::numeric(10,2)             as fare_amount,
        null::numeric(10,2)             as extra,
        null::numeric(10,2)             as mta_tax,
        null::numeric(10,2)             as tip_amount,
        null::numeric(10,2)             as tolls_amount,
        null::numeric(10,2)             as improvement_surcharge,
        null::numeric(10,2)             as total_amount,
        null::numeric(10,2)             as congestion_surcharge
    from {{ ref('stg_taxi_trips_fhv') }}
    where dropoff_datetime is not null
    {% if is_incremental() %}
      and pickup_datetime > (select max(pickup_datetime) from {{ this }})
    {% endif %}

    union all

    -- -----------------------------------------------------------------------
    -- FHVHV: high-volume for-hire vehicles (Uber, Lyft, Via, Juno)
    -- Includes detailed fare breakdowns distinct from yellow/green structure.
    -- -----------------------------------------------------------------------
    select
        {{ dbt_utils.generate_surrogate_key([
            "'fhvhv'",
            'hvfhs_license_num',
            'pickup_datetime',
            'dropoff_datetime',
            'pickup_location_id',
            'dropoff_location_id',
            'coalesce(base_passenger_fare, 0) + coalesce(tolls_amount, 0) + coalesce(bcf_amount, 0) + coalesce(sales_tax, 0) + coalesce(congestion_surcharge, 0) + coalesce(airport_fee, 0) + coalesce(tips_amount, 0)'
        ]) }} as trip_surrogate_key,
        'fhvhv'                         as taxi_type,
        null::int                       as vendor_id,
        hvfhs_license_num               as base_identifier,
        pickup_datetime,
        dropoff_datetime,
        pickup_datetime::date           as pickup_date,
        dropoff_datetime::date          as dropoff_date,
        null::int                       as passenger_count,
        trip_miles                      as trip_distance,
        pickup_location_id,
        dropoff_location_id,
        null::int                       as ratecode_id,
        null                            as store_and_fwd_flag,
        null::int                       as payment_type,
        base_passenger_fare             as fare_amount,
        null::numeric(10,2)             as extra,
        null::numeric(10,2)             as mta_tax,
        tips_amount                     as tip_amount,
        tolls_amount                    as tolls_amount,
        null::numeric(10,2)             as improvement_surcharge,
        -- Total amount charged to passenger: sum of all FHVHV fare components
        coalesce(base_passenger_fare, 0)
            + coalesce(tolls_amount, 0)
            + coalesce(bcf_amount, 0)
            + coalesce(sales_tax, 0)
            + coalesce(congestion_surcharge, 0)
            + coalesce(airport_fee, 0)
            + coalesce(tips_amount, 0)  as total_amount,
        congestion_surcharge
    from {{ ref('stg_taxi_trips_fhvhv') }}
    where 1=1
    {% if is_incremental() %}
      and pickup_datetime > (select max(pickup_datetime) from {{ this }})
    {% endif %}

)

select * from trips
