# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Public portfolio project (public GitHub repo, MIT): a small data warehouse built from the open MIMIC-IV Clinical Database Demo (v2.2, de-identified). The pipeline loads raw files into Postgres, models them with dbt, and shows them on a public Streamlit dashboard. Early stage — so far the repo has tooling, CI, a placeholder package, and a dashboard that only checks the DB connection. `dbt-core`/`dbt-postgres` are dependencies, but no dbt project exists yet.

Full credentialed MIMIC-IV data must never go into the repo, Neon, the dashboard, or a chat. Only the open demo data is used.

## Roadmap

1. Loader: start with one table (e.g. `hosp/patients`) into a `raw` schema in local Postgres, then extend to all files. Record a SHA-256 per file and skip files that haven't changed. Add a test so CI covers it.
2. Load into Neon `main` and make sure the `dashboard_ro` role can read the tables.
3. dbt models, then replace the placeholder dashboard with real charts.
4. Finish the README.

## Commands

Python 3.12, managed with `uv`. On this machine `uv` is not on PATH, so run it as `python -m uv ...` (e.g. `python -m uv run pytest`). The commands below show plain `uv`, which is what CI uses.

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

- **Databases:** local Postgres from `docker-compose.yml` (credentials `POSTGRES_USER`/`POSTGRES_PASSWORD`/`POSTGRES_DB` from `.env`), plus the hosted Neon project `icu-warehouse`, which has the branches `main` (`NEON_MAIN_URL`) and `ci` (`NEON_CI_URL`). The dashboard connects as the read-only role `dashboard_ro`. Repo secrets for GitHub Actions: `NEON_CI_URL`, `NEON_API_KEY`.
- **Dashboard:** `dashboard/app.py` reads `DATABASE_URL` from `.streamlit/secrets.toml` via `st.secrets` and connects with psycopg 3. `dashboard/requirements.txt` holds its own dependency list for deployment, separate from `pyproject.toml`.
- **Package:** `src/icu_data_warehouse/` (uv_build backend, console script `icu-data-warehouse` → `main`).
- **CI** (`.github/workflows/ci.yml`, on every push): `uv sync --locked`, ruff check, pytest, then a psycopg connection check against `DATABASE_URL` (GitHub secret `NEON_CI_URL`). If you change dependencies, update `uv.lock`, or CI fails.
- **Source data:** `data/mimic-iv-demo/` has gzipped CSVs in `hosp/` (hospital-wide tables such as patients, admissions, labevents) and `icu/` (icustays, chartevents, inputevents, and so on, with `d_items` as the item dictionary). `data/` is gitignored and so are both secrets files (`.env`, `.streamlit/secrets.toml`). Never commit them; gitleaks runs in pre-commit.
