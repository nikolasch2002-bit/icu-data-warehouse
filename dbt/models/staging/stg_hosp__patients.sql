-- One row per patient. Casts the raw text columns to their real types;
-- names stay as in MIMIC so they can be checked against its documentation.

with source as (
    select * from {{ source('hosp', 'patients') }}
)

select
    subject_id::integer as subject_id,
    gender,
    -- Age in anchor_year. MIMIC caps it at 91 for patients over 89.
    anchor_age::integer as anchor_age,
    -- The shifted year (2100-2200) that anchor_age refers to.
    anchor_year::integer as anchor_year,
    -- The real 3-year window that anchor_year maps to, e.g. '2011 - 2013'.
    anchor_year_group,
    -- Date of death, shifted like every MIMIC date. Null if not known to
    -- have died.
    dod::date as dod
from source
