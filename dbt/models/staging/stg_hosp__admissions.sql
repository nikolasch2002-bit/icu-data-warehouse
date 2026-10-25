-- One row per hospital admission, typed from raw.admissions.

with source as (
    select * from {{ source('hosp', 'admissions') }}
)

select
    hadm_id::integer as hadm_id,
    subject_id::integer as subject_id,
    admittime::timestamp as admittime,
    dischtime::timestamp as dischtime,
    -- Set only for in-hospital deaths. It can differ from dischtime.
    deathtime::timestamp as deathtime,
    admission_type,
    admit_provider_id,
    admission_location,
    discharge_location,
    insurance,
    marital_status,
    race,
    -- Emergency department registration and exit. Null if the patient did
    -- not come through the ED.
    edregtime::timestamp as edregtime,
    edouttime::timestamp as edouttime,
    hospital_expire_flag::boolean as hospital_expire_flag,
    -- MIMIC writes '?' for an unknown language; null says that honestly.
    nullif(language, '?') as language
from source
