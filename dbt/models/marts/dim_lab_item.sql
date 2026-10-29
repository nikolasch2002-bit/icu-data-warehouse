-- One row per lab test. The surrogate key is numbered in itemid order, so
-- it is the same on every build as long as the dictionary does not change.

select
    row_number() over (order by itemid)::integer as lab_item_key,
    itemid,
    label,
    fluid,
    category
from {{ ref('stg_hosp__d_labitems') }}
