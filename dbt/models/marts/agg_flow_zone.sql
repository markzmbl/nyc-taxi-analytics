select
    g.granularity_name,
    date_trunc(g.date_trunc_arg, f.pickup_date)::date as period_start,
    f.pickup_location_id,
    f.dropoff_location_id,
    pz.zone   as pickup_zone_name,
    pz.borough as pickup_borough,
    dz.zone   as dropoff_zone_name,
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
    f.pickup_location_id,
    f.dropoff_location_id,
    pz.zone, pz.borough,
    dz.zone, dz.borough
