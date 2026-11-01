-- 08 Lactate clearance in the first 24 hours of an ICU stay
--
-- Lactate builds up in the blood when tissues get too little oxygen, as
-- in shock. A raised lactate that falls quickly is a sign that
-- resuscitation is working, so lactate clearance is a common target in
-- sepsis care. This query takes the ICU stays whose first lactate in the
-- first 24 hours was 2 mmol/L or more, and compares that first value with
-- the last one taken in the same 24 hours:
--
-- clearance % = (first - last) / first * 100
--
-- Stays are grouped by whether lactate fell by at least 10%, a threshold
-- widely used in sepsis studies, and in-hospital mortality is shown per
-- group. Lactates taken before ICU admission, in the emergency department
-- for example, are not used, so the first value is the first one in the
-- ICU. The groups are small: read the mortality as a direction, not a
-- rate.

with lactate as (
    select
        l.patient_key,
        l.charttime,
        l.labevent_id,
        l.valuenum
    from marts.fact_lab_result as l
    inner join marts.dim_lab_item as i
        on l.lab_item_key = i.lab_item_key
    where
        i.itemid = 50813
        and l.valuenum is not null
),

first_day as (
    -- The lactates in each stay's first 24 hours, with the first and last
    -- value of that window on every row. As in query 06, last_value needs
    -- the full frame.
    select
        s.stay_id,
        s.admission_key,
        first_value(l.valuenum) over by_time as first_lactate,
        last_value(l.valuenum) over (
            by_time
            rows between unbounded preceding and unbounded following
        ) as last_lactate,
        count(*) over (partition by s.stay_id) as lactates
    from marts.fact_icu_stay as s
    inner join lactate as l
        on
            s.patient_key = l.patient_key
            and l.charttime between s.intime and s.intime + interval '24 hours'
    -- labevent_id breaks ties between lactates taken at the same time.
    window by_time as (
        partition by s.stay_id order by l.charttime asc, l.labevent_id asc
    )
),

raised as (
    -- One row per stay, kept only if the first lactate was raised.
    select distinct
        stay_id,
        admission_key,
        lactates,
        first_lactate,
        last_lactate,
        round(100 * (first_lactate - last_lactate) / first_lactate, 1)
            as clearance_pct
    from first_day
    where first_lactate >= 2
),

grouped as (
    select
        r.clearance_pct,
        a.died_in_hospital,
        r.first_lactate,
        r.last_lactate,
        case
            -- A single lactate gives nothing to compare.
            when r.lactates = 1 then 'No repeat lactate'
            when r.clearance_pct >= 10 then 'Cleared by 10% or more'
            else 'Cleared by less than 10%'
        end as clearance_group
    from raised as r
    inner join marts.fact_hospital_admission as a
        on r.admission_key = a.admission_key
)

select
    clearance_group,
    count(*) as icu_stays,
    -- The medians describe each group; with no repeat, first = last.
    round(
        (percentile_cont(0.5) within group (order by first_lactate))::numeric,
        1
    ) as median_first_lactate,
    round(
        (percentile_cont(0.5) within group (order by last_lactate))::numeric,
        1
    ) as median_last_lactate,
    count(*) filter (where last_lactate < 2) as normalised_below_2,
    count(*) filter (where died_in_hospital) as died_in_hospital,
    round(
        100.0 * count(*) filter (where died_in_hospital) / count(*), 1
    ) as mortality_pct
from grouped
group by clearance_group
order by
    case clearance_group
        when 'Cleared by 10% or more' then 0
        when 'Cleared by less than 10%' then 1
        else 2
    end asc
