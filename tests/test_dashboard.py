"""The dashboard's queries read only marts_public, and all of them run.

tests/test_security.py proves that dashboard_ro can read the marts_public
views and nothing else. Together with these tests, that shows the dashboard
needs no access beyond what its role has. The tests run the queries as the
owner: on Neon, dashboard_ro was created in the console, and the owner may
not switch into it.
"""

import os
import re

import psycopg
import pytest

from dashboard import queries
from loader.load_raw import database_url

QUERIES = {
    name: sql
    for name, sql in vars(queries).items()
    if name.isupper() and isinstance(sql, str)
}

# Values for the queries that take parameters.
PARAMS = {
    "LAB_TREND": {
        "label": "Creatinine",
        "fluid": "Blood",
        "care_units": ["Medical Intensive Care Unit (MICU)"],
    },
}


@pytest.fixture(scope="module")
def conn():
    try:
        url = database_url()
    except KeyError:
        pytest.skip("no database configured (DATABASE_URL or POSTGRES_*)")
    with psycopg.connect(url) as conn:
        built = conn.execute("select to_regclass('marts_public.icu_stays')").fetchone()
        if built[0] is None:
            message = "marts_public not built: run dbt build first"
            if os.environ.get("CI"):
                pytest.fail(message)
            pytest.skip(message)
        yield conn


@pytest.mark.parametrize("name", QUERIES)
def test_query_reads_only_marts_public(name):
    # Every table or view after from or join, written schema.name.
    relations = re.findall(r"\b(?:from|join)\s+(\w+)\.(\w+)", QUERIES[name])
    assert relations, f"{name} reads no schema-qualified relation"
    assert {schema for schema, _ in relations} == {"marts_public"}


@pytest.mark.parametrize("name", QUERIES)
def test_query_returns_rows(conn, name):
    try:
        rows = conn.execute(QUERIES[name], PARAMS.get(name)).fetchall()
    finally:
        conn.rollback()
    assert rows
