-- dim_diagnosis has one row per ICD code and version. A code in two
-- overlapping chapter ranges would appear twice; this returns such codes.
select
    icd_code,
    icd_version,
    count(*) as n_rows
from {{ ref('dim_diagnosis') }}
group by icd_code, icd_version
having count(*) > 1
