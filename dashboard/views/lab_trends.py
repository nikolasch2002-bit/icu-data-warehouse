import altair as alt
import queries
import streamlit as st
from db import run

st.title("Lab trends")
st.write(
    "How a lab test typically moves over the first two weeks of an ICU "
    "stay. Each point summarizes every result of that test on that day of "
    "the stay: the line is the median, the band the middle half of results. "
    "No single patient's values are published."
)

tests = run(queries.LAB_TESTS)
names = [f"{t['label']} ({t['fluid']}, {t['unit']})" for t in tests]
default = next(
    (
        i
        for i, t in enumerate(tests)
        if (t["label"], t["fluid"]) == ("Creatinine", "Blood")
    ),
    0,
)
choice = st.selectbox(
    "Lab test", range(len(tests)), index=default, format_func=names.__getitem__
)
test = tests[choice]

units = [row["care_unit"] for row in run(queries.LAB_CARE_UNITS)]
care_units = st.multiselect(
    "First care unit",
    units,
    default=[u for u in units if "(MICU)" in u or "(SICU)" in u] or units[:2],
)

if not care_units:
    st.info("Choose at least one care unit.")
    st.stop()

trend = run(
    queries.LAB_TREND,
    {"label": test["label"], "fluid": test["fluid"], "care_units": care_units},
)
if not trend:
    st.info("No results for this test in the chosen units.")
    st.stop()

base = alt.Chart(alt.Data(values=trend)).encode(
    x=alt.X("icu_day:O", title="Day of ICU stay (0 = first 24 hours)"),
)
# Only the line draws the legend; the faint band would make its symbols dark.
band = base.mark_area(opacity=0.2).encode(
    color=alt.Color("care_unit:N", legend=None),
    y=alt.Y("q1_value:Q", title=f"{test['label']} ({test['unit']})"),
    y2="q3_value:Q",
)
line = base.mark_line(point=True).encode(
    y="median_value:Q",
    color=alt.Color(
        "care_unit:N",
        title="First care unit",
        legend=alt.Legend(orient="bottom", columns=1, labelLimit=400),
    ),
    tooltip=[
        "care_unit:N",
        "icu_day:O",
        "results:Q",
        "median_value:Q",
        "q1_value:Q",
        "q3_value:Q",
    ],
)
st.altair_chart(band + line, use_container_width=True)
st.caption(
    "Later days hold fewer patients, so their medians rest on few results: "
    "hover over a point to see how many."
)
