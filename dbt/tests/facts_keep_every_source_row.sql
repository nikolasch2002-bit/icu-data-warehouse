-- The facts are built with inner joins to their dimensions. If a lookup
-- failed, the join would silently drop the row. Returns a row for any fact
-- whose row count differs from its staging source.
with counts as (
    select
        'fact_hospital_admission' as fact,
        (select count(*) from {{ ref('stg_hosp__admissions') }}) as source_rows,
        (select count(*) from {{ ref('fact_hospital_admission') }}) as fact_rows

    union all

    select
        'fact_icu_stay' as fact,
        (select count(*) from {{ ref('stg_icu__icustays') }}) as source_rows,
        (select count(*) from {{ ref('fact_icu_stay') }}) as fact_rows

    union all

    select
        'fact_diagnosis' as fact,
        (
            select count(*) from {{ ref('stg_hosp__diagnoses_icd') }}
        ) as source_rows,
        (select count(*) from {{ ref('fact_diagnosis') }}) as fact_rows

    union all

    select
        'fact_lab_result' as fact,
        (select count(*) from {{ ref('stg_hosp__labevents') }}) as source_rows,
        (select count(*) from {{ ref('fact_lab_result') }}) as fact_rows

    union all

    select
        'fact_vital_sign' as fact,
        (select count(*) from {{ ref('stg_icu__chartevents') }}) as source_rows,
        (select count(*) from {{ ref('fact_vital_sign') }}) as fact_rows
)

select
    fact,
    source_rows,
    fact_rows
from counts
where source_rows <> fact_rows
