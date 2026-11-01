-- 06 Creatinine trend per ICU stay
--
-- For each ICU stay, the first, peak and last serum creatinine (mg/dL)
-- measured between ICU admission and discharge, how many hours into the
-- stay the peak came, and the change from first to last. Creatinine rises
-- when the kidneys filter less, so a peak well above the first value
-- points to kidney injury during the stay; query 07 turns that into KDIGO
-- stages. Stays without a creatinine result during the stay are left out.
--
-- The trend is rising or falling when the last value differs from the
-- first by at least 0.3 mg/dL, the smallest rise KDIGO counts as kidney
-- injury, and stable otherwise. A stay with a single result has no trend.
-- Only serum creatinine (itemid 50912) is
-- used; the few whole-blood values from blood gas analysers are left out.

with creatinine as (
    -- Each result is placed in the ICU stay whose time window contains it.
    -- The join uses the patient and the times, not the admission: a stay
    -- belongs to one admission, and the window decides which results
    -- count.
    select
        s.stay_id,
        s.first_care_unit_key,
        s.intime,
        l.charttime,
        l.valuenum
    from marts.fact_icu_stay as s
    inner join marts.fact_lab_result as l
        on
            s.patient_key = l.patient_key
            and l.charttime between s.intime and s.outtime
    inner join marts.dim_lab_item as i
        on l.lab_item_key = i.lab_item_key
    where
        i.itemid = 50912
        and l.valuenum is not null
),

per_result as (
    -- Window functions add the stay's first, peak and last value to every
    -- result row of that stay, without collapsing the rows.
    select
        stay_id,
        first_care_unit_key,
        intime,
        first_value(valuenum) over by_time as first_value,
        -- last_value needs the full frame. With only order by, the default
        -- frame ends at the current row, so last_value would return the
        -- current row's value instead of the stay's last one.
        last_value(valuenum) over (
            by_time
            rows between unbounded preceding and unbounded following
        ) as last_value,
        max(valuenum) over by_stay as peak_value,
        -- The time of the peak: sort the stay's results by value, highest
        -- first; if the peak value repeats, the earliest one wins.
        first_value(charttime) over (
            by_stay
            order by valuenum desc, charttime asc
        ) as peak_time,
        count(*) over by_stay as results
    from creatinine
    window
        by_stay as (partition by stay_id),
        by_time as (partition by stay_id order by charttime asc)
),

per_stay as (
    -- Every row of a stay now holds the same values; keep one.
    select distinct
        stay_id,
        first_care_unit_key,
        intime,
        results,
        first_value,
        peak_value,
        peak_time,
        last_value
    from per_result
)

select
    p.stay_id,
    cu.care_unit,
    p.results,
    p.first_value,
    p.peak_value,
    round(extract(epoch from p.peak_time - p.intime) / 3600, 1)
        as hours_to_peak,
    p.last_value,
    p.last_value - p.first_value as change_first_to_last,
    case
        when p.results = 1 then 'one result'
        when p.last_value - p.first_value >= 0.3 then 'rising'
        when p.last_value - p.first_value <= -0.3 then 'falling'
        else 'stable'
    end as trend
from per_stay as p
inner join marts.dim_care_unit as cu
    on p.first_care_unit_key = cu.care_unit_key
order by p.peak_value - p.first_value desc, p.stay_id asc
