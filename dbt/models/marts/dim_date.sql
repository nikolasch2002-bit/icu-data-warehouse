-- One row per calendar day from 2100-01-01 to 2214-12-31. MIMIC shifts
-- every date into the 2100s-2200s, so a normal calendar table would match
-- nothing. Generated, not read from any source.
--
-- date_key is the date as a number, e.g. 21250411 for 2125-04-11: still an
-- integer key, but readable, and it sorts like the date.

with days as (
    select series_day::date as date_day
    from generate_series(
        '2100-01-01'::date,
        '2214-12-31'::date,
        interval '1 day'
    ) as series_day
)

select
    date_day,
    to_char(date_day, 'YYYYMMDD')::integer as date_key,
    extract(year from date_day)::integer as year,
    extract(month from date_day)::integer as month,
    -- ISO numbering: 1 = Monday ... 7 = Sunday.
    extract(isodow from date_day)::integer as day_of_week,
    trim(to_char(date_day, 'Day')) as day_name,
    extract(isodow from date_day) in (6, 7) as is_weekend
from days
