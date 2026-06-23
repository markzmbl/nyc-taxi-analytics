with date_spine as (

    select
        d::date as date_day
    from generate_series(
        '2018-01-01'::date,
        '2024-12-31'::date,
        '1 day'::interval
    ) as d

)

select
    date_day,
    extract(dow from date_day)::int           as day_of_week,
    extract(dow from date_day) in (0, 6)      as is_weekend,
    trim(to_char(date_day, 'Day'))            as day_name,
    extract(month from date_day)::int         as month_number,
    trim(to_char(date_day, 'Month'))          as month_name,
    extract(quarter from date_day)::int       as quarter,
    extract(year from date_day)::int          as year
from date_spine
