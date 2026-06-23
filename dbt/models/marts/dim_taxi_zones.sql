select
    location_id,
    borough,
    zone,
    service_zone,
    centroid_lat,
    centroid_lon
from {{ ref('taxi_zone_lookup') }}
