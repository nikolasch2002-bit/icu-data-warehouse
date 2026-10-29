-- Grain: one row per ICU stay.

with stays as (
    select * from {{ ref('stg_icu__icustays') }}
),

moves as (
    -- Each ICU stay is made of one or more location records in transfers,
    -- the first starting at the stay's intime. The number of moves within
    -- the stay is the number of those records minus one.
    select
        stays.stay_id,
        count(*) - 1 as transfers_count
    from stays
    inner join {{ ref('stg_hosp__transfers') }} as transfers
        on
            stays.hadm_id = transfers.hadm_id
            and transfers.careunit is not null
            and stays.intime <= transfers.intime
            and stays.outtime > transfers.intime
    group by stays.stay_id
)

select
    -- Kept on the fact as a degenerate dimension: fact_vital_sign links
    -- to the stay through it.
    stays.stay_id,
    dim_patient.patient_key,
    dim_admission.admission_key,
    first_unit.care_unit_key as first_care_unit_key,
    last_unit.care_unit_key as last_care_unit_key,
    to_char(stays.intime, 'YYYYMMDD')::integer as in_date_key,
    round(
        extract(epoch from stays.outtime - stays.intime) / 3600, 1
    ) as icu_los_hours,
    -- Died during this stay: the admission's death time falls between the
    -- stay's in and out times. A death after leaving the ICU does not count.
    coalesce(
        admissions.deathtime between stays.intime and stays.outtime, false
    ) as died_in_icu,
    coalesce(moves.transfers_count, 0) as transfers_count
from stays
inner join {{ ref('stg_hosp__admissions') }} as admissions
    on stays.hadm_id = admissions.hadm_id
inner join {{ ref('dim_patient') }} as dim_patient
    on stays.subject_id = dim_patient.subject_id
inner join {{ ref('dim_admission') }} as dim_admission
    on stays.hadm_id = dim_admission.hadm_id
inner join {{ ref('dim_care_unit') }} as first_unit
    on stays.first_careunit = first_unit.care_unit
inner join {{ ref('dim_care_unit') }} as last_unit
    on stays.last_careunit = last_unit.care_unit
left join moves
    on stays.stay_id = moves.stay_id
