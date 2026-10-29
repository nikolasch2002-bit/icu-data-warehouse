-- One row per admission and ICD code, typed from raw.diagnoses_icd.

with source as (
    select * from {{ source('hosp', 'diagnoses_icd') }}
)

select
    hadm_id::integer as hadm_id,
    subject_id::integer as subject_id,
    -- Priority of the diagnosis within the admission; 1 is the main one.
    seq_num::integer as seq_num,
    -- Stored without the dot, e.g. 41401 for ICD-9 414.01.
    icd_code,
    icd_version::integer as icd_version
from source
