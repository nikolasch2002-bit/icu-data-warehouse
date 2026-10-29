-- The lab test dictionary, one row per itemid.

with source as (
    select * from {{ source('hosp', 'd_labitems') }}
)

select
    itemid::integer as itemid,
    label,
    -- The sample the test is run on, e.g. Blood or Urine.
    fluid,
    -- The lab section, e.g. Chemistry or Hematology.
    category
from source
