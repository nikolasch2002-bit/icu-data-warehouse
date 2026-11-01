-- The facts store each event time twice: as a timestamp, for intervals,
-- and as date_key / time_key, for grouping through dim_date and dim_time.
-- Both come from the same column today. Returns a row for any fact row
-- where they disagree, so a later change to one expression but not the
-- other fails the build.
with mismatches as (
    select
        'fact_lab_result' as fact,
        labevent_id::text as row_id
    from {{ ref('fact_lab_result') }}
    where
        date_key <> to_char(charttime, 'YYYYMMDD')::integer
        or time_key <> extract(hour from charttime)::integer

    union all

    select
        'fact_vital_sign' as fact,
        stay_id::text as row_id
    from {{ ref('fact_vital_sign') }}
    where
        date_key <> to_char(charttime, 'YYYYMMDD')::integer
        or time_key <> extract(hour from charttime)::integer

    union all

    select
        'fact_icu_stay' as fact,
        stay_id::text as row_id
    from {{ ref('fact_icu_stay') }}
    where in_date_key <> to_char(intime, 'YYYYMMDD')::integer

    union all

    select
        'fact_hospital_admission' as fact,
        admission_key::text as row_id
    from {{ ref('fact_hospital_admission') }}
    where
        admit_date_key <> to_char(admittime, 'YYYYMMDD')::integer
        or discharge_date_key <> to_char(dischtime, 'YYYYMMDD')::integer
)

select
    fact,
    row_id
from mismatches
