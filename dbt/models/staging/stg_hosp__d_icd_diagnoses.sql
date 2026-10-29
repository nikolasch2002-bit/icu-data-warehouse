-- The ICD-9 and ICD-10 diagnosis dictionary, one row per code and version.
-- The same code string can mean different things in the two versions, so
-- (icd_code, icd_version) is the key, never icd_code alone.

with source as (
    select * from {{ source('hosp', 'd_icd_diagnoses') }}
)

select
    icd_code,
    icd_version::integer as icd_version,
    long_title
from source
