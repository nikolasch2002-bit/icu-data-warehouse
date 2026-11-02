-- Public: one row per hospital admission, for the Overview and Mortality
-- pages and the readmission rate.
--
-- No identifiers or dates. Age is the age at admission as a 10-year band.
-- Length of stay is rounded to 0.1 days, so an exact duration cannot be
-- matched to a record elsewhere. Insurance, language, race, marital status
-- and admission and discharge locations are left out: no page uses them.

with icu_admissions as (
    select distinct admission_key
    from {{ ref('fact_icu_stay') }}
)

select
    p.gender,
    -- anchor_age is the age in anchor_year; add the years since then.
    {{ age_band(
        'p.anchor_age + extract(year from a.admittime)::integer'
        ~ ' - p.anchor_year'
    ) }} as age_band,
    p.anchor_year_group,
    d.admission_type,
    a.came_through_ed,
    i.admission_key is not null as had_icu_stay,
    round(a.los_days, 1) as los_days,
    a.died_in_hospital,
    a.readmitted_within_30_days
from {{ ref('fact_hospital_admission') }} as a
inner join {{ ref('dim_patient') }} as p
    on a.patient_key = p.patient_key
inner join {{ ref('dim_admission') }} as d
    on a.admission_key = d.admission_key
left join icu_admissions as i
    on a.admission_key = i.admission_key
