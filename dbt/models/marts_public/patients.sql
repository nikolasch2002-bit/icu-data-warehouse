-- Public: one row per patient, for patient counts on the Overview page.
--
-- No identifier of any kind, not even the pseudonymous subject_key: the
-- dashboard counts patients but never follows one. Age is a 10-year band,
-- and the date of death is left out.

select
    gender,
    {{ age_band('anchor_age') }} as age_band,
    -- The real 3-year window the patient's shifted dates map to.
    anchor_year_group
from {{ ref('dim_patient') }}
