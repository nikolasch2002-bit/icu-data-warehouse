-- 09 Hyperkalemia and the vital signs around it
--
-- A blood potassium of 5.5 mmol/L or more (hyperkalemia) can slow the
-- heart and cause dangerous arrhythmias. For each ICU stay with a
-- potassium of 5.5 or more during the stay, this query takes the first
-- such result and compares the vital signs in the 6 hours before it with
-- the 6 hours after: the lowest heart rate, the highest heart rate and the
-- lowest mean arterial pressure (MAP, non-invasive). Comparing the same
-- stays before and after shows what changed, not just how sick these
-- patients were to begin with.
--
-- Flags per stay and period: bradycardia (heart rate below 60), tachycardia
-- (above 100) and hypotension (MAP below 65). Serum and whole-blood
-- potassium both count. A raised potassium can be a lab artefact (from a
-- haemolysed sample), and treatment usually starts within the 6 hours, so
-- the 'after' period shows the combined effect of the potassium and its
-- treatment. Many raised results come soon after ICU admission, before
-- any vitals were charted, so fewer stays have a 'before' period.

with hyperkalemia as (
    -- The first potassium of 5.5 or more in each ICU stay. distinct on
    -- keeps one row per stay: the earliest, with labevent_id breaking
    -- ties between results taken at the same time.
    select distinct on (s.stay_id)
        s.stay_id,
        l.charttime as flagged_at,
        l.valuenum as potassium
    from marts.fact_icu_stay as s
    inner join marts.fact_lab_result as l
        on
            s.patient_key = l.patient_key
            and l.charttime between s.intime and s.outtime
    inner join marts.dim_lab_item as i
        on l.lab_item_key = i.lab_item_key
    where
        -- 50971 serum potassium, 50822 whole blood (blood gas).
        i.itemid in (50971, 50822)
        and l.valuenum >= 5.5
    order by s.stay_id asc, l.charttime asc, l.labevent_id asc
),

vitals_around as (
    -- The stay's heart rate and MAP values within 6 hours either side of
    -- the flagged result, labelled by period. The result's own minute
    -- counts as 'after'.
    select
        h.stay_id,
        ci.label,
        v.valuenum,
        case
            when v.charttime < h.flagged_at then '6 h before'
            else '6 h after'
        end as period
    from hyperkalemia as h
    inner join marts.fact_vital_sign as v
        on
            h.stay_id = v.stay_id
            and v.charttime >= h.flagged_at - interval '6 hours'
            and v.charttime < h.flagged_at + interval '6 hours'
    inner join marts.dim_chart_item as ci
        on v.chart_item_key = ci.chart_item_key
    where ci.itemid in (220045, 220181)
),

per_stay as (
    -- One row per stay and period. A stay with no values in a period has
    -- no row for it, so each period counts only the stays charted then.
    select
        stay_id,
        period,
        min(valuenum) filter (where label = 'Heart Rate') as min_hr,
        max(valuenum) filter (where label = 'Heart Rate') as max_hr,
        min(valuenum) filter (
            where label = 'Non Invasive Blood Pressure mean'
        ) as min_map
    from vitals_around
    group by stay_id, period
)

select
    period,
    (select count(*) from hyperkalemia) as stays_with_hyperkalemia,
    count(*) as stays_with_vitals,
    round(
        (percentile_cont(0.5) within group (order by min_hr))::numeric, 0
    ) as median_lowest_hr,
    round(
        (percentile_cont(0.5) within group (order by max_hr))::numeric, 0
    ) as median_highest_hr,
    round(
        (percentile_cont(0.5) within group (order by min_map))::numeric, 0
    ) as median_lowest_map,
    count(*) filter (where min_hr < 60) as bradycardia,
    count(*) filter (where max_hr > 100) as tachycardia,
    count(*) filter (where min_map < 65) as hypotension
from per_stay
group by period
order by period desc
