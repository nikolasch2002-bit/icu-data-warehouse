-- One row per hour of the day, 0-23. A measurement belongs to the hour it
-- was taken in, minutes ignored, so 14:59 is hour 14 (day shift) and 15:00
-- is hour 15 (evening shift). The shifts are those in docs/data-model.md.

with hours as (
    select series_hour::integer as hour_of_day
    from generate_series(0, 23) as series_hour
)

select
    -- The hour itself is the key: small, readable and already unique.
    hour_of_day as time_key,
    hour_of_day,
    case
        when hour_of_day between 7 and 14 then 'day'
        when hour_of_day between 15 and 22 then 'evening'
        else 'night'
    end as shift
from hours
