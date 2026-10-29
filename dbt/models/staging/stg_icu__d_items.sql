-- The ICU item dictionary, one row per itemid. It covers every kind of
-- charted item; dim_chart_item keeps only the 7 vital signs.

with source as (
    select * from {{ source('icu', 'd_items') }}
)

select
    itemid::integer as itemid,
    label,
    abbreviation,
    -- The table the item's values are stored in, e.g. chartevents.
    linksto,
    category,
    unitname,
    param_type
from source
