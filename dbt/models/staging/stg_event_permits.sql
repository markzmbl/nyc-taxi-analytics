with source as (

    select * from {{ source('raw', 'event_permits') }}

)

select
    (payload->>'event_id')::bigint                as event_id,
    trim(payload->>'event_name')                  as event_name,
    (payload->>'start_date_time')::timestamp      as start_at,
    (payload->>'end_date_time')::timestamp        as end_at,
    trim(payload->>'event_type')                  as event_type,
    trim(payload->>'event_borough')               as borough,
    trim(payload->>'event_location')              as event_location,
    trim(payload->>'street_closure_type')         as street_closure_type,
    nullif(split_part(regexp_replace(payload->>'police_precinct', '[^0-9,]', '', 'g'), ',', 1), '')::int as police_precinct
from source
where payload->>'start_date_time' is not null
  and payload->>'event_id' is not null
