with source as (

    select payload from {{ source('raw', 'air_quality') }}

)

select
    (payload->>'date_local')::date                as observation_date,
    trim(payload->>'parameter')                   as parameter_name,
    (payload->>'parameter_code')::int             as parameter_code,
    (payload->>'poc')::int                        as poc,
    trim(payload->>'sample_duration_code')        as sample_duration_code,
    trim(payload->>'pollutant_standard')          as pollutant_standard,
    (payload->>'arithmetic_mean')::numeric(10,4)  as arithmetic_mean,
    (payload->>'aqi')::int                        as aqi,
    trim(payload->>'units_of_measure')            as units_of_measure,
    trim(payload->>'county_name')                 as county_name,
    (payload->>'county_code')::int                as county_code,
    trim(payload->>'site_number')                 as site_number,
    (payload->>'latitude')::numeric(10,6)         as latitude,
    (payload->>'longitude')::numeric(10,6)        as longitude,
    trim(payload->>'local_site_name')             as site_name,
    trim(payload->>'cbsa_name')                   as cbsa_name
from source
where payload->>'date_local' is not null
