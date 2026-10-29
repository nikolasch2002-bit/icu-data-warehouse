-- Every date the facts will use must exist in dim_date. Returns any
-- admission, ICU stay, lab or vital-sign date outside its range.
with used_dates as (
    select admittime::date as date_day from {{ ref('stg_hosp__admissions') }}
    union
    select dischtime::date from {{ ref('stg_hosp__admissions') }}
    union
    select intime::date from {{ ref('stg_icu__icustays') }}
    union
    select charttime::date from {{ ref('stg_hosp__labevents') }}
    union
    select charttime::date from {{ ref('stg_icu__chartevents') }}
)

select used_dates.date_day
from used_dates
left join {{ ref('dim_date') }} as d
    on used_dates.date_day = d.date_day
where d.date_day is null
