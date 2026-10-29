-- 01 Cohort counts
--
-- How many patients, hospital admissions and ICU stays the warehouse
-- holds, overall and broken down by anchor year group and by the care unit
-- where each ICU stay began. Every later result should be read against
-- these numbers: with 100 patients, a single death moves a unit's mortality
-- by several percentage points.
--
-- The anchor year group is the real 3-year window a patient's shifted
-- dates map to; it is the only real-calendar time MIMIC reveals.
--
-- An admission whose ICU stays began in two different units counts once in
-- each, so the care-unit rows add up to more than the total admissions.

with base as (
    select
        p.anchor_year_group,
        a.patient_key,
        a.admission_key,
        s.stay_id,
        -- Admissions without an ICU stay get their own row in the
        -- care-unit breakdown.
        coalesce(cu.care_unit, 'No ICU stay') as care_unit
    from marts.fact_hospital_admission as a
    inner join marts.dim_patient as p
        on a.patient_key = p.patient_key
    left join marts.fact_icu_stay as s
        on a.admission_key = s.admission_key
    left join marts.dim_care_unit as cu
        on s.first_care_unit_key = cu.care_unit_key
)

-- grouping sets computes three groupings in one pass: the total, one row
-- per year group, and one row per care unit. grouping(col) = 0 tells which
-- grouping a row belongs to.
select
    case
        when grouping(care_unit) = 0 then 'First care unit'
        when grouping(anchor_year_group) = 0 then 'Anchor year group'
        else 'All'
    end as breakdown,
    coalesce(anchor_year_group, care_unit, 'All') as category,
    count(distinct patient_key) as patients,
    count(distinct admission_key) as admissions,
    count(stay_id) as icu_stays
from base
group by grouping sets ((), (anchor_year_group), (care_unit))
order by
    grouping(anchor_year_group) desc,
    grouping(care_unit) desc,
    icu_stays desc,
    category asc
