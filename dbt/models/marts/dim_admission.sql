-- One row per hospital admission, plus one "outside an admission" row with
-- key -1 (docs/data-model.md, decision 3). Lab results taken outside an
-- admission point to that row, so fact_lab_result keeps every row of
-- labevents and never has a null key.
--
-- The descriptive columns live here rather than in the facts, which keeps
-- the facts narrow.

with admissions as (
    select
        row_number() over (order by hadm_id)::integer as admission_key,
        hadm_id,
        admission_type,
        admission_location,
        discharge_location,
        insurance,
        language,
        marital_status,
        race
    from {{ ref('stg_hosp__admissions') }}
),

outside_admission as (
    select
        -1 as admission_key,
        null::integer as hadm_id,
        'Outside an admission' as admission_type,
        null as admission_location,
        null as discharge_location,
        null as insurance,
        null as language,
        null as marital_status,
        null as race
)

select * from admissions
union all
select * from outside_admission
