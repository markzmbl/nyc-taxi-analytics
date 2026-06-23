{{
  config(
    materialized='table'
  )
}}

with station_map as (

    select
        s.station   as raw_station_name,
        s.line_name as raw_line_name,
        sl.station_complex_id
    from {{ ref('stg_subway_turnstiles') }} s
    cross join lateral (
        select station_complex_id
        from {{ ref('subway_station_lookup') }} sl
        order by levenshtein(upper(s.station), upper(sl.station_name))
        limit 1
    ) sl
    group by 1, 2, 3

),

daily as (

    select
        t.observed_date,
        sm.station_complex_id,
        sum(t.entry_delta)  as total_entries,
        sum(t.exit_delta)   as total_exits
    from {{ ref('stg_subway_turnstiles') }} t
    left join station_map sm
        on t.station = sm.raw_station_name
       and t.line_name = sm.raw_line_name
    where t.observed_date is not null
    group by 1, 2

)

select
    {{ dbt_utils.generate_surrogate_key(['observed_date', 'station_complex_id']) }} as entry_key,
    observed_date,
    station_complex_id,
    total_entries,
    total_exits,
    total_entries + total_exits as total_activity
from daily
