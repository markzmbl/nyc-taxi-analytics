-- Restaurant inspection facts — one row per inspection (denormalised).
-- Violations are kept as an aggregated text array for dashboard display.

with inspections as (
    select *,
        row_number() over (
            partition by camis, inspection_date
            order by violation_code
        ) as rn
    from {{ ref('stg_restaurant_inspections') }}
),

violations_agg as (
    select
        camis,
        inspection_date,
        string_agg(
            violation_code || ': ' || violation_description,
            ' | '
            order by violation_code
        ) as violations_summary,
        count(*) filter (where critical_flag = 'Critical') as critical_count,
        count(*) filter (where critical_flag != 'Critical') as non_critical_count
    from inspections
    group by 1, 2
)

select
    i.camis,
    i.dba,
    i.boro,
    i.cuisine,
    i.inspection_date,
    i.inspection_type,
    i.action,
    i.score,
    i.grade,
    i.grade_date,
    i.latitude,
    i.longitude,
    i.zipcode,
    i.violation_count,
    coalesce(v.critical_count, 0)      as critical_violations,
    coalesce(v.non_critical_count, 0)  as non_critical_violations,
    v.violations_summary,
    i.loaded_at
from inspections i
join violations_agg v
    on i.camis = v.camis
    and i.inspection_date = v.inspection_date
where i.rn = 1
