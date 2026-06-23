select
    station_complex_id,
    station_name,
    latitude,
    longitude,
    borough,
    lines,
    {{ map_to_taxi_zone('latitude', 'longitude') }} as nearest_taxi_zone_id
from {{ ref('subway_station_lookup') }}
