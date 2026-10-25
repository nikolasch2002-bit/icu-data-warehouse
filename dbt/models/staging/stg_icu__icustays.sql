-- One row per ICU stay, typed from raw.icustays.

with source as (
    select * from {{ source('icu', 'icustays') }}
)

select
    stay_id::integer as stay_id,
    hadm_id::integer as hadm_id,
    subject_id::integer as subject_id,
    -- A stay can move between units; these are where it started and ended.
    first_careunit,
    last_careunit,
    intime::timestamp as intime,
    outtime::timestamp as outtime,
    -- Length of stay in fractional days, as MIMIC computes it from
    -- outtime - intime.
    los::numeric as los
from source
