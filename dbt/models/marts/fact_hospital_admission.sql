-- Grain: one row per hospital admission.

with admissions as (
    select * from {{ ref('stg_hosp__admissions') }}
),

next_admission as (
    -- For each admission, when the same patient's next admission starts.
    -- partition by subject_id: look only at that patient's admissions.
    -- order by admittime: "next" means the next one in time.
    select
        hadm_id,
        lead(admittime) over (
            partition by subject_id
            order by admittime
        ) as next_admittime
    from admissions
)

select
    dim_admission.admission_key,
    dim_patient.patient_key,
    to_char(admissions.admittime, 'YYYYMMDD')::integer as admit_date_key,
    to_char(admissions.dischtime, 'YYYYMMDD')::integer as discharge_date_key,
    round(
        extract(epoch from admissions.dischtime - admissions.admittime) / 86400,
        2
    ) as los_days,
    admissions.hospital_expire_flag as died_in_hospital,
    admissions.edregtime is not null as came_through_ed,
    -- True if the patient's next admission starts within 30 days of this
    -- discharge. Null when the patient died in hospital: they cannot be
    -- readmitted, so a readmission rate must leave them out.
    case
        when admissions.hospital_expire_flag then null
        else coalesce(
            next_admission.next_admittime
            <= admissions.dischtime + interval '30 days',
            false
        )
    end as readmitted_within_30_days
from admissions
inner join next_admission
    on admissions.hadm_id = next_admission.hadm_id
inner join {{ ref('dim_admission') }} as dim_admission
    on admissions.hadm_id = dim_admission.hadm_id
inner join {{ ref('dim_patient') }} as dim_patient
    on admissions.subject_id = dim_patient.subject_id
