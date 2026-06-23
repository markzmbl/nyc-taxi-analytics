{% macro map_to_taxi_zone(lat_col, lon_col) %}
(
    select z.location_id
    from {{ ref('taxi_zone_lookup') }} z
    where z.centroid_lat is not null
      and z.centroid_lon is not null
    order by
        ({{ lat_col }} - z.centroid_lat) ^ 2
      + ({{ lon_col }} - z.centroid_lon) ^ 2
    limit 1
)
{% endmacro %}
