-- Every diagnosis must have a title in the ICD dictionary, matched on code
-- and version together. Returns the diagnoses that have none.
select
    d.hadm_id,
    d.icd_code,
    d.icd_version
from {{ ref('stg_hosp__diagnoses_icd') }} as d
left join {{ ref('stg_hosp__d_icd_diagnoses') }} as dict
    on
        d.icd_code = dict.icd_code
        and d.icd_version = dict.icd_version
where dict.icd_code is null
