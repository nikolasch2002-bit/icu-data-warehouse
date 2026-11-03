import altair as alt
import queries
import streamlit as st
from db import run

st.title("Mortality")
st.write(
    "How many patients died in hospital, by ICU unit, by how they were "
    "admitted and by age, and how many came back within 30 days. Every "
    "percentage is shown with the counts behind it: with 100 patients, one "
    "death moves a small group's rate by many points."
)

st.subheader("In-hospital mortality by first ICU care unit")
by_unit = run(queries.MORTALITY_BY_UNIT)
chart = (
    alt.Chart(alt.Data(values=by_unit))
    .mark_bar()
    .encode(
        x=alt.X("hospital_mortality_pct:Q", title="Died in hospital (%)"),
        y=alt.Y("care_unit:N", title=None, sort="-x", axis=alt.Axis(labelLimit=260)),
        tooltip=[
            "care_unit:N",
            "icu_stays:Q",
            "died_in_icu:Q",
            "died_in_hospital:Q",
            "hospital_mortality_pct:Q",
        ],
    )
)
st.altair_chart(chart, use_container_width=True)
st.dataframe(
    by_unit,
    hide_index=True,
    column_config={
        "care_unit": "First care unit",
        "icu_stays": "ICU stays",
        "died_in_icu": "Died in the ICU",
        "died_in_hospital": "Died in hospital",
        "hospital_mortality_pct": "Died in hospital (%)",
    },
)

left, right = st.columns(2)

with left:
    st.subheader("By admission type")
    st.dataframe(
        run(queries.MORTALITY_BY_ADMISSION_TYPE),
        hide_index=True,
        column_config={
            "admission_type": "Admission type",
            "admissions": "Admissions",
            "deaths": "Deaths",
            "mortality_pct": "Mortality (%)",
        },
    )

with right:
    st.subheader("By age band at admission")
    by_age = run(queries.MORTALITY_BY_AGE)
    chart = (
        alt.Chart(alt.Data(values=by_age))
        .mark_bar()
        .encode(
            x=alt.X("age_band:O", title="Age band"),
            y=alt.Y("mortality_pct:Q", title="Mortality (%)"),
            tooltip=["age_band:O", "admissions:Q", "deaths:Q", "mortality_pct:Q"],
        )
    )
    st.altair_chart(chart, use_container_width=True)

st.subheader("30-day readmission")
readmission = run(queries.READMISSION)[0]
st.metric(
    "Readmitted within 30 days",
    f"{readmission['readmission_pct']:.1f}%",
    help="Of admissions discharged alive; a patient who died cannot be readmitted.",
)
st.caption(
    f"{readmission['readmitted']} of {readmission['discharged_alive']} "
    "admissions discharged alive were followed by another admission of the "
    "same patient within 30 days."
)
