"""Proof for security/: roles.sql, the row-level security in rls.sql, the
minimization in minimization.sql, the audit trail in audit.sql, and the
pseudonymization in pseudonymize.sql.

The tests apply the security files, then act as each role with
set role, which makes
Postgres check every statement against that role's privileges and policies.
Each check runs in a transaction that is rolled back, so nothing it writes
is kept. The expected rows are computed as the owner, whom RLS does not
limit.
"""

import hashlib
import hmac
import os
import secrets
from pathlib import Path

import psycopg
import pytest
from psycopg import errors, sql

from loader.load_raw import database_url

REPO_DIR = Path(__file__).resolve().parent.parent
SECURITY_DIR = REPO_DIR / "security"
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
        for name in (
            "roles.sql",
            "minimization.sql",
            "audit.sql",
            "pseudonymize.sql",
        ):
            conn.execute((SECURITY_DIR / name).read_text(encoding="utf-8"))
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
        # dim_patient without subject_id: the pseudonymous key and the date
        # of death stay readable, MIMIC's patient ID does not.
        ("analyst_micu", "select subject_key, dod from marts.dim_patient", True),
        ("analyst_micu", "select subject_id from marts.dim_patient", False),
        ("analyst_sicu", "select subject_id from marts.dim_patient", False),
        ("analyst_sicu", "select * from marts.dim_patient", False),
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


# Minimization: what the public dashboard can read ----------------------------

PUBLIC_VIEWS = ["hospital_admissions", "icu_stays", "lab_trends", "patients"]

# Columns that identify a patient or a record, or that the spec keeps out.
FORBIDDEN_COLUMNS = {
    "subject_id",
    "subject_key",
    "patient_key",
    "hadm_id",
    "admission_key",
    "stay_id",
    "labevent_id",
    "dod",
    "anchor_age",
    "anchor_year",
    "insurance",
    "language",
    "race",
    "marital_status",
}


def test_public_views_are_views(conn):
    # Base tables in marts_public would copy data out of the marts; views
    # only show what their query selects.
    relations = conn.execute(
        "select c.relname, c.relkind from pg_class as c"
        " inner join pg_namespace as n on c.relnamespace = n.oid"
        " where n.nspname = 'marts_public' and c.relkind in ('r', 'v', 'm', 'p')"
        " order by c.relname"
    ).fetchall()
    assert relations == [(view, "v") for view in PUBLIC_VIEWS]


@pytest.mark.parametrize("view", PUBLIC_VIEWS)
def test_dashboard_reads_public_view(conn, view):
    granted = conn.execute(
        "select has_table_privilege('dashboard_ro', %s, 'select')",
        (f"marts_public.{view}",),
    ).fetchone()[0]
    assert granted


def test_dashboard_reads_nothing_else(conn):
    # Every table and view in the database the dashboard role could select
    # from, through its own grants or PUBLIC's, outside marts_public.
    readable = conn.execute(
        "select n.nspname || '.' || c.relname from pg_class as c"
        " inner join pg_namespace as n on c.relnamespace = n.oid"
        " where c.relkind in ('r', 'v', 'm', 'p')"
        " and n.nspname not in ('marts_public', 'pg_catalog', 'information_schema')"
        " and has_table_privilege('dashboard_ro', c.oid, 'select')"
    ).fetchall()
    assert readable == []


@pytest.mark.parametrize("schema", ["raw", "staging", "marts", "seeds"])
def test_dashboard_cannot_enter_private_schemas(conn, schema):
    usage = conn.execute(
        "select has_schema_privilege('dashboard_ro', %s, 'usage')", (schema,)
    ).fetchone()[0]
    assert not usage


def test_public_views_hold_no_identifiers_or_dates(conn):
    columns = conn.execute(
        "select table_name, column_name, data_type"
        " from information_schema.columns where table_schema = 'marts_public'"
    ).fetchall()
    assert columns, "marts_public has no columns: run dbt build"
    forbidden = [(t, c) for t, c, _ in columns if c in FORBIDDEN_COLUMNS]
    dated = [(t, c) for t, c, kind in columns if "date" in kind or "time" in kind]
    assert forbidden == []
    assert dated == []


# Audit trail ------------------------------------------------------------------

DIMENSIONS = [
    "dim_admission",
    "dim_care_unit",
    "dim_chart_item",
    "dim_date",
    "dim_diagnosis",
    "dim_lab_item",
    "dim_patient",
    "dim_time",
]


@pytest.mark.parametrize("table", DIMENSIONS)
def test_dimension_has_audit_trigger(conn, table):
    # dbt recreates the table on every build; its post_hook must add the
    # trigger again.
    triggers = conn.execute(
        "select tgname from pg_trigger where tgrelid = %s::regclass"
        " and not tgisinternal",
        (f"marts.{table}",),
    ).fetchall()
    assert triggers == [("audit_changes",)]


