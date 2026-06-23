with source as (

    select * from {{ source('raw', 'citibike_trips') }}

)

select
    tripduration::int                         as trip_duration_sec,
    starttime::timestamp                      as started_at,
    stoptime::timestamp                       as ended_at,
    "start station id"::int                   as start_station_id,
    trim("start station name")                as start_station_name,
    "start station latitude"::numeric(10,6)   as start_lat,
    "start station longitude"::numeric(10,6)  as start_lng,
    "end station id"::int                     as end_station_id,
    trim("end station name")                  as end_station_name,
    "end station latitude"::numeric(10,6)     as end_lat,
    "end station longitude"::numeric(10,6)    as end_lng,
    bikeid::int                               as bike_id,
    trim(usertype)                            as user_type,
    "birth year"::int                         as birth_year,
    gender::int                               as gender
from source
where starttime is not null
  and stoptime is not null
