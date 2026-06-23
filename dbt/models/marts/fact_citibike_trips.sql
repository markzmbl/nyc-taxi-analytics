{{
  config(
    materialized='incremental',
    unique_key='trip_surrogate_key',
    incremental_strategy='delete+insert'
  )
}}

with trips as (

    select
        {{ dbt_utils.generate_surrogate_key([
            'bike_id',
            'started_at',
            'start_station_id',
            'end_station_id'
        ]) }} as trip_surrogate_key,
        started_at,
        ended_at,
        started_at::date as trip_date,
        trip_duration_sec,
        start_station_id,
        start_station_name,
        start_lat,
        start_lng,
        end_station_id,
        end_station_name,
        end_lat,
        end_lng,
        bike_id,
        user_type,
        birth_year,
        gender,
        {{ map_to_taxi_zone('start_lat', 'start_lng') }} as start_taxi_zone_id,
        {{ map_to_taxi_zone('end_lat', 'end_lng') }}     as end_taxi_zone_id
    from {{ ref('stg_citibike_trips') }}
    where 1=1
    {% if is_incremental() %}
      and started_at > (select max(started_at) from {{ this }})
    {% endif %}

)

select * from trips
