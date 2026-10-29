-- Grain: one row per admission and ICD code.

select
    dim_patient.patient_key,
    dim_admission.admission_key,
    dim_diagnosis.diagnosis_key,
    -- Priority within the admission; 1 is the main diagnosis.
    diagnoses.seq_num
from {{ ref('stg_hosp__diagnoses_icd') }} as diagnoses
inner join {{ ref('dim_patient') }} as dim_patient
    on diagnoses.subject_id = dim_patient.subject_id
inner join {{ ref('dim_admission') }} as dim_admission
    on diagnoses.hadm_id = dim_admission.hadm_id
-- Code and version together: the same code can mean different things in
-- ICD-9 and ICD-10.
inner join {{ ref('dim_diagnosis') }} as dim_diagnosis
    on
        diagnoses.icd_code = dim_diagnosis.icd_code
        and diagnoses.icd_version = dim_diagnosis.icd_version
