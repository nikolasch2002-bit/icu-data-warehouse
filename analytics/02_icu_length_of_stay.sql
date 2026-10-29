-- 02 ICU length of stay per unit
--
-- Median and interquartile range (IQR) of ICU length of stay, in days, by
-- the care unit where the stay began. Length of stay is right-skewed: a few
-- very long stays pull the mean up, so the median and IQR describe a
-- typical stay better. Units with only a handful of stays are shown but
-- should not be compared.

with stays as (
    select
        cu.care_unit,
        cu.care_unit_type,
        s.icu_los_hours / 24 as los_days
    from marts.fact_icu_stay as s
    inner join marts.dim_care_unit as cu
        on s.first_care_unit_key = cu.care_unit_key
)

select
    care_unit,
    care_unit_type,
    count(*) as icu_stays,
    -- percentile_cont interpolates between values, as the median of an
    -- even-sized group should.
    round(
        (percentile_cont(0.5) within group (order by los_days))::numeric, 1
    ) as median_days,
    round(
        (percentile_cont(0.25) within group (order by los_days))::numeric, 1
    ) as q1_days,
    round(
        (percentile_cont(0.75) within group (order by los_days))::numeric, 1
    ) as q3_days,
    round(max(los_days), 1) as max_days
from stays
group by care_unit, care_unit_type
order by icu_stays desc, care_unit asc
