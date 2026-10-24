import gzip
from pathlib import Path

import psycopg
import pytest

from loader.load_raw import (
    database_url,
    load_csv,
    load_if_changed,
    source_path,
    table_name,
)

TEST_SCHEMA = "loader_test"


def test_table_name():
    assert table_name(Path("hosp/patients.csv.gz")) == "patients"


def test_source_path():
    assert source_path(Path("data/hosp/patients.csv.gz")) == "hosp/patients.csv.gz"


def write_patients(csv_path: Path, rows: list[str]) -> Path:
    # A tiny synthetic file in the patients layout, so the tests need no
    # real data and run the same in CI.
    with gzip.open(csv_path, "wt", newline="") as f:
        f.write("subject_id,gender,anchor_age,dod\n")
        for row in rows:
            f.write(row + "\n")
    return csv_path


@pytest.fixture
def conn():
    try:
        url = database_url()
    except KeyError:
        pytest.skip("no database configured (DATABASE_URL or POSTGRES_*)")
    with psycopg.connect(url) as conn:
        conn.execute(f"drop schema if exists {TEST_SCHEMA} cascade")
        conn.commit()
        yield conn
        conn.execute(f"drop schema if exists {TEST_SCHEMA} cascade")
        conn.commit()


@pytest.fixture
def patients(tmp_path):
    return write_patients(
        tmp_path / "patients.csv.gz", ["1,F,21,", "2,M,72,2137-09-02"]
    )


def log_rows(conn) -> list[tuple]:
    return conn.execute(
        f"select sha256, row_count from {TEST_SCHEMA}.load_log order by loaded_at"
    ).fetchall()


def test_load_csv(conn, patients):
    assert load_csv(conn, patients, schema=TEST_SCHEMA) == 2
    # Loading again replaces the table instead of appending.
    assert load_csv(conn, patients, schema=TEST_SCHEMA) == 2

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


def test_unchanged_file_is_skipped(conn, patients):
    assert load_if_changed(conn, patients, schema=TEST_SCHEMA) == 2
    assert load_if_changed(conn, patients, schema=TEST_SCHEMA) is None
    assert len(log_rows(conn)) == 1


def test_changed_file_is_reloaded(conn, patients):
    load_if_changed(conn, patients, schema=TEST_SCHEMA)
    write_patients(patients, ["1,F,21,", "2,M,72,2137-09-02", "3,F,50,"])

    assert load_if_changed(conn, patients, schema=TEST_SCHEMA) == 3
    first, second = log_rows(conn)
    assert first[0] != second[0]
    assert second[1] == 3


def test_force_reloads_unchanged_file(conn, patients):
    load_if_changed(conn, patients, schema=TEST_SCHEMA)
    assert load_if_changed(conn, patients, schema=TEST_SCHEMA, force=True) == 2
    assert len(log_rows(conn)) == 2


def test_dropped_table_is_reloaded(conn, patients):
    # The log alone is not enough: if the table is gone, load it again.
    load_if_changed(conn, patients, schema=TEST_SCHEMA)
    conn.execute(f"drop table {TEST_SCHEMA}.patients")
    conn.commit()

    assert load_if_changed(conn, patients, schema=TEST_SCHEMA) == 2
