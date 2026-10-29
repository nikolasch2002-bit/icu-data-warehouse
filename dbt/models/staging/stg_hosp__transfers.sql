-- One row per movement of a patient between locations, typed from
-- raw.transfers. Used for the transfer count in fact_icu_stay.

with source as (
    select * from {{ source('hosp', 'transfers') }}
)

select
    transfer_id::integer as transfer_id,
    subject_id::integer as subject_id,
    -- Null for ED visits that did not lead to an admission.
    hadm_id::integer as hadm_id,
    -- admit, transfer, discharge or ED.
    eventtype,
    -- The unit the patient moved into. Null on discharge rows.
    careunit,
    intime::timestamp as intime,
    -- Null on discharge rows, which mark a moment rather than a stay.
    outtime::timestamp as outtime
from source
