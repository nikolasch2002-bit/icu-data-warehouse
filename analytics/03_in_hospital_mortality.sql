-- 03 In-hospital mortality
--
-- The share of hospital admissions that ended in death, by admission type
-- and by the care unit where the admission's first ICU stay began.
-- Admissions without an ICU stay appear as 'No ICU stay', which shows how
-- much of the mortality is concentrated in ICU patients. The counts are
-- small, so percentages are shown next to the numbers they come from.

with first_stay as (
    -- An admission can have several ICU stays. distinct on keeps one row
    -- per admission: the earliest stay, by in-date and then stay_id.
    select distinct on (s.admission_key)
        s.admission_key,
        cu.care_unit
    from marts.fact_icu_stay as s
    inner join marts.dim_care_unit as cu
        on s.first_care_unit_key = cu.care_unit_key
    order by s.admission_key, s.in_date_key, s.stay_id
),

admissions as (
    select
        a.died_in_hospital,
        d.admission_type,
        coalesce(fs.care_unit, 'No ICU stay') as care_unit
    from marts.fact_hospital_admission as a
    inner join marts.dim_admission as d
        on a.admission_key = d.admission_key
    left join first_stay as fs
        on a.admission_key = fs.admission_key
)

select
    case
        when grouping(admission_type) = 0 then 'Admission type'
        else 'First ICU care unit'
    end as breakdown,
    coalesce(admission_type, care_unit) as category,
    count(*) as admissions,
    count(*) filter (where died_in_hospital) as deaths,
    round(
        100.0 * count(*) filter (where died_in_hospital) / count(*), 1
    ) as mortality_pct
from admissions
group by grouping sets ((admission_type), (care_unit))
order by breakdown asc, admissions desc, category asc
