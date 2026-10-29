-- The grain of fact_diagnosis: one row per admission and diagnosis.
-- Returns any pair that appears more than once.
select
    admission_key,
    diagnosis_key,
    count(*) as n_rows
from {{ ref('fact_diagnosis') }}
group by admission_key, diagnosis_key
having count(*) > 1
