{{
  config(
    materialized='table'
  )
}}

select
    event_id,
    event_name,
    start_at,
    end_at,
    start_at::date as event_date,
    event_type,
    borough,
    event_location,
    street_closure_type,
    police_precinct,
    extract(epoch from (end_at - start_at)) / 3600.0 as duration_hours
from {{ ref('stg_event_permits') }}
