"""Load MIMIC-IV demo CSVs verbatim into the raw schema.

Every column is loaded as text. Typing and renaming happen in dbt staging,
so raw stays a faithful copy of the source file.

Usage:
    python -m loader.load_raw                      # hosp/patients.csv.gz
    python -m loader.load_raw icu/icustays.csv.gz  # any file under data/mimic-iv-demo
"""

import argparse
import csv
import gzip
import os
from pathlib import Path

import psycopg
from psycopg import sql
from psycopg.conninfo import make_conninfo

DATA_DIR = Path(__file__).resolve().parent.parent / "data" / "mimic-iv-demo"
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


def read_header(csv_path: Path) -> list[str]:
    with gzip.open(csv_path, "rt", newline="", encoding="utf-8") as f:
        return next(csv.reader(f))


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


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "files",
        nargs="*",
        default=["hosp/patients.csv.gz"],
        help="paths relative to data/mimic-iv-demo",
    )
    args = parser.parse_args()

    with psycopg.connect(database_url()) as conn:
        for name in args.files:
            csv_path = DATA_DIR / name
            rows = load_csv(conn, csv_path)
            print(f"raw.{table_name(csv_path)}: {rows} rows")


if __name__ == "__main__":
    main()
