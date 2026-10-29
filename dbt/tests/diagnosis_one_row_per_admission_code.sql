-- The grain of fact_diagnosis: one row per admission and ICD code.
-- Returns any admission that lists the same code twice.
select
    hadm_id,
    icd_code,
    icd_version,
    count(*) as n_rows
from {{ ref('stg_hosp__diagnoses_icd') }}
group by hadm_id, icd_code, icd_version
having count(*) > 1
