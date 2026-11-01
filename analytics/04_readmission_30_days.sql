-- 04 30-day hospital readmission rate
--
-- The share of discharged-alive admissions that were followed by another
-- admission of the same patient within 30 days of discharge, overall, by
-- admission type, and by whether the admission included an ICU stay.
-- Admissions that ended in death are left out of the denominator: a
-- patient who died cannot be readmitted. Any next admission counts,
-- planned or not, so this is an all-cause rate.
--
-- The demo holds every admission of its 100 patients, so a missed
-- readmission would only be one to another hospital, which MIMIC cannot
-- see.

with icu_admissions as (
    select distinct admission_key
    from marts.fact_icu_stay
),

admissions as (
    select
        a.readmitted_within_30_days,
        d.admission_type,
        case
            when i.admission_key is not null then 'ICU stay'
            else 'No ICU stay'
        end as icu_status
    from marts.fact_hospital_admission as a
    inner join marts.dim_admission as d
        on a.admission_key = d.admission_key
    left join icu_admissions as i
        on a.admission_key = i.admission_key
    -- The flag is null for in-hospital deaths.
    where a.readmitted_within_30_days is not null
)

select
    case
        when grouping(admission_type) = 0 then 'Admission type'
        when grouping(icu_status) = 0 then 'ICU'
        else 'All'
    end as breakdown,
    coalesce(admission_type, icu_status, 'All admissions') as category,
    count(*) as discharged_alive,
    count(*) filter (where readmitted_within_30_days) as readmitted,
    round(
        100.0 * count(*) filter (where readmitted_within_30_days) / count(*),
        1
    ) as readmission_pct
from admissions
group by grouping sets ((), (admission_type), (icu_status))
order by
    -- 'All' first, then the two breakdowns.
    grouping(admission_type) + grouping(icu_status) desc,
    breakdown asc,
    discharged_alive desc,
    category asc
