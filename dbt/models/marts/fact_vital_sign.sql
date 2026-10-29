-- Grain: one row per charted vital sign (the 7 items kept at staging).

select
    -- Degenerate dimension: links the value to its row in fact_icu_stay.
    vitals.stay_id,
    dim_patient.patient_key,
    dim_chart_item.chart_item_key,
    to_char(vitals.charttime, 'YYYYMMDD')::integer as date_key,
    extract(hour from vitals.charttime)::integer as time_key,
    -- Already in the unit of dim_chart_item (temperature in °C).
    vitals.valuenum
from {{ ref('stg_icu__chartevents') }} as vitals
inner join {{ ref('dim_patient') }} as dim_patient
    on vitals.subject_id = dim_patient.subject_id
inner join {{ ref('dim_chart_item') }} as dim_chart_item
    on vitals.itemid = dim_chart_item.itemid
