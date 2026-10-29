-- Each shift is 8 hours, and the boundaries are where docs/data-model.md
-- puts them. Returns any shift with the wrong hours.
select
    shift,
    min(hour_of_day) as first_hour,
    max(hour_of_day) as last_hour,
    count(*) as n_hours
from {{ ref('dim_time') }}
group by shift
having
    count(*) <> 8
    or (shift = 'day' and (min(hour_of_day) <> 7 or max(hour_of_day) <> 14))
    or (
        shift = 'evening'
        and (min(hour_of_day) <> 15 or max(hour_of_day) <> 22)
    )
    -- Night wraps around midnight: hour 23 and hours 0-6.
    or (
        shift = 'night'
        and (
            min(hour_of_day) <> 0
            or max(hour_of_day) <> 23
            or count(*) filter (where hour_of_day between 7 and 22) > 0
        )
    )
