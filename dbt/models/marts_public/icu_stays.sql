-- Public: one row per ICU stay, for the Overview, Length of stay and
-- Mortality pages.
--
-- No identifiers or dates. Age is the age at ICU admission as a 10-year
-- band. Length of stay is in days rounded to 0.1, not exact hours, so a
-- stay cannot be matched to a record elsewhere by its duration.

select
    p.gender,
    {{ age_band(
        'p.anchor_age + extract(year from s.intime)::integer'
        ~ ' - p.anchor_year'
    ) }} as age_band,
    p.anchor_year_group,
    d.admission_type,
    first_unit.care_unit as first_care_unit,
    first_unit.care_unit_type as first_care_unit_type,
    last_unit.care_unit as last_care_unit,
    round(s.icu_los_hours / 24, 1) as icu_los_days,
    s.transfers_count,
    s.died_in_icu,
    a.died_in_hospital
from {{ ref('fact_icu_stay') }} as s
inner join {{ ref('dim_patient') }} as p
    on s.patient_key = p.patient_key
inner join {{ ref('dim_admission') }} as d
    on s.admission_key = d.admission_key
inner join {{ ref('fact_hospital_admission') }} as a
    on s.admission_key = a.admission_key
inner join {{ ref('dim_care_unit') }} as first_unit
    on s.first_care_unit_key = first_unit.care_unit_key
inner join {{ ref('dim_care_unit') }} as last_unit
    on s.last_care_unit_key = last_unit.care_unit_key
