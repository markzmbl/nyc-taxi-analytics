-- Engine-agnostic core model: proves the warehouse + dbt wiring works
-- regardless of which demo content (if any) is installed.
select
    1 as id,
    'hello from the analytics blueprint' as message
