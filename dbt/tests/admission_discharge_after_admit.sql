-- An admission cannot end before it starts. Returns the rows that do.
select
    hadm_id,
    admittime,
    dischtime
from {{ ref('stg_hosp__admissions') }}
where dischtime < admittime
