select
    station_id,
    station_name,
    latitude,
    longitude,
    capacity,
    borough,
    {{ map_to_taxi_zone('latitude', 'longitude') }} as nearest_taxi_zone_id
from {{ ref('citibike_station_lookup') }}
