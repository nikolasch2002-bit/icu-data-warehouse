-- One row per lab result, typed from raw.labevents. The free-text comments
-- column is left out: notes are out of scope, and it adds nothing the
-- queries use.

with source as (
    select * from {{ source('hosp', 'labevents') }}
)

select
    labevent_id::integer as labevent_id,
    subject_id::integer as subject_id,
    -- Null for labs taken outside a hospital admission (about a quarter).
    hadm_id::integer as hadm_id,
    -- Results from the same sample share a specimen_id.
    specimen_id::integer as specimen_id,
    itemid::integer as itemid,
    charttime::timestamp as charttime,
    storetime::timestamp as storetime,
    -- The result as reported. Some results are text only, e.g. 'NEG'.
    value,
    -- The numeric result, null when the result is text only.
    valuenum::numeric as valuenum,
    valueuom,
    ref_range_lower::numeric as ref_range_lower,
    ref_range_upper::numeric as ref_range_upper,
    -- ROUTINE or STAT, sometimes missing.
    priority,
    -- MIMIC sets flag to 'abnormal' or leaves it empty.
    coalesce(flag = 'abnormal', false) as is_abnormal
from source
