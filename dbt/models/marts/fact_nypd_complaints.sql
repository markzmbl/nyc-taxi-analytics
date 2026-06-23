-- NYPD complaint facts — one row per complaint, ready for geospatial joins.

select
    complaint_num,
    complaint_date,
    complaint_time,
    boro,
    offense_description,
    pd_description,
    law_category,
    crime_status,
    location_type,
    premise_type,
    jurisdiction,
    precinct,
    patrol_boro,
    station_name,
    suspect_age_group,
    suspect_race,
    suspect_sex,
    victim_age_group,
    victim_race,
    victim_sex,
    latitude,
    longitude,
    loaded_at
from {{ ref('stg_nypd_complaints') }}
