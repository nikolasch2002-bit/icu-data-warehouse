"""Load MIMIC-IV demo CSVs verbatim into the raw schema.

Every column is loaded as text. Typing and renaming happen in dbt staging,
so raw stays a faithful copy of the source file.

Each successful load appends a row to raw.load_log with the file's SHA-256.
A file whose SHA-256 matches its last load is skipped. The hashes use the
same paths as PhysioNet's SHA256SUMS.txt, so the two can be compared.

Usage:
    python -m loader.load_raw                        # every file under hosp/ and icu/
    python -m loader.load_raw hosp/patients.csv.gz   # just these files
    python -m loader.load_raw --force                # reload even if unchanged
"""

import argparse
import csv
import gzip
import hashlib
import os
from pathlib import Path

import psycopg
from psycopg import sql
from psycopg.conninfo import make_conninfo

DATA_DIR = Path(__file__).resolve().parent.parent / "data" / "mimic-iv-demo"
MODULES = ("hosp", "icu")
CHUNK_SIZE = 1024 * 1024


def database_url() -> str:
    """DATABASE_URL if set, otherwise the local Docker database from POSTGRES_*."""
    if url := os.environ.get("DATABASE_URL"):
        return url
    # 127.0.0.1, not localhost: Docker only listens on IPv4, and localhost on
    # Windows tries IPv6 first and waits for it to time out.
    return make_conninfo(
        host="127.0.0.1",
        port=5432,
        user=os.environ["POSTGRES_USER"],
        password=os.environ["POSTGRES_PASSWORD"],
        dbname=os.environ["POSTGRES_DB"],
    )


def table_name(csv_path: Path) -> str:
    """hosp/patients.csv.gz -> patients."""
    return csv_path.name.removesuffix(".csv.gz")


def source_path(csv_path: Path) -> str:
    """The module/file form PhysioNet uses, e.g. hosp/patients.csv.gz."""
    return f"{csv_path.parent.name}/{csv_path.name}"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(CHUNK_SIZE):
            digest.update(chunk)
    return digest.hexdigest()


def read_header(csv_path: Path) -> list[str]:
    with gzip.open(csv_path, "rt", newline="", encoding="utf-8") as f:
        return next(csv.reader(f))


def ensure_load_log(conn: psycopg.Connection, schema: str) -> None:
    # Append-only: one row per successful load, so the history is kept.
    conn.execute(
        sql.SQL(
            """
            create table if not exists {} (
                source_path text not null,
                sha256 text not null,
                row_count bigint not null,
                loaded_at timestamptz not null default now()
            )
            """
        ).format(sql.Identifier(schema, "load_log"))
    )


def last_sha256(conn: psycopg.Connection, csv_path: Path, schema: str) -> str | None:
    """SHA-256 of the file's latest load, or None if its table is missing."""
    table = f"{schema}.{table_name(csv_path)}"
    row = conn.execute(
        sql.SQL(
            """
            select sha256 from {}
            where source_path = %s and to_regclass(%s) is not null
            order by loaded_at desc
            limit 1
            """
        ).format(sql.Identifier(schema, "load_log")),
        (source_path(csv_path), table),
    ).fetchone()
    return row[0] if row else None


def load_csv(conn: psycopg.Connection, csv_path: Path, schema: str = "raw") -> int:
    """Replace schema.<table> with the contents of csv_path; return the row count.

    Drop, create and COPY run in one transaction, so a failed load leaves the
    previous table in place.
    """
    target = sql.Identifier(schema, table_name(csv_path))
    columns = sql.SQL(", ").join(
        sql.SQL("{} text").format(sql.Identifier(c)) for c in read_header(csv_path)
    )
    with conn.transaction():
        conn.execute(
            sql.SQL("create schema if not exists {}").format(sql.Identifier(schema))
        )
        conn.execute(sql.SQL("drop table if exists {}").format(target))
        conn.execute(sql.SQL("create table {} ({})").format(target, columns))
        # In CSV format an unquoted empty field becomes NULL, e.g. dod for
        # patients who did not die.
        copy_sql = sql.SQL("copy {} from stdin with (format csv, header true)")
        with conn.cursor() as cur:
            with (
                cur.copy(copy_sql.format(target)) as copy,
                gzip.open(csv_path, "rb") as f,
            ):
                while chunk := f.read(CHUNK_SIZE):
                    copy.write(chunk)
            cur.execute(sql.SQL("select count(*) from {}").format(target))
            return cur.fetchone()[0]


def load_if_changed(
    conn: psycopg.Connection,
    csv_path: Path,
    schema: str = "raw",
    force: bool = False,
) -> int | None:
    """Load csv_path unless its SHA-256 matches the last load.

    Returns the row count, or None if the file was skipped. The table and its
    load_log row are written in one transaction, so the log never claims a
    load that did not happen.
    """
    digest = sha256(csv_path)
    with conn.transaction():
        conn.execute(
            sql.SQL("create schema if not exists {}").format(sql.Identifier(schema))
        )
        ensure_load_log(conn, schema)
        if not force and last_sha256(conn, csv_path, schema) == digest:
            return None
        rows = load_csv(conn, csv_path, schema)
        conn.execute(
            sql.SQL(
                "insert into {} (source_path, sha256, row_count) values (%s, %s, %s)"
            ).format(sql.Identifier(schema, "load_log")),
            (source_path(csv_path), digest, rows),
        )
        return rows


def all_files() -> list[Path]:
    return sorted(p for m in MODULES for p in (DATA_DIR / m).glob("*.csv.gz"))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "files",
        nargs="*",
        help="paths relative to data/mimic-iv-demo (default: every file)",
    )
    parser.add_argument(
        "--force", action="store_true", help="reload files even if unchanged"
    )
    args = parser.parse_args()
    paths = [DATA_DIR / f for f in args.files] or all_files()

    with psycopg.connect(database_url()) as conn:
        for csv_path in paths:
            rows = load_if_changed(conn, csv_path, force=args.force)
            status = "unchanged, skipped" if rows is None else f"{rows} rows"
            print(f"raw.{table_name(csv_path)}: {status}")


if __name__ == "__main__":
    main()
