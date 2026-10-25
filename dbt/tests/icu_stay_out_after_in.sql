-- An ICU stay cannot end before it starts. Returns the rows that do.
select
    stay_id,
    intime,
    outtime
from {{ ref('stg_icu__icustays') }}
where outtime < intime