def test_changes_by_etl_writer_are_audited(conn):
    # The spec's proof: insert, update and delete a dim_patient row as
    # etl_writer, and three audit rows appear. All in one transaction that
    # is rolled back, so neither the row nor its audit rows are kept.
    try:
        conn.execute("set local role etl_writer")
        conn.execute(
            "insert into marts.dim_patient (patient_key, gender, anchor_age)"
            " values (-999, 'F', 50)"
        )
        conn.execute(
            "update marts.dim_patient set anchor_age = 51 where patient_key = -999"
        )
        conn.execute("delete from marts.dim_patient where patient_key = -999")
        conn.execute("reset role")
        log = conn.execute(
            "select role_name, table_name, change_type,"
            " old_row ->> 'anchor_age', new_row ->> 'anchor_age'"
            " from audit.change_log"
            " where coalesce(new_row, old_row) ->> 'patient_key' = '-999'"
            " order by change_id"
        ).fetchall()
    finally:
        conn.rollback()
    assert log == [
        ("etl_writer", "marts.dim_patient", "INSERT", None, "50"),
        ("etl_writer", "marts.dim_patient", "UPDATE", "50", "51"),
        ("etl_writer", "marts.dim_patient", "DELETE", "51", None),
    ]


@pytest.mark.parametrize(
    ("role", "statement", "expected"),
    [
        # Only the auditor reads the log.
        ("auditor", "select 1 from audit.change_log limit 1", True),
        ("etl_writer", "select 1 from audit.change_log limit 1", False),
        ("analyst_micu", "select 1 from audit.change_log limit 1", False),
        # Nobody but the owner can change what is already logged, not even
        # the role whose changes it records.
        ("etl_writer", "delete from audit.change_log", False),
        ("etl_writer", "update audit.change_log set change_type = 'X'", False),
        ("auditor", "delete from audit.change_log", False),
        # The auditor reads the log and nothing else.
        (
            "auditor",
            "insert into audit.change_log (table_name, change_type) values ('x', 'x')",
            False,
        ),
    ],
)
def test_audit_log_access(conn, role, statement, expected):
    assert allowed(conn, role, statement) is expected


# Pseudonymization -------------------------------------------------------------


def hmac_key() -> str:
    """The real ICU_HMAC_KEY, which these tests need to check subject_key."""
    key = os.environ.get("ICU_HMAC_KEY")
    if not key:
        message = "ICU_HMAC_KEY is not set"
        if os.environ.get("CI"):
            pytest.fail(message)
        pytest.skip(message)
    return key


def test_subject_key_is_hmac_of_subject_id(conn):
    # Recompute every subject_key in Python, independently of the SQL
    # function, from the key outside the database.
    key = hmac_key().encode()
    rows = conn.execute(
        "select subject_id, subject_key from marts.dim_patient"
    ).fetchall()
    conn.rollback()
    assert rows
    for subject_id, subject_key in rows:
        expected = hmac.new(key, str(subject_id).encode(), hashlib.sha256)
        assert subject_key == expected.hexdigest()


def test_pseudonymize_rejects_short_key(conn):
    # A short key could be guessed, which would make the codes reversible.
    try:
        with pytest.raises(errors.RaiseException):
            conn.execute("select privacy.pseudonymize('10014729', 'short')")
    finally:
        conn.rollback()


def run_dbt(*args: str) -> None:
    from dbt.cli.main import dbtRunner

    dbt_dir = str(REPO_DIR / "dbt")
    result = dbtRunner().invoke(
        [*args, "--project-dir", dbt_dir, "--profiles-dir", dbt_dir]
        # Parse afresh, so the key in the environment is the one used.
        + ["--no-partial-parse"]
    )
    assert result.success, result.exception


def patients(conn) -> list[tuple]:
    rows = conn.execute(
        "select patient_key, subject_key, subject_id, gender, anchor_age,"
        " anchor_year, anchor_year_group, dod"
        " from marts.dim_patient order by patient_key"
    ).fetchall()
    # End the transaction, so dbt is not blocked from replacing the table.
    conn.rollback()
    return rows


def test_key_rotation_changes_every_key_and_nothing_else(conn, monkeypatch):
    # The spec's proof: rebuild dim_patient with a new key. The views that
    # read dim_patient are rebuilt too, because replacing a table drops
    # them. Afterwards the real key is put back and the table rebuilt.
    real_key = hmac_key()
    rebuild = ["run", "-s", "dim_patient", "path:models/marts_public"]
    before = patients(conn)
    try:
        monkeypatch.setenv("ICU_HMAC_KEY", secrets.token_hex(32))
        run_dbt(*rebuild)
        rotated = patients(conn)
    finally:
        monkeypatch.setenv("ICU_HMAC_KEY", real_key)
        run_dbt(*rebuild)
    restored = patients(conn)

    def without_key(rows):
        return [row[:1] + row[2:] for row in rows]

    assert len(rotated) == len(before)
    # Every subject_key changed, and the new ones are still all different.
    assert all(new[1] != old[1] for new, old in zip(rotated, before))
    assert len({row[1] for row in rotated}) == len(rotated)
    # Every other column is exactly as it was.
    assert without_key(rotated) == without_key(before)
    # The real key gives back the original codes.
    assert restored == before


def test_dashboard_statements_time_out(conn):
    # A leaked dashboard password must not allow queries that run for long.
    settings = conn.execute(
        "select s.setconfig from pg_db_role_setting as s"
        " inner join pg_roles as r on s.setrole = r.oid"
        " where r.rolname = 'dashboard_ro' and s.setdatabase = 0"
    ).fetchone()
    conn.rollback()
    assert settings is not None
    assert "statement_timeout=15s" in settings[0]
