-- 07 Acute kidney injury (AKI) by the KDIGO creatinine criteria
--
-- The highest KDIGO AKI stage reached during each ICU stay, and in-hospital
-- mortality per stage. Each serum creatinine result during the stay is
-- compared with the patient's own earlier results: the lowest in the
-- previous 7 days is the baseline for the ratio criteria, the lowest in
-- the previous 48 hours for the absolute rise. Earlier results count
-- wherever they were taken, so a ward lab the day before ICU admission
-- can be the baseline.
--
-- Stage 1: at least 1.5 times the 7-day baseline, or a rise of at least
-- 0.3 mg/dL over the 48-hour baseline. Stage 2: at least 2 times. Stage 3:
-- at least 3 times, or a value of 4.0 mg/dL or more that also meets a
-- stage 1 criterion. KDIGO also stages by urine output and by the start of
-- dialysis; neither is in this warehouse, so stages here can only be
-- underestimates.
--
-- A stay whose results have no earlier value within 7 days cannot be
-- staged ('No baseline'). This misses patients whose creatinine was
-- already high when they arrived, a known limit of baselines taken from
-- hospital data only.

with creatinine as (
    -- Every serum creatinine result of every patient, in or outside an
    -- admission, so earlier results can serve as baselines.
    select
        l.patient_key,
        l.charttime,
        l.valuenum
    from marts.fact_lab_result as l
    inner join marts.dim_lab_item as i
        on l.lab_item_key = i.lab_item_key
    where
        i.itemid = 50912
        and l.valuenum is not null
),

with_baselines as (
    -- The frame looks back in time from each result over the same
    -- patient's results. range (not rows) measures the frame in time, so
    -- '7 days preceding' means 7 days, however many results that covers.
    -- exclude group leaves out the current result and any other result
    -- taken at the same moment: a baseline must come before the value.
    select
        patient_key,
        charttime,
        valuenum,
        min(valuenum) over (
            partition by patient_key
            order by charttime asc
            range between interval '7 days' preceding and current row
            exclude group
        ) as baseline_7_days,
        min(valuenum) over (
            partition by patient_key
            order by charttime asc
            range between interval '48 hours' preceding and current row
            exclude group
        ) as baseline_48_hours
    from creatinine
),

staged_results as (
    -- The stage of each result taken during an ICU stay. A missing
    -- baseline makes its comparison null, which counts as not met; a
    -- result with no 7-day baseline at all gets a null stage.
    select
        s.stay_id,
        s.admission_key,
        case
            when b.baseline_7_days is null then null
            when
                b.valuenum >= 3 * b.baseline_7_days
                or (
                    b.valuenum >= 4.0
                    and (
                        b.valuenum >= 1.5 * b.baseline_7_days
                        or b.valuenum - b.baseline_48_hours >= 0.3
                    )
                )
                then 3
            when b.valuenum >= 2 * b.baseline_7_days then 2
            when
                b.valuenum >= 1.5 * b.baseline_7_days
                or b.valuenum - b.baseline_48_hours >= 0.3
                then 1
            else 0
        end as aki_stage
    from marts.fact_icu_stay as s
    inner join with_baselines as b
        on
            s.patient_key = b.patient_key
            and b.charttime between s.intime and s.outtime
),

stays as (
    -- One row per ICU stay with its highest stage. max ignores nulls, so
    -- a stay is staged if any of its results had a baseline.
    select
        s.stay_id,
        a.died_in_hospital,
        case
            when count(r.stay_id) = 0 then 'No creatinine during stay'
            when max(r.aki_stage) is null then 'No baseline'
            when max(r.aki_stage) = 0 then 'No AKI'
            else 'Stage ' || max(r.aki_stage)
        end as highest_stage
    from marts.fact_icu_stay as s
    inner join marts.fact_hospital_admission as a
        on s.admission_key = a.admission_key
    left join staged_results as r
        on s.stay_id = r.stay_id
    group by s.stay_id, a.died_in_hospital
)

select
    highest_stage,
    count(*) as icu_stays,
    round(100.0 * count(*) / sum(count(*)) over (), 1) as pct_of_stays,
    count(*) filter (where died_in_hospital) as died_in_hospital,
    round(
        100.0 * count(*) filter (where died_in_hospital) / count(*), 1
    ) as mortality_pct
from stays
group by highest_stage
order by
    case highest_stage
        when 'No AKI' then 0
        when 'Stage 1' then 1
        when 'Stage 2' then 2
        when 'Stage 3' then 3
        when 'No baseline' then 4
        else 5
    end asc
