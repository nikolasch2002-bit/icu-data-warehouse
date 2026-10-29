-- One row per vital-sign item. The item list comes from the staged vital
-- signs, so the 7 itemids are written down in one place only
-- (stg_icu__chartevents).

with vital_items as (
    select distinct itemid
    from {{ ref('stg_icu__chartevents') }}
)

select
    row_number() over (order by d.itemid)::integer as chart_item_key,
    d.itemid,
    -- Temperature is converted to °C at staging, so its MIMIC label
    -- ('Temperature Fahrenheit') and unit would be wrong here.
    case
        when d.itemid = 223761 then 'Temperature'
        else d.label
    end as label,
    case
        when d.itemid = 223761 then '°C'
        else d.unitname
    end as unit
from {{ ref('stg_icu__d_items') }} as d
inner join vital_items on d.itemid = vital_items.itemid
