-- Grain: one row per lab result (row of labevents), including results
-- taken outside an admission.

select
    -- Kept as a degenerate dimension, so a result can be traced back to
    -- its source row.
    labs.labevent_id,
    dim_patient.patient_key,
    -- Labs without an hadm_id go to the -1 "outside an admission" row.
    -- Only a null hadm_id maps to -1: if a real hadm_id found no match,
    -- the key stays null and the not_null test fails, instead of the row
    -- being hidden under -1.
    case
        when labs.hadm_id is null then -1
        else dim_admission.admission_key
    end as admission_key,
    dim_lab_item.lab_item_key,
    to_char(labs.charttime, 'YYYYMMDD')::integer as date_key,
    extract(hour from labs.charttime)::integer as time_key,
    labs.valuenum,
    labs.valueuom,
    labs.is_abnormal,
    labs.ref_range_lower,
    labs.ref_range_upper
from {{ ref('stg_hosp__labevents') }} as labs
inner join {{ ref('dim_patient') }} as dim_patient
    on labs.subject_id = dim_patient.subject_id
inner join {{ ref('dim_lab_item') }} as dim_lab_item
    on labs.itemid = dim_lab_item.itemid
left join {{ ref('dim_admission') }} as dim_admission
    on labs.hadm_id = dim_admission.hadm_id
