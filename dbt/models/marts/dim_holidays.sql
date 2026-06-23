select
    d.date_day,
    h.holiday_name,
    h.holiday_name is not null as is_holiday
from {{ ref('dim_date') }} d
left join {{ ref('stg_holidays') }} h
    on d.date_day = h.holiday_date
