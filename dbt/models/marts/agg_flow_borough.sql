select
    g.granularity_name,
    date_trunc(g.date_trunc_arg, f.pickup_date)::date as period_start,
    pz.borough as pickup_borough,
    dz.borough as dropoff_borough,
    count(*)                       as trip_count,
    avg(f.total_amount)::numeric(10,2)  as avg_total_amount,
    avg(f.trip_distance)::numeric(10,2) as avg_trip_distance
from {{ ref('fact_trips') }} f
cross join {{ ref('granularity_options') }} g
left join {{ ref('dim_taxi_zones') }} pz
    on f.pickup_location_id = pz.location_id
left join {{ ref('dim_taxi_zones') }} dz
    on f.dropoff_location_id = dz.location_id
group by
    g.granularity_name,
    date_trunc(g.date_trunc_arg, f.pickup_date)::date,
    pz.borough,
    dz.borough
