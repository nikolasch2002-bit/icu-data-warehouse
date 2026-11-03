import altair as alt
import queries
import streamlit as st
from db import run

st.title("ICU Data Warehouse")
st.write(
    "Who is in the data: the 100 patients of the MIMIC-IV demo, their "
    "hospital admissions, and the ICU stays within them."
)

headline = run(queries.HEADLINE)[0]
columns = st.columns(4)
columns[0].metric("Patients", headline["patients"])
columns[1].metric("Hospital admissions", headline["admissions"])
columns[2].metric("ICU stays", headline["icu_stays"])
columns[3].metric("In-hospital deaths", headline["in_hospital_deaths"])

left, right = st.columns(2)

with left:
    st.subheader("ICU stays by first care unit")
    stays = run(queries.STAYS_BY_UNIT)
    chart = (
        alt.Chart(alt.Data(values=stays))
        .mark_bar()
        .encode(
            x=alt.X("icu_stays:Q", title="ICU stays"),
            y=alt.Y(
                "care_unit:N", title=None, sort="-x", axis=alt.Axis(labelLimit=260)
            ),
            color=alt.Color(
                "care_unit_type:N",
                title="Unit type",
                legend=alt.Legend(orient="bottom", columns=3),
            ),
            tooltip=["care_unit:N", "care_unit_type:N", "icu_stays:Q"],
        )
    )
    st.altair_chart(chart, use_container_width=True)

with right:
    st.subheader("Patients by age band")
    patients = run(queries.PATIENTS_BY_AGE)
    chart = (
        alt.Chart(alt.Data(values=patients))
        .mark_bar()
        .encode(
            x=alt.X("age_band:O", title="Age band"),
            y=alt.Y("patients:Q", title="Patients", stack=True),
            color=alt.Color(
                "gender:N", title="Gender", legend=alt.Legend(orient="bottom")
            ),
            tooltip=["age_band:O", "gender:N", "patients:Q"],
        )
    )
    st.altair_chart(chart, use_container_width=True)
    st.caption("Age in the patient's anchor year; MIMIC records ages over 89 as 90+.")

st.subheader("Admissions by year group")
st.caption(
    "MIMIC shifts every date into the future to protect privacy; the year "
    "group is the real three-year window an admission falls in."
)
st.dataframe(
    run(queries.ADMISSIONS_BY_YEAR_GROUP),
    hide_index=True,
    column_config={
        "anchor_year_group": "Year group",
        "admissions": "Admissions",
        "with_icu_stay": "With an ICU stay",
    },
)
