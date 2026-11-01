-- 05 Top 20 diagnoses, with their ICD chapter
--
-- The 20 ICD codes recorded on the most admissions (more if codes tie for
-- 20th place), with the chapter each
-- belongs to and the number of distinct patients. All diagnosis positions
-- count, not only the main one, so long-term conditions such as
-- hypertension and hyperlipidemia rank high: they are coded on almost
-- every admission of the patients who have them.
--
-- The hospital switched from ICD-9 to ICD-10 in 2015 (in real time, before
-- MIMIC shifted the dates), so
-- the same condition can appear twice, once per version: hypertension is
-- both 4019 (ICD-9) and I10 (ICD-10). Chapter numbers also differ between
-- versions, so the chapter is shown by name. ICD-9 V codes belong to a
-- supplementary classification with no chapter number.

with counts as (
    select
        d.icd_version,
        d.icd_code,
        d.title,
        d.chapter_number,
        d.chapter,
        count(*) as admissions,
        count(distinct f.patient_key) as patients
    from marts.fact_diagnosis as f
    inner join marts.dim_diagnosis as d
        on f.diagnosis_key = d.diagnosis_key
    group by d.icd_version, d.icd_code, d.title, d.chapter_number, d.chapter
),

top_codes as (
    -- with ties keeps every code tied with the 20th, where limit 20 would
    -- drop some of them. A tie means equal on every order by column, so
    -- this sorts on admissions alone; the final order comes below.
    select *
    from counts
    order by admissions desc
    fetch first 20 rows with ties
)

select
    -- rank gives tied codes the same position (two codes at 8, then 10).
    rank() over (order by admissions desc) as rank_position,
    icd_version,
    icd_code,
    title,
    chapter_number,
    chapter,
    admissions,
    patients
from top_codes
order by admissions desc, icd_version asc, icd_code asc
