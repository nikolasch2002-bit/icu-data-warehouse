"""Every SQL query the dashboard runs, in one place.

The dashboard connects as dashboard_ro, which can read only the marts_public
views, so every query here reads only those. tests/test_dashboard.py runs
each one as dashboard_ro to prove it. The SQL does the counting and the
percentiles; the pages only draw the results.
"""

# Overview ----------------------------------------------------------------------

HEADLINE = """
select
    (select count(*) from marts_public.patients) as patients,
    (select count(*) from marts_public.hospital_admissions) as admissions,
    (select count(*) from marts_public.icu_stays) as icu_stays,
    (
        select count(*) from marts_public.hospital_admissions
        where died_in_hospital
    ) as in_hospital_deaths
"""

STAYS_BY_UNIT = """
select
    first_care_unit as care_unit,
    first_care_unit_type as care_unit_type,
    count(*) as icu_stays
from marts_public.icu_stays
group by first_care_unit, first_care_unit_type
order by icu_stays desc, care_unit asc
"""

PATIENTS_BY_AGE = """
select
    age_band,
    gender,
    count(*) as patients
from marts_public.patients
group by age_band, gender
order by age_band asc, gender asc
"""

ADMISSIONS_BY_YEAR_GROUP = """
select
    anchor_year_group,
    count(*) as admissions,
    count(*) filter (where had_icu_stay) as with_icu_stay
from marts_public.hospital_admissions
group by anchor_year_group
order by anchor_year_group asc
"""

# Length of stay ----------------------------------------------------------------

# One row per stay, for the box plot: the plot computes its own quartiles.
ICU_STAY_LENGTHS = """
select
    first_care_unit as care_unit,
    icu_los_days
from marts_public.icu_stays
"""

ICU_LOS_SUMMARY = """
select
    first_care_unit as care_unit,
    count(*) as icu_stays,
    percentile_cont(0.5) within group (order by icu_los_days) as median_days,
    percentile_cont(0.25) within group (order by icu_los_days) as q1_days,
    percentile_cont(0.75) within group (order by icu_los_days) as q3_days,
    max(icu_los_days) as longest_days
from marts_public.icu_stays
group by first_care_unit
order by icu_stays desc, care_unit asc
"""

HOSPITAL_LOS_BY_ICU = """
select
    case when had_icu_stay then 'ICU stay' else 'No ICU stay' end as icu,
    count(*) as admissions,
    percentile_cont(0.5) within group (order by los_days) as median_days,
    percentile_cont(0.25) within group (order by los_days) as q1_days,
    percentile_cont(0.75) within group (order by los_days) as q3_days
from marts_public.hospital_admissions
group by had_icu_stay
order by icu asc
"""

# Mortality ---------------------------------------------------------------------

MORTALITY_BY_UNIT = """
select
    first_care_unit as care_unit,
    count(*) as icu_stays,
    count(*) filter (where died_in_icu) as died_in_icu,
    count(*) filter (where died_in_hospital) as died_in_hospital,
    round(100.0 * count(*) filter (where died_in_hospital) / count(*), 1)
        as hospital_mortality_pct
from marts_public.icu_stays
group by first_care_unit
order by icu_stays desc, care_unit asc
"""

MORTALITY_BY_ADMISSION_TYPE = """
select
    admission_type,
    count(*) as admissions,
    count(*) filter (where died_in_hospital) as deaths,
    round(100.0 * count(*) filter (where died_in_hospital) / count(*), 1)
        as mortality_pct
from marts_public.hospital_admissions
group by admission_type
order by admissions desc, admission_type asc
"""

MORTALITY_BY_AGE = """
select
    age_band,
    count(*) as admissions,
    count(*) filter (where died_in_hospital) as deaths,
    round(100.0 * count(*) filter (where died_in_hospital) / count(*), 1)
        as mortality_pct
from marts_public.hospital_admissions
group by age_band
order by age_band asc
"""

# The flag is null for in-hospital deaths, who cannot be readmitted, so
# count() of it counts only the admissions discharged alive.
READMISSION = """
select
    count(readmitted_within_30_days) as discharged_alive,
    count(*) filter (where readmitted_within_30_days) as readmitted,
    round(
        100.0 * count(*) filter (where readmitted_within_30_days)
        / count(readmitted_within_30_days),
        1
    ) as readmission_pct
from marts_public.hospital_admissions
"""

# Lab trends --------------------------------------------------------------------

# Tests with enough results to draw a trend, most measured first.
LAB_TESTS = """
select
    label,
    fluid,
    unit,
    sum(results) as results
from marts_public.lab_trends
group by label, fluid, unit
having sum(results) >= 100
order by results desc, label asc
"""

LAB_CARE_UNITS = """
select distinct first_care_unit as care_unit
from marts_public.lab_trends
order by care_unit asc
"""

# The quartiles per ICU day of one test, for the chosen units. The first two
# weeks: later days hold too few stays to say much.
LAB_TREND = """
select
    first_care_unit as care_unit,
    icu_day,
    results,
    q1_value,
    median_value,
    q3_value
from marts_public.lab_trends
where
    label = %(label)s
    and fluid = %(fluid)s
    and first_care_unit = any(%(care_units)s)
    and icu_day <= 13
order by care_unit asc, icu_day asc
"""
