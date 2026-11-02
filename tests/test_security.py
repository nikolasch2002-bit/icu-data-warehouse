"""Proof for security/roles.sql and the row-level security in rls.sql.

The tests apply roles.sql, then act as each role with set role, which makes
Postgres check every statement against that role's privileges and policies.
Each check runs in a transaction that is rolled back, so nothing it writes
is kept. The expected rows are computed as the owner, whom RLS does not
limit.
"""

import os
from pathlib import Path

import psycopg
import pytest
from psycopg import errors, sql

from loader.load_raw import database_url

ROLES_SQL = Path(__file__).resolve().parent.parent / "security" / "roles.sql"
ROLES = ["etl_writer", "analyst_micu", "analyst_sicu", "auditor"]


@pytest.fixture(scope="module")
def conn():
    try:
        url = database_url()
    except KeyError:
        pytest.skip("no database configured (DATABASE_URL or POSTGRES_*)")
    with psycopg.connect(url) as conn:
        built = conn.execute("select to_regclass('marts.fact_icu_stay')").fetchone()
        if built[0] is None:
            # CI runs dbt build before the tests, so a missing marts schema
            # there is a broken pipeline, not a reason to skip.
            message = "marts not built: run dbt build first"
            if os.environ.get("CI"):
                pytest.fail(message)
            pytest.skip(message)
        conn.execute(ROLES_SQL.read_text(encoding="utf-8"))
        conn.commit()
        yield conn


def allowed(conn, role: str, statement: str) -> bool:
    """Whether role may run statement. Nothing it does is kept."""
    try:
        # set local lasts until the end of the transaction.
        conn.execute(sql.SQL("set local role {}").format(sql.Identifier(role)))
        conn.execute(statement)
        return True
    except errors.InsufficientPrivilege:
        return False
    finally:
        conn.rollback()


@pytest.mark.parametrize("role", ROLES)
def test_role_has_no_special_powers(conn, role):
    attributes = conn.execute(
        "select rolcanlogin, rolsuper, rolcreatedb, rolcreaterole, rolbypassrls"
        " from pg_roles where rolname = %s",
        (role,),
    ).fetchone()
    assert attributes == (False, False, False, False, False)


@pytest.mark.parametrize(
    ("schema", "role", "privilege"),
    [
        ("raw", "etl_writer", "delete"),
        ("staging", "etl_writer", "select"),
        ("marts", "etl_writer", "delete"),
        ("marts", "analyst_micu", "select"),
        ("marts", "analyst_sicu", "select"),
    ],
)
def test_new_tables_get_the_grants(conn, schema, role, privilege):
    # The loader and dbt recreate their tables on every run. A table created
    # after roles.sql ran must get the same grants with no further step.
    table = f"{schema}.default_privileges_probe"
    try:
        conn.execute(
            sql.SQL("create table {}.default_privileges_probe (x integer)").format(
                sql.Identifier(schema)
            )
        )
        granted = conn.execute(
            "select has_table_privilege(%s, %s, %s)", (role, table, privilege)
        ).fetchone()[0]
    finally:
        conn.rollback()
    assert granted


@pytest.mark.parametrize(
    ("role", "statement", "expected"),
    [
        # etl_writer: the pipeline, writes every layer it builds.
        ("etl_writer", "select 1 from raw.patients limit 1", True),
        ("etl_writer", "delete from raw.patients", True),
        ("etl_writer", "create table raw.probe (x integer)", True),
        ("etl_writer", "select 1 from staging.stg_hosp__patients limit 1", True),
        ("etl_writer", "create view staging.probe as select 1 as x", True),
        ("etl_writer", "delete from marts.dim_patient", True),
        ("etl_writer", "create table marts.probe (x integer)", True),
        # Analysts: read marts, cannot change it, never see raw or staging.
        ("analyst_micu", "select 1 from marts.fact_icu_stay limit 1", True),
        ("analyst_micu", "select 1 from marts.dim_patient limit 1", True),
        ("analyst_micu", "delete from marts.dim_patient", False),
        ("analyst_micu", "create table marts.probe (x integer)", False),
        ("analyst_micu", "select 1 from raw.patients limit 1", False),
        ("analyst_micu", "select 1 from staging.stg_hosp__patients limit 1", False),
        ("analyst_sicu", "select 1 from marts.fact_icu_stay limit 1", True),
        ("analyst_sicu", "delete from marts.dim_patient", False),
        ("analyst_sicu", "select 1 from raw.patients limit 1", False),
        # auditor: nothing until audit.sql grants it the audit table.
        ("auditor", "select 1 from marts.dim_patient limit 1", False),
        ("auditor", "select 1 from staging.stg_hosp__patients limit 1", False),
        ("auditor", "select 1 from raw.patients limit 1", False),
    ],
)
def test_role_privileges(conn, role, statement, expected):
    assert allowed(conn, role, statement) is expected


