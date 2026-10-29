-- The facts are built with inner joins to their dimensions. If a lookup
-- failed, the join would silently drop the row. Returns a row for any fact
-- whose row count differs from its staging source.
select
    'fact_hospital_admission' as fact,
    (select count(*) from {{ ref('stg_hosp__admissions') }}) as source_rows,
    (select count(*) from {{ ref('fact_hospital_admission') }}) as fact_rows
where
    (select count(*) from {{ ref('stg_hosp__admissions') }})
    <> (select count(*) from {{ ref('fact_hospital_admission') }})

union all

select
    'fact_icu_stay' as fact,
    (select count(*) from {{ ref('stg_icu__icustays') }}) as source_rows,
    (select count(*) from {{ ref('fact_icu_stay') }}) as fact_rows
where
    (select count(*) from {{ ref('stg_icu__icustays') }})
    <> (select count(*) from {{ ref('fact_icu_stay') }})
