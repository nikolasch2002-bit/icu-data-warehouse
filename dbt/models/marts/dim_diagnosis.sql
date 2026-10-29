-- One row per ICD code and version, with the chapter it belongs to.
-- Chapters come from seeds/icd_chapters.csv, which lists each chapter's
-- first and last 3-character code (ICD-9-CM and ICD-10-CM).
--
-- The comparison uses the first 3 characters, e.g. '414' for ICD-9 41401
-- or 'I25' for ICD-10 I2510. COLLATE "C" compares byte by byte, so digits
-- sort before letters ('O99' < 'O9A') whatever the database's language
-- settings are.

with codes as (
    select
        icd_code,
        icd_version,
        long_title,
        left(icd_code, 3) collate "C" as code_prefix
    from {{ ref('stg_hosp__d_icd_diagnoses') }}
),

chapters as (
    select
        icd_version,
        chapter_number,
        chapter,
        code_from collate "C" as code_from,
        code_to collate "C" as code_to
    from {{ ref('icd_chapters') }}
)

select
    row_number() over (
        order by codes.icd_version, codes.icd_code
    )::integer as diagnosis_key,
    codes.icd_code,
    codes.icd_version,
    codes.long_title as title,
    chapters.chapter_number,
    chapters.chapter
from codes
left join chapters
    on
        codes.icd_version = chapters.icd_version
        and codes.code_prefix between chapters.code_from and chapters.code_to