# Row-level security ---------------------------------------------------------

ANALYST_CARE_UNITS = {
    "analyst_micu": "Medical Intensive Care Unit (MICU)",
    "analyst_sicu": "Surgical Intensive Care Unit (SICU)",
}
RLS_TABLES = ["fact_icu_stay", "fact_vital_sign", "fact_lab_result"]

# The stays of one care unit: those that began or ended there.
UNIT_STAYS = """
    select s.stay_id, s.admission_key
    from marts.fact_icu_stay as s
    inner join marts.dim_care_unit as cu
        on cu.care_unit_key in (s.first_care_unit_key, s.last_care_unit_key)
    where cu.care_unit = %(care_unit)s
"""


def as_role(conn, role: str, query: str) -> list[tuple]:
    """The rows query returns when role runs it."""
    try:
        conn.execute(sql.SQL("set local role {}").format(sql.Identifier(role)))
        return conn.execute(query).fetchall()
    finally:
        conn.rollback()


def as_owner(conn, query: str, care_unit: str) -> list[tuple]:
    try:
        return conn.execute(query, {"care_unit": care_unit}).fetchall()
    finally:
        conn.rollback()


@pytest.mark.parametrize("table", RLS_TABLES)
def test_rls_is_enabled(conn, table):
    # dbt recreates the table on every build; its post_hook must enable RLS.
    enabled = conn.execute(
        "select relrowsecurity from pg_class where oid = %s::regclass",
        (f"marts.{table}",),
    ).fetchone()[0]
    assert enabled


@pytest.mark.parametrize(("role", "care_unit"), ANALYST_CARE_UNITS.items())
def test_analyst_sees_only_own_stays(conn, role, care_unit):
    expected = as_owner(conn, f"select stay_id from ({UNIT_STAYS}) as u", care_unit)
    visible = as_role(conn, role, "select stay_id from marts.fact_icu_stay")
    assert expected, f"no {care_unit} stays to test with"
    assert sorted(visible) == sorted(expected)


@pytest.mark.parametrize(("role", "care_unit"), ANALYST_CARE_UNITS.items())
def test_analyst_sees_only_own_vitals(conn, role, care_unit):
    expected = as_owner(
        conn,
        f"select count(*) from marts.fact_vital_sign"
        f" where stay_id in (select stay_id from ({UNIT_STAYS}) as u)",
        care_unit,
    )
    visible = as_role(conn, role, "select count(*) from marts.fact_vital_sign")
    assert visible == expected


@pytest.mark.parametrize(("role", "care_unit"), ANALYST_CARE_UNITS.items())
def test_analyst_sees_labs_of_own_admissions(conn, role, care_unit):
    expected = as_owner(
        conn,
        f"select count(*) from marts.fact_lab_result"
        f" where admission_key in (select admission_key from ({UNIT_STAYS}) as u)",
        care_unit,
    )
    visible = as_role(conn, role, "select count(*) from marts.fact_lab_result")
    assert visible == expected


def test_analysts_see_different_stays(conn):
    micu, sicu = (
        set(as_role(conn, role, "select stay_id from marts.fact_icu_stay"))
        for role in ANALYST_CARE_UNITS
    )
    # Not the same rows, and neither sees everything.
    total = conn.execute("select count(*) from marts.fact_icu_stay").fetchone()[0]
    assert micu != sicu
    assert len(micu) < total and len(sicu) < total


@pytest.mark.parametrize("table", RLS_TABLES)
def test_etl_writer_sees_every_row(conn, table):
    total = conn.execute(f"select count(*) from marts.{table}").fetchone()
    assert as_role(conn, "etl_writer", f"select count(*) from marts.{table}") == [total]
