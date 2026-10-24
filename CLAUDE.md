# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Portfolio project: a PostgreSQL data warehouse for ICU data, built from the MIMIC-IV Clinical Database Demo (v2.2). Early stage — so far the repo has tooling, CI, a placeholder package, and a Streamlit dashboard that only checks the DB connection. `dbt-core`/`dbt-postgres` are dependencies, but no dbt project exists yet.

The repo must never contain real patient data; use only synthetic or de-identified datasets.

## Commands

Python 3.12, managed with `uv`.

```bash
uv sync                          # install deps (CI uses: uv sync --locked)
uv run pytest                    # all tests
uv run pytest tests/test_smoke.py::test_smoke   # single test
uv run ruff check .              # lint (what CI runs)
uv run ruff format .             # format
uv run sqlfluff lint <path>      # SQL lint, postgres dialect (.sqlfluff)
uv run pre-commit run --all-files   # ruff, ruff-format, sqlfluff-lint, gitleaks
docker compose up -d db          # local Postgres 16 on 127.0.0.1:5432
uv run streamlit run dashboard/app.py
```

## Architecture and environment

- **Databases:** local Postgres from `docker-compose.yml` (credentials `POSTGRES_USER`/`POSTGRES_PASSWORD`/`POSTGRES_DB` from `.env`), plus hosted Neon Postgres: `NEON_MAIN_URL` (main) and `NEON_CI_URL` (CI) in `.env`.
- **Dashboard:** `dashboard/app.py` reads `DATABASE_URL` from `.streamlit/secrets.toml` via `st.secrets` and connects with psycopg 3. `dashboard/requirements.txt` holds its own dependency list for deployment, separate from `pyproject.toml`.
- **Package:** `src/icu_data_warehouse/` (uv_build backend, console script `icu-data-warehouse` → `main`).
- **CI** (`.github/workflows/ci.yml`, on every push): `uv sync --locked`, ruff check, pytest, then a psycopg connection check against `DATABASE_URL` (GitHub secret `NEON_CI_URL`). If you change dependencies, update `uv.lock`, or CI fails.
- **Source data:** `data/mimic-iv-demo/` has gzipped CSVs in `hosp/` (hospital-wide tables such as patients, admissions, labevents) and `icu/` (icustays, chartevents, inputevents, and so on, with `d_items` as the item dictionary). `data/` is gitignored and so are both secrets files (`.env`, `.streamlit/secrets.toml`). Never commit them; gitleaks runs in pre-commit.
