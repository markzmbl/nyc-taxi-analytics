{{
  config(
    materialized='table'
  )
}}

select distinct
    {{ dbt_utils.generate_surrogate_key([
        'observation_date',
        'parameter_code',
        'poc',
        'sample_duration_code',
        'pollutant_standard',
        'county_code',
        'site_number'
    ]) }} as air_quality_key,
    observation_date,
    parameter_name,
    parameter_code,
    poc,
    sample_duration_code,
    pollutant_standard,
    arithmetic_mean,
    aqi,
    units_of_measure,
    county_name,
    county_code,
    site_number,
    latitude,
    longitude,
    site_name,
    cbsa_name,
    case
        when latitude is not null and longitude is not null
        then {{ map_to_taxi_zone('latitude', 'longitude') }}
    end as taxi_zone_id
from {{ ref('stg_air_quality') }}
