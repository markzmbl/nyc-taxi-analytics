{% macro get_max_loaded_at(source_name, source_table) %}
    select coalesce(max(loaded_at), '1900-01-01'::timestamptz)
    from {{ source(source_name, source_table) }}
{% endmacro %}
