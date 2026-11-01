-- 11 Vital signs in the 24 hours before death, against matched survivors
--
-- How heart rate, blood pressure, breathing and oxygen saturation change
-- in the last 24 hours of patients who died in the ICU, next to the last
-- 24 hours of ICU stays that ended with the patient leaving alive. For each
-- death, the two surviving stays from the same type of care unit with the
-- closest age are the matches. The deaths are lined up on the time of
-- death, the survivors on the time they left the ICU, and both are cut
-- into four 6-hour blocks counting back from that moment. A survivor's
-- last 24 hours are the hours before they were well enough to leave, so
-- the comparison is between dying and recovering patients.
--
-- Within each block, each stay's values are averaged first and the median
-- is then taken across stays, so a stay that was charted every 15 minutes
-- does not outweigh one charted every hour. Survivors are matched with
-- replacement, so one survivor can match two deaths; it then counts once.
-- With 12 deaths the comparison shows patterns, not significance.

with deaths as (
    select
        s.stay_id,
        cu.care_unit_type,
        p.anchor_age,
        a.deathtime as anchor_time
    from marts.fact_icu_stay as s
    inner join marts.fact_hospital_admission as a
        on s.admission_key = a.admission_key
    inner join marts.dim_patient as p
        on s.patient_key = p.patient_key
    inner join marts.dim_care_unit as cu
        on s.first_care_unit_key = cu.care_unit_key
    where s.died_in_icu
),

survivor_candidates as (
    -- Stays whose patient left hospital alive, at least 24 hours long so
    -- every block lies inside the stay.
    select
        s.stay_id,
        cu.care_unit_type,
        p.anchor_age,
        s.outtime as anchor_time
    from marts.fact_icu_stay as s
    inner join marts.fact_hospital_admission as a
        on s.admission_key = a.admission_key
    inner join marts.dim_patient as p
        on s.patient_key = p.patient_key
    inner join marts.dim_care_unit as cu
        on s.first_care_unit_key = cu.care_unit_key
    where
        not a.died_in_hospital
        and s.icu_los_hours >= 24
),

matches as (
    -- For each death, rank the candidates of the same care unit type by
    -- age difference; stay_id breaks ties so the match is repeatable.
    select
        c.stay_id,
        c.anchor_time,
        row_number() over (
            partition by d.stay_id
            order by abs(c.anchor_age - d.anchor_age) asc, c.stay_id asc
        ) as match_rank
    from deaths as d
    inner join survivor_candidates as c
        on d.care_unit_type = c.care_unit_type
),

cohort as (
    select
        'Died in ICU' as outcome,
        stay_id,
        anchor_time
    from deaths

    union

    -- union, not union all: a survivor matched to two deaths counts once.
    select
        'Matched survivor' as outcome,
        stay_id,
        anchor_time
    from matches
    where match_rank <= 2
),

per_stay_block as (
    -- Each stay's mean of each vital in each 6-hour block. hours_before is
    -- 0 to 24; dividing by 6 and rounding down gives blocks 0 to 3, with
    -- block 0 the last 6 hours.
    select
        c.outcome,
        c.stay_id,
        floor(extract(epoch from c.anchor_time - v.charttime) / 3600 / 6)
            as block,
        avg(v.valuenum) filter (where ci.itemid = 220045) as heart_rate,
        avg(v.valuenum) filter (where ci.itemid = 220181) as mean_bp,
        avg(v.valuenum) filter (where ci.itemid = 220210) as resp_rate,
        avg(v.valuenum) filter (where ci.itemid = 220277) as spo2
    from cohort as c
    inner join marts.fact_vital_sign as v
        on
            c.stay_id = v.stay_id
            and v.charttime > c.anchor_time - interval '24 hours'
            and c.anchor_time >= v.charttime
    inner join marts.dim_chart_item as ci
        on v.chart_item_key = ci.chart_item_key
    group by c.outcome, c.stay_id, block
)

select
    outcome,
    (block * 6 + 6)::integer || '-' || (block * 6)::integer || ' h before'
        as hours_before_end,
    count(*) as stays,
    round(
        (percentile_cont(0.5) within group (order by heart_rate))::numeric, 0
    ) as median_heart_rate,
    round(
        (percentile_cont(0.5) within group (order by mean_bp))::numeric, 0
    ) as median_mean_bp,
    round(
        (percentile_cont(0.5) within group (order by resp_rate))::numeric, 0
    ) as median_resp_rate,
    round(
        (percentile_cont(0.5) within group (order by spo2))::numeric, 0
    ) as median_spo2
from per_stay_block
group by outcome, block
order by outcome asc, block desc
