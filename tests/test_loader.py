import gzip
from pathlib import Path

import psycopg
import pytest

from loader.load_raw import database_url, load_csv, table_name

TEST_SCHEMA = "loader_test"


def test_table_name():
    assert table_name(Path("hosp/patients.csv.gz")) == "patients"


@pytest.fixture
def conn():
    try:
        url = database_url()
    except KeyError:
        pytest.skip("no database configured (DATABASE_URL or POSTGRES_*)")
    with psycopg.connect(url) as conn:
        yield conn
        conn.execute(f"drop schema if exists {TEST_SCHEMA} cascade")
        conn.commit()


def test_load_csv(conn, tmp_path):
    # A tiny synthetic file in the patients layout, so the test needs no
    # real data and runs the same in CI.
    csv_path = tmp_path / "patients.csv.gz"
    with gzip.open(csv_path, "wt", newline="") as f:
        f.write("subject_id,gender,anchor_age,dod\n")
        f.write("1,F,21,\n")
        f.write("2,M,72,2137-09-02\n")

    assert load_csv(conn, csv_path, schema=TEST_SCHEMA) == 2
    # Loading again replaces the table instead of appending.
    assert load_csv(conn, csv_path, schema=TEST_SCHEMA) == 2

    rows = conn.execute(
        f"select subject_id, dod from {TEST_SCHEMA}.patients order by subject_id"
    ).fetchall()
    assert rows == [("1", None), ("2", "2137-09-02")]

    types = conn.execute(
        "select distinct data_type from information_schema.columns"
        " where table_schema = %s and table_name = 'patients'",
        (TEST_SCHEMA,),
    ).fetchall()
    assert types == [("text",)]
