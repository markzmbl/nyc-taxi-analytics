-- Shred the nested JSONB payload from raw.restaurant_inspections.
-- Each payload is one inspection visit with 0..N violations in an array.

with source as (
    select * from {{ source('raw', 'restaurant_inspections') }}
),

flattened as (
    select
        (payload ->> 'camis')::int                                    as camis,
        trim(payload ->> 'dba')                                       as dba,
        trim(payload ->> 'boro')                                      as boro,
        trim(payload ->> 'building')                                  as building,
        trim(payload ->> 'street')                                    as street,
        trim(payload ->> 'zipcode')                                   as zipcode,
        trim(payload ->> 'phone')                                     as phone,
        trim(payload ->> 'cuisine_description')                       as cuisine,
        (payload ->> 'inspection_date')::date                         as inspection_date,
        trim(payload ->> 'inspection_type')                           as inspection_type,
        trim(payload ->> 'action')                                    as action,
        (payload ->> 'score')::int                                    as score,
        trim(payload ->> 'grade')                                     as grade,
        (payload ->> 'grade_date')::date                              as grade_date,
        (payload ->> 'latitude')::numeric(12,8)                       as latitude,
        (payload ->> 'longitude')::numeric(12,8)                      as longitude,
        payload -> 'violations'                                       as violations_json,
        jsonb_array_length(payload -> 'violations')                   as violation_count,
        loaded_at
    from source
    where payload ->> 'camis' is not null
      and payload ->> 'inspection_date' is not null
),

-- Unnest violations so each violation is its own row for easy querying
violations_unnested as (
    select
        camis,
        inspection_date,
        jsonb_array_elements(violations_json) ->> 'code'              as violation_code,
        jsonb_array_elements(violations_json) ->> 'description'       as violation_description,
        jsonb_array_elements(violations_json) ->> 'critical_flag'     as critical_flag
    from flattened
    where violations_json is not null
      and jsonb_array_length(violations_json) > 0
)

select
    f.camis,
    f.dba,
    f.boro,
    f.building,
    f.street,
    f.zipcode,
    f.phone,
    f.cuisine,
    f.inspection_date,
    f.inspection_type,
    f.action,
    f.score,
    f.grade,
    f.grade_date,
    f.latitude,
    f.longitude,
    f.violation_count,
    v.violation_code,
    v.violation_description,
    v.critical_flag,
    f.loaded_at
from flattened f
left join violations_unnested v
    on f.camis = v.camis
    and f.inspection_date = v.inspection_date
