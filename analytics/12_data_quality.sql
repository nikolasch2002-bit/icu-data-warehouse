-- 12 Data-quality report
--
-- Checks on the source data that the marts either guard against or pass
-- through, with the number of rows each one finds. Orphan rows point to
-- an admission or ICU stay that does not exist; the facts are built with
-- inner joins and dbt tests, so these checks run on the staging views to
-- show what the source holds. Out-of-range values are physiologically
-- impossible vital signs, such as a heart rate of 0 in a living patient;
-- they usually come from a disconnected monitor or a typing error, and
-- they stay in the marts, so queries that use vitals should keep them in
-- mind. Timing finds vital signs charted before the stay's in-time or
-- after its out-time. Duplicate charting is the same measurement recorded
-- twice at the same time.
--
-- The plausible ranges are deliberately wide, so a flagged value is
-- almost certainly an error rather than a very sick patient. A count of 0
-- is a passed check.

with vital_limits as (
    -- Plausible range per vital sign, in the unit of dim_chart_item.
    select *
    from (
        values
        (220045, 1, 300),   -- heart rate, bpm
        (220179, 30, 300),  -- systolic blood pressure, mmHg
        (220180, 10, 200),  -- diastolic blood pressure, mmHg
        (220181, 15, 250),  -- mean blood pressure, mmHg
        (220210, 1, 80),    -- respiratory rate, breaths/min
        (220277, 50, 100),  -- oxygen saturation, %
        (223761, 25, 45)    -- temperature, °C
    ) as limits (itemid, low, high)
),

checks as (
    select
        1 as check_order,
        'Orphan rows' as category,
        'Lab result with an unknown admission' as check_name,
        (
            select count(*)
            from staging.stg_hosp__labevents as l
            where
                l.hadm_id is not null
                and not exists (
                    select 1
                    from staging.stg_hosp__admissions as a
                    where l.hadm_id = a.hadm_id
                )
        ) as rows_found,
        (select count(*) from staging.stg_hosp__labevents) as rows_checked

    union all

    select
        2 as check_order,
        'Orphan rows' as category,
        'Diagnosis with an unknown admission' as check_name,
        (
            select count(*)
            from staging.stg_hosp__diagnoses_icd as d
            where not exists (
                select 1
                from staging.stg_hosp__admissions as a
                where d.hadm_id = a.hadm_id
            )
        ) as rows_found,
        (select count(*) from staging.stg_hosp__diagnoses_icd) as rows_checked

    union all

    select
        3 as check_order,
        'Orphan rows' as category,
        'ICU stay with an unknown admission' as check_name,
        (
            select count(*)
            from staging.stg_icu__icustays as s
            where not exists (
                select 1
                from staging.stg_hosp__admissions as a
                where s.hadm_id = a.hadm_id
            )
        ) as rows_found,
        (select count(*) from staging.stg_icu__icustays) as rows_checked

    union all

    select
        4 as check_order,
        'Orphan rows' as category,
        'Vital sign with an unknown ICU stay' as check_name,
        (
            select count(*)
            from staging.stg_icu__chartevents as v
            where not exists (
                select 1
                from staging.stg_icu__icustays as s
                where v.stay_id = s.stay_id
            )
        ) as rows_found,
        (select count(*) from staging.stg_icu__chartevents) as rows_checked

    union all

    select
        5 as check_order,
        'Timing' as category,
        'Vital sign charted outside its ICU stay' as check_name,
        (
            select count(*)
            from marts.fact_vital_sign as v
            inner join marts.fact_icu_stay as s
                on v.stay_id = s.stay_id
            where v.charttime not between s.intime and s.outtime
        ) as rows_found,
        (select count(*) from marts.fact_vital_sign) as rows_checked

    union all

    -- One row per vital sign: how many of its values fall outside the
    -- plausible range.
    select
        6 as check_order,
        'Out of range' as category,
        ci.label || ' outside ' || lim.low || '-' || lim.high || ' '
        || ci.unit as check_name,
        count(*) filter (
            where v.valuenum not between lim.low and lim.high
        ) as rows_found,
        count(*) as rows_checked
    from marts.fact_vital_sign as v
    inner join marts.dim_chart_item as ci
        on v.chart_item_key = ci.chart_item_key
    inner join vital_limits as lim
        on ci.itemid = lim.itemid
    group by ci.label, ci.unit, lim.low, lim.high

    union all

    -- Duplicates: rows beyond the first for the same measurement at the
    -- same time (same stay and item for vitals, same patient and test for
    -- labs). A group of 3 identical rows counts 2.
    select
        7 as check_order,
        'Duplicate charting' as category,
        'Vital sign charted twice at the same time' as check_name,
        coalesce(sum(copies - 1), 0)::bigint as rows_found,
        (select count(*) from marts.fact_vital_sign) as rows_checked
    from (
        select count(*) as copies
        from marts.fact_vital_sign
        group by stay_id, chart_item_key, charttime
        having count(*) > 1
    ) as dup

    union all

    select
        8 as check_order,
        'Duplicate charting' as category,
        'Lab result repeated at the same time' as check_name,
        coalesce(sum(copies - 1), 0)::bigint as rows_found,
        (select count(*) from marts.fact_lab_result) as rows_checked
    from (
        select count(*) as copies
        from marts.fact_lab_result
        group by patient_key, lab_item_key, charttime
        having count(*) > 1
    ) as dup

    union all

    -- The same repeats, counted only where the values disagree: these are
    -- the ones a query cannot resolve by keeping either row.
    select
        9 as check_order,
        'Duplicate charting' as category,
        '... of which with different values' as check_name,
        coalesce(sum(copies - 1), 0)::bigint as rows_found,
        (select count(*) from marts.fact_lab_result) as rows_checked
    from (
        select count(*) as copies
        from marts.fact_lab_result
        group by patient_key, lab_item_key, charttime
        having count(distinct valuenum) > 1
    ) as dup
)

select
    category,
    check_name,
    rows_found,
    rows_checked,
    round(100.0 * rows_found / rows_checked, 2) as pct_of_rows
from checks
order by check_order asc, check_name asc
