{{
  config(
    materialized='table'
  )
}}

with date_bounds as (

    select min(pickup_date) as min_dt, max(pickup_date) as max_dt
    from {{ ref('fact_trips') }}

),

dates as (

    select d.date_day
    from {{ ref('dim_date') }} d
    cross join date_bounds b
    where d.date_day >= b.min_dt
      and d.date_day <= b.max_dt

),

taxi as (

    select
        pickup_date as activity_date,
        count(*)                                          as taxi_trips,
        sum(total_amount)                                 as taxi_revenue,
        sum(case when taxi_type = 'yellow' then 1 else 0 end)  as yellow_trips,
        sum(case when taxi_type = 'yellow' then total_amount end) as yellow_revenue,
        sum(case when taxi_type = 'green'  then 1 else 0 end)  as green_trips,
        sum(case when taxi_type = 'green'  then total_amount end) as green_revenue,
        sum(case when taxi_type = 'fhv'    then 1 else 0 end)  as fhv_trips,
        sum(case when taxi_type = 'fhv'    then total_amount end) as fhv_revenue,
        sum(case when taxi_type = 'fhvhv'  then 1 else 0 end)  as fhvhv_trips,
        sum(case when taxi_type = 'fhvhv'  then total_amount end) as fhvhv_revenue
    from {{ ref('fact_trips') }}
    group by 1

),

subway as (

    select
        observed_date as activity_date,
        sum(total_entries) as subway_entries,
        sum(total_exits)   as subway_exits
    from {{ ref('fact_subway_entries') }}
    group by 1

),

citibike as (

    select
        trip_date as activity_date,
        count(*)  as citibike_trips,
        avg(trip_duration_sec) as citibike_avg_duration_sec
    from {{ ref('fact_citibike_trips') }}
    group by 1

),

complaints as (

    select
        complaint_date as activity_date,
        count(*)       as complaints_311_count
    from {{ ref('fact_311_complaints') }}
    group by 1

),

events as (

    select
        event_date as activity_date,
        count(*)   as event_permits_count
    from {{ ref('fact_event_permits') }}
    group by 1

),

air as (

    select
        observation_date as activity_date,
        avg(case when parameter_code = 44201 then arithmetic_mean end) as avg_ozone,
        avg(case when parameter_code = 88101 then arithmetic_mean end) as avg_pm25,
        max(aqi) as max_aqi
    from {{ ref('fact_air_quality') }}
    group by 1

),

weather as (

    select
        date_day as activity_date,
        avg_temperature,
        total_precip_depth,
        max_snow_depth,
        avg_wind_speed
    from {{ ref('dim_weather') }}

),

holidays as (

    select
        date_day as activity_date,
        is_holiday,
        holiday_name
    from {{ ref('dim_holidays') }}

)

select
    d.date_day,
    coalesce(t.taxi_trips, 0)              as taxi_trips,
    coalesce(t.taxi_revenue, 0)            as taxi_revenue,
    coalesce(t.yellow_trips, 0)            as yellow_trips,
    coalesce(t.yellow_revenue, 0)          as yellow_revenue,
    coalesce(t.green_trips, 0)             as green_trips,
    coalesce(t.green_revenue, 0)           as green_revenue,
    coalesce(t.fhv_trips, 0)               as fhv_trips,
    coalesce(t.fhv_revenue, 0)             as fhv_revenue,
    coalesce(t.fhvhv_trips, 0)             as fhvhv_trips,
    coalesce(t.fhvhv_revenue, 0)           as fhvhv_revenue,
    coalesce(s.subway_entries, 0)          as subway_entries,
    coalesce(s.subway_exits, 0)            as subway_exits,
    coalesce(c.citibike_trips, 0)          as citibike_trips,
    c.citibike_avg_duration_sec,
    coalesce(co.complaints_311_count, 0)   as complaints_311_count,
    coalesce(e.event_permits_count, 0)     as event_permits_count,
    a.avg_ozone,
    a.avg_pm25,
    a.max_aqi,
    w.avg_temperature,
    w.total_precip_depth,
    w.max_snow_depth,
    w.avg_wind_speed,
    h.is_holiday,
    h.holiday_name
from dates d
left join taxi t       on d.date_day = t.activity_date
left join subway s     on d.date_day = s.activity_date
left join citibike c   on d.date_day = c.activity_date
left join complaints co on d.date_day = co.activity_date
left join events e     on d.date_day = e.activity_date
left join air a        on d.date_day = a.activity_date
left join weather w    on d.date_day = w.activity_date
left join holidays h   on d.date_day = h.activity_date
