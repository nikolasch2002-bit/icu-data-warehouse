-- A patient cannot die in hospital before being admitted. Returns any
-- admission whose death time comes before its admission time.
select
    hadm_id,
    admittime,
    deathtime
from {{ ref('stg_hosp__admissions') }}
where deathtime < admittime
