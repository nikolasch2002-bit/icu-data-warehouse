-- One row per ICU care unit that an ICU stay starts or ends in, with the
-- hand-curated type from seeds/care_unit_types.csv (decided in
-- docs/data-model.md). A unit missing from the seed gets a null type,
-- which the not_null test turns into a failed build.

with units as (
    select first_careunit as care_unit from {{ ref('stg_icu__icustays') }}
    union
    select last_careunit from {{ ref('stg_icu__icustays') }}
)

select
    row_number() over (order by units.care_unit)::integer as care_unit_key,
    units.care_unit,
    unit_types.care_unit_type
from units
left join {{ ref('care_unit_types') }} as unit_types
    on units.care_unit = unit_types.care_unit
