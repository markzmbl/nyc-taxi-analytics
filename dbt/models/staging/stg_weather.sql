with source as (

    select payload, loaded_at
    from {{ source('raw', 'weather') }}

)

select
    (payload ->> 'datetime')::timestamp          as observation_datetime,
    (payload ->> 'temperature')::numeric(5,1)    as temperature,
    (payload ->> 'temperatureDewPoint')::numeric(5,1) as dew_point,
    (payload ->> 'precipDepth')::numeric(8,1)    as precip_depth,
    (payload ->> 'snowDepth')::numeric(8,1)      as snow_depth,
    (payload ->> 'windSpeed')::numeric(5,1)      as wind_speed,
    (payload ->> 'stationPressure')::numeric(10,2) as station_pressure,
    (payload ->> 'latitude')::numeric(9,6)       as latitude,
    (payload ->> 'longitude')::numeric(9,6)      as longitude,
    trim(payload ->> 'usaf')                     as station_id,
    loaded_at
from source
where (payload ->> 'datetime') is not null
