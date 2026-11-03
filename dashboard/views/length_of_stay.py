import altair as alt
import queries
import streamlit as st
from db import run

st.title("Length of stay")
st.write(
    "How long patients stay in the ICU, by the unit where the stay began. "
    "A few very long stays pull the average up, so the median and the "
    "interquartile range (the middle half of stays) describe a typical "
    "stay better."
)

st.subheader("ICU length of stay by first care unit")
lengths = run(queries.ICU_STAY_LENGTHS)
chart = (
    alt.Chart(alt.Data(values=lengths))
    .mark_boxplot(extent="min-max", rule={"color": "#9a9a9a"})
    .encode(
        x=alt.X("icu_los_days:Q", title="ICU length of stay (days)"),
        y=alt.Y("care_unit:N", title=None, axis=alt.Axis(labelLimit=260)),
    )
)
st.altair_chart(chart, use_container_width=True)
st.caption(
    "The box is the middle half of stays, the line in it the median, the "
    "whiskers the shortest and longest stay."
)

st.dataframe(
    run(queries.ICU_LOS_SUMMARY),
    hide_index=True,
    column_config={
        "care_unit": "First care unit",
        "icu_stays": "ICU stays",
        "median_days": st.column_config.NumberColumn("Median (days)", format="%.1f"),
        "q1_days": st.column_config.NumberColumn("Q1 (days)", format="%.1f"),
        "q3_days": st.column_config.NumberColumn("Q3 (days)", format="%.1f"),
        "longest_days": st.column_config.NumberColumn("Longest (days)", format="%.1f"),
    },
)
st.caption("Units with only a handful of stays are shown but should not be compared.")

st.subheader("Hospital length of stay, with and without an ICU stay")
st.dataframe(
    run(queries.HOSPITAL_LOS_BY_ICU),
    hide_index=True,
    column_config={
        "icu": "Admission",
        "admissions": "Admissions",
        "median_days": st.column_config.NumberColumn("Median (days)", format="%.1f"),
        "q1_days": st.column_config.NumberColumn("Q1 (days)", format="%.1f"),
        "q3_days": st.column_config.NumberColumn("Q3 (days)", format="%.1f"),
    },
)
