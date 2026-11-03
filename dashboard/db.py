"""The dashboard's database access: one connection, cached query results."""

from decimal import Decimal

import psycopg
import streamlit as st
from psycopg.rows import dict_row


@st.cache_resource
def _connection() -> psycopg.Connection:
    # DATABASE_URL in .streamlit/secrets.toml (or the app's secrets on
    # Streamlit Cloud) is dashboard_ro's connection to Neon main.
    return psycopg.connect(
        st.secrets["DATABASE_URL"], autocommit=True, row_factory=dict_row
    )


def _execute(sql: str, params: dict | None) -> list[dict]:
    return _connection().execute(sql, params).fetchall()


# The data changes only when the warehouse is rebuilt, so results are kept
# for an hour instead of querying Neon on every click.
@st.cache_data(ttl=3600, show_spinner=False)
def run(sql: str, params: dict | None = None) -> list[dict]:
    """The rows of a query from queries.py, as dicts."""
    try:
        rows = _execute(sql, params)
    except psycopg.OperationalError:
        # Neon closes idle connections; reconnect once and retry.
        _connection.clear()
        rows = _execute(sql, params)
    # Charts need plain numbers; Postgres numeric arrives as Decimal.
    return [
        {k: float(v) if isinstance(v, Decimal) else v for k, v in row.items()}
        for row in rows
    ]
