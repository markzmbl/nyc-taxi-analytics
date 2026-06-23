{{
  config(
    materialized='incremental',
    unique_key='complaint_id',
    incremental_strategy='delete+insert'
  )
}}

with complaints as (

    select
        complaint_id,
        created_at,
        closed_at,
        created_at::date as complaint_date,
        complaint_type,
        descriptor,
        borough,
        latitude,
        longitude,
        incident_zip,
        agency,
        agency_name,
        status,
        resolution_description,
        location_type,
        case
            when latitude is not null and longitude is not null
            then {{ map_to_taxi_zone('latitude', 'longitude') }}
        end as taxi_zone_id,
        extract(epoch from (closed_at - created_at)) / 3600.0 as resolution_hours
    from {{ ref('stg_311_complaints') }}
    where 1=1
    {% if is_incremental() %}
      and created_at > (select coalesce(max(created_at), '1900-01-01'::timestamp) from {{ this }})
    {% endif %}

)

select * from complaints
