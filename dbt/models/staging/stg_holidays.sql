with source as (

    select payload, loaded_at
    from {{ source('raw', 'holidays') }}

)

select
    (payload ->> 'date')::date                        as holiday_date,
    trim(payload ->> 'normalizeHolidayName')          as holiday_name,
    trim(payload ->> 'countryRegionCode')             as country_code,
    (payload ->> 'isPaidTimeOff')::boolean            as is_paid_time_off,
    loaded_at
from source
where trim(payload ->> 'countryRegionCode') = 'US'
