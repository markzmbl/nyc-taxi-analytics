with source as (

    select * from {{ source('raw', 'complaints_311') }}

)

select
    (payload->>'unique_key')::bigint              as complaint_id,
    (payload->>'created_date')::timestamp         as created_at,
    (payload->>'closed_date')::timestamp          as closed_at,
    trim(payload->>'complaint_type')              as complaint_type,
    trim(payload->>'descriptor')                  as descriptor,
    trim(payload->>'borough')                     as borough,
    (payload->>'latitude')::numeric(10,6)         as latitude,
    (payload->>'longitude')::numeric(10,6)        as longitude,
    trim(payload->>'incident_zip')                as incident_zip,
    trim(payload->>'agency')                      as agency,
    trim(payload->>'agency_name')                 as agency_name,
    trim(payload->>'status')                      as status,
    trim(payload->>'resolution_description')      as resolution_description,
    trim(payload->>'location_type')               as location_type
from source
where payload->>'created_date' is not null
  and payload->>'unique_key' is not null
