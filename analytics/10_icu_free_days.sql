-- 10 ICU-free days at day 28
--
-- ICU-free days count the days a patient was alive and out of the ICU in
-- the 28 days after their first ICU admission. A patient who dies within
-- the 28 days gets 0, however long they were out of the ICU before. The
-- measure is a common outcome in critical-care trials because it combines
-- survival and length of ICU stay in one number: higher is better.
--
-- One row per patient, starting at their first ICU stay in the data. ICU
-- time counts every stay of that patient in the window, including a
-- return to the ICU in a later admission, cut off at day 28. Deaths come
-- from the date of death (dod), which includes deaths after discharge, so
-- a patient who died at home on day 20 also gets 0.

with first_stays as (
    -- Each patient's first ICU stay: the start of their 28-day window.
    select distinct on (s.patient_key)
        s.patient_key,
        s.intime as window_start,
        s.intime + interval '28 days' as window_end,
        cu.care_unit_type
    from marts.fact_icu_stay as s
    inner join marts.dim_care_unit as cu
        on s.first_care_unit_key = cu.care_unit_key
    order by s.patient_key asc, s.intime asc, s.stay_id asc
),

icu_days as (
    -- The part of each stay that falls inside the patient's window: from
    -- the later of the two starts to the earlier of the two ends. A stay
    -- that starts after the window gets a negative overlap, set to 0.
    select
        f.patient_key,
        sum(
            greatest(
                extract(
                    epoch from
                    least(s.outtime, f.window_end)
                    - greatest(s.intime, f.window_start)
                ),
                0
            )
        ) / 86400 as days_in_icu
    from first_stays as f
    inner join marts.fact_icu_stay as s
        on f.patient_key = s.patient_key
    group by f.patient_key
),

patients as (
    select
        f.care_unit_type,
        p.dod is not null and p.dod <= f.window_end::date as died_by_day_28,
        case
            when p.dod is not null and p.dod <= f.window_end::date then 0
            -- An ICU stay can only cover the 28 days, never more.
            else 28 - least(d.days_in_icu, 28)
        end as icu_free_days
    from first_stays as f
    inner join icu_days as d
        on f.patient_key = d.patient_key
    inner join marts.dim_patient as p
        on f.patient_key = p.patient_key
)

select
    coalesce(care_unit_type, 'All') as first_care_unit_type,
    count(*) as patients,
    count(*) filter (where died_by_day_28) as died_by_day_28,
    round(
        (percentile_cont(0.5) within group (order by icu_free_days))::numeric,
        1
    ) as median_icu_free_days,
    round(
        (percentile_cont(0.25) within group (order by icu_free_days))::numeric,
        1
    ) as q1_icu_free_days,
    round(
        (percentile_cont(0.75) within group (order by icu_free_days))::numeric,
        1
    ) as q3_icu_free_days
from patients
group by grouping sets ((), (care_unit_type))
order by grouping(care_unit_type) desc, patients desc, care_unit_type asc
