-- dim_admission has exactly one row without an hadm_id, and it is the -1
-- "outside an admission" row. Returns a row if that is not so.
select
    count(*) as n_without_hadm,
    min(admission_key) as smallest_key
from {{ ref('dim_admission') }}
where hadm_id is null
having count(*) <> 1 or min(admission_key) <> -1
