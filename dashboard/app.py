import psycopg
import streamlit as st

st.title("ICU Data Warehouse")

with psycopg.connect(st.secrets["DATABASE_URL"]) as conn:
    row = conn.execute("select version()").fetchone()

st.write("Connected to:", row[0])
