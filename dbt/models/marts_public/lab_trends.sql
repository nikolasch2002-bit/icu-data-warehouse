-- Public: lab values over the days of an ICU stay, for the Lab trends page.
--
-- Aggregated, not one row per result: one row per lab test, first care
-- unit and day of the ICU stay, with the number of results and their
-- quartiles. The page draws how a test typically moves over a stay, which
-- needs no single patient's values. Day 0 is the first 24 hours.

with stay_labs as (
    -- Results with a number, taken during an ICU stay.
    select
        i.label,
        i.fluid,
        l.valueuom as unit,
        cu.care_unit as first_care_unit,
        floor(extract(epoch from l.charttime - s.intime) / 86400)::integer
            as icu_day,
        l.valuenum
    from {{ ref('fact_icu_stay') }} as s
    inner join {{ ref('fact_lab_result') }} as l
        on
            s.patient_key = l.patient_key
            and l.charttime between s.intime and s.outtime
    inner join {{ ref('dim_lab_item') }} as i
        on l.lab_item_key = i.lab_item_key
    inner join {{ ref('dim_care_unit') }} as cu
        on s.first_care_unit_key = cu.care_unit_key
    where l.valuenum is not null
)

select
    label,
    fluid,
    unit,
    first_care_unit,
    icu_day,
    count(*) as results,
    round(
        (percentile_cont(0.25) within group (order by valuenum))::numeric, 2
    ) as q1_value,
    round(
        (percentile_cont(0.5) within group (order by valuenum))::numeric, 2
    ) as median_value,
    round(
        (percentile_cont(0.75) within group (order by valuenum))::numeric, 2
    ) as q3_value
from stay_labs
group by label, fluid, unit, first_care_unit, icu_day
