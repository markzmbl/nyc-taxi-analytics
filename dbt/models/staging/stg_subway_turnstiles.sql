with source as (

    select * from {{ source('raw', 'subway_turnstiles') }}

),

ordered as (

    select
        control_area,
        unit,
        scp,
        station,
        line_name,
        division,
        observed_at,
        entries_cum,
        exits_cum,
        lag(entries_cum) over (
            partition by control_area, unit, scp
            order by observed_at
        ) as prev_entries,
        lag(exits_cum) over (
            partition by control_area, unit, scp
            order by observed_at
        ) as prev_exits
    from source
    where observed_at is not null

),

deltas as (

    select
        control_area,
        unit,
        scp,
        station,
        line_name,
        division,
        observed_at,
        observed_at::date as observed_date,
        entries_cum,
        exits_cum,
        case
            when prev_entries is null then 0
            when entries_cum - prev_entries < 0 then 0
            when entries_cum - prev_entries > 50000 then 0
            else entries_cum - prev_entries
        end as entry_delta,
        case
            when prev_exits is null then 0
            when exits_cum - prev_exits < 0 then 0
            when exits_cum - prev_exits > 50000 then 0
            else exits_cum - prev_exits
        end as exit_delta
    from ordered

)

select * from deltas
