select
    d.date_day,
    avg(w.temperature)    as avg_temperature,
    min(w.temperature)    as min_temperature,
    max(w.temperature)    as max_temperature,
    sum(w.precip_depth)   as total_precip_depth,
    max(w.snow_depth)     as max_snow_depth,
    avg(w.wind_speed)     as avg_wind_speed
from {{ ref('dim_date') }} d
left join {{ ref('stg_weather') }} w
    on d.date_day = w.observation_datetime::date
group by d.date_day
