-- Vital signs only: raw.chartevents filtered to the 7 items chosen in
-- docs/data-model.md, one row per charted value. Temperature is charted in
-- °F and converted to °C here, so every downstream model sees one unit.

with source as (
    select * from {{ source('icu', 'chartevents') }}
),

vitals as (
    select
        stay_id::integer as stay_id,
        hadm_id::integer as hadm_id,
        subject_id::integer as subject_id,
        caregiver_id::integer as caregiver_id,
        charttime::timestamp as charttime,
        storetime::timestamp as storetime,
        itemid::integer as itemid,
        valuenum::numeric as valuenum,
        valueuom,
        -- Set by the bedside system when a value was outside its alarm limits.
        warning::boolean as warning
    from source
    where itemid in (
        '220045',  -- Heart Rate
        '220210',  -- Respiratory Rate
        '220277',  -- O2 saturation pulseoxymetry
        '220179',  -- Non Invasive Blood Pressure systolic
        '220180',  -- Non Invasive Blood Pressure diastolic
        '220181',  -- Non Invasive Blood Pressure mean
        '223761'   -- Temperature Fahrenheit
    )
)

select
    stay_id,
    hadm_id,
    subject_id,
    caregiver_id,
    charttime,
    storetime,
    itemid,
    warning,
    case
        when itemid = 223761 then round((valuenum - 32) * 5 / 9, 1)
        else valuenum
    end as valuenum,
    case
        when itemid = 223761 then '°C'
        else valueuom
    end as valueuom
from vitals
