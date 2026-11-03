"""ICU Data Warehouse dashboard: four pages over the marts_public views.

Run locally with: uv run streamlit run dashboard/app.py
"""

import streamlit as st

st.set_page_config(page_title="ICU Data Warehouse", layout="wide")

# The pages are in views/, not pages/: Streamlit would turn a pages/ folder
# into a second, automatic menu next to this one.
page = st.navigation(
    [
        st.Page("views/overview.py", title="Overview", icon=":material/dashboard:"),
        st.Page(
            "views/length_of_stay.py",
            title="Length of stay",
            icon=":material/schedule:",
        ),
        st.Page("views/mortality.py", title="Mortality", icon=":material/monitoring:"),
        st.Page("views/lab_trends.py", title="Lab trends", icon=":material/science:"),
    ]
)
page.run()

st.divider()
# The citations are a condition of using the data (ODbL, PhysioNet).
st.caption(
    "Data: Johnson et al. (2023), MIMIC-IV Clinical Database Demo v2.2, "
    "PhysioNet, DOI [10.13026/dp1f-ex47](https://doi.org/10.13026/dp1f-ex47), "
    "under the Open Database License (ODbL). "
    "Pollard et al. (2026), PhysioNet, Nature Health, "
    "DOI [10.1038/s44360-026-00096-z](https://doi.org/10.1038/s44360-026-00096-z). "
    "100 de-identified patients with shifted dates; small numbers, "
    "so percentages move a lot with one patient."
)
