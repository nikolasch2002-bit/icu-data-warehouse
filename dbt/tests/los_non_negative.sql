-- No stay can be shorter than zero. Returns any admission or ICU stay with
-- a negative length of stay.
select
    'fact_hospital_admission' as fact,
    admission_key as row_key,
    los_days as los
from {{ ref('fact_hospital_admission') }}
where los_days < 0

union all

select
    'fact_icu_stay' as fact,
    stay_id as row_key,
    icu_los_hours as los
from {{ ref('fact_icu_stay') }}
where icu_los_hours < 0
