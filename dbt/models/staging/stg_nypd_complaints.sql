-- Flatten key fields from raw.nypd_complaints JSONB for geospatial joins.

with source as (
    select * from {{ source('raw', 'nypd_complaints') }}
)

select
    trim(payload ->> 'cmplnt_num')                                      as complaint_num,
    (payload ->> 'cmplnt_fr_dt')::date                               as complaint_date,
    (payload ->> 'cmplnt_fr_tm')::time                               as complaint_time,
    trim(payload ->> 'boro_nm')                                      as boro,
    trim(payload ->> 'ofns_desc')                                    as offense_description,
    trim(payload ->> 'pd_desc')                                      as pd_description,
    trim(payload ->> 'law_cat_cd')                                   as law_category,
    trim(payload ->> 'crm_atpt_cptd_cd')                             as crime_status,
    trim(payload ->> 'loc_of_occur_desc')                            as location_type,
    trim(payload ->> 'prem_typ_desc')                                as premise_type,
    trim(payload ->> 'juris_desc')                                   as jurisdiction,
    (payload ->> 'addr_pct_cd')::int                                 as precinct,
    trim(payload ->> 'patrol_boro')                                  as patrol_boro,
    trim(payload ->> 'station_name')                                 as station_name,
    trim(payload ->> 'susp_age_group')                                as suspect_age_group,
    trim(payload ->> 'susp_race')                                    as suspect_race,
    trim(payload ->> 'susp_sex')                                     as suspect_sex,
    trim(payload ->> 'vic_age_group')                                as victim_age_group,
    trim(payload ->> 'vic_race')                                     as victim_race,
    trim(payload ->> 'vic_sex')                                      as victim_sex,
    (payload ->> 'latitude')::numeric(12,8)                          as latitude,
    (payload ->> 'longitude')::numeric(12,8)                         as longitude,
    loaded_at
from source
where payload ->> 'cmplnt_num' is not null
  and payload ->> 'cmplnt_fr_dt' is not null
