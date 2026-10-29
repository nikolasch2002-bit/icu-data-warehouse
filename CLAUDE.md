# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A SQL-first clinical data warehouse, built as a public portfolio project (MIT) for Analytics Engineer and Clinical Data Engineer roles. It loads the open MIMIC-IV Clinical Database Demo v2.2 (100 patients, ODbL) into Postgres, models a star schema with dbt, answers 12 clinical questions in plain SQL, and serves a public Streamlit dashboard. It also includes a security and GDPR layer: roles, row-level security, an audit trigger, minimization views, HMAC pseudonymization, a threat model and a GDPR note.

**[docs/project-spec.md](docs/project-spec.md) is the source of truth.** It defines the scope (what is in and out), the grain of every fact and the attributes of every dimension, the 12 analytic queries, the security deliverables and how each is proven, the target repo layout, and the README outline. Read the relevant section before building any part.

Current state: early. The repo has tooling, CI, a placeholder package in `src/`, and a dashboard that only checks the DB connection. The loader is done, the dbt project has its first staging model, and `security/` has a start; `analytics/` and the `Makefile` do not exist yet. The spec's target layout uses `loader/`, `dbt/`, `analytics/` and `security/` at the top level.

## Rules that shape the work

- **Data:** only the open demo. Full credentialed MIMIC-IV must never go into the repo, Neon, the dashboard, or a chat. Raw CSVs are never committed; `data/` is gitignored.
- **The design comes before the code.** The schema and grain are fixed in the spec and in `docs/data-model.md`. Implement them; don't invent new facts, dimensions or scope. Things listed as out of scope (ML, medications, microbiology, notes, OMOP, streaming, dashboard auth) stay out.
- **The user must be able to explain every line in an interview.** Keep changes small and explain the reasoning for non-obvious SQL: window partitions, RLS policies, dbt tests. Commit in small steps with messages that say *why*, because the commit history is part of the portfolio. The user writes ADRs (`docs/adr/`, MADR format); you can draft one, but flag it for them to rewrite.
- **Modelling conventions:** surrogate integer keys on every dimension, and facts never join on `subject_id`. Type 1 dimensions. `chartevents` is filtered to the 7 vital-sign item ids at staging. `dim_date` covers 2100–2214 because MIMIC shifts dates; age comes from `anchor_age` / `anchor_year_group`. `subject_key` is an HMAC of `subject_id`, with the key kept outside the database.
- **SQL is the main language.** Python is used only for loading (httpx + psycopg 3 `COPY`, with no pandas), tests and the dashboard.
- **Public exposure:** the dashboard role reads only the `marts_public` views, never base tables, and `dod` is never exposed.

## Roadmap (next steps)

1. Loader: start with one table (`hosp/patients`) into a `raw` schema in local Postgres, then extend to all files. Record a SHA-256 per file in `raw.load_log` and skip unchanged files. Add a test so CI covers it.
2. Load into Neon `main` and make sure the dashboard's read-only role (`dashboard_ro`) can read what it needs.
3. dbt staging → marts, then the 12 analytic queries, then the `security/` layer, then the four-page dashboard (Overview, Length of stay, Mortality, Lab trends).
4. The docs (architecture, data model + Mermaid ERD, threat model, GDPR note), and a README that follows the spec's outline, including the ODbL and PhysioNet citations.

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
uv run --env-file .env python -m loader.load_raw [hosp/x.csv.gz ...] [--force]   # local Docker Postgres; no args = all 31 files
uv run --env-file .env sh -c 'DATABASE_URL="$NEON_MAIN_URL" python -m loader.load_raw'   # load into Neon main
uv run --env-file .env pytest    # DB tests skip unless DATABASE_URL or POSTGRES_* are set
uv run --env-file .env dbt build --project-dir dbt --profiles-dir dbt   # models + tests, local Docker
uv run --env-file .env dbt build --project-dir dbt --profiles-dir dbt -s stg_hosp__patients   # one model + its tests
```

dbt (`dbt/`): `profiles.yml` holds no credentials. Locally it uses `POSTGRES_*` and `127.0.0.1`; CI sets `DBT_HOST`/`DBT_USER`/`DBT_PASSWORD`/`DBT_DBNAME`/`DBT_SSLMODE` to the run's Neon branch. The `generate_schema_name` macro makes models build into exactly the schema they name (`staging`, later `marts`), not dbt's default `dbt_staging`. Staging models are views named `stg_<module>__<table>`, one per source table, with tests in a `.yml` file next to each model. Sources are declared per MIMIC module (`hosp`, `icu`), both pointing at schema `raw`. Generic tests use dbt 1.10+ syntax, with `arguments:` under the test name.

The loader (`loader/load_raw.py`) uses `DATABASE_URL` when it's set, and otherwise local Docker on `127.0.0.1`. For each file under `hosp/` and `icu/`, it replaces `raw.<file name>` with an all-text copy of the CSV and appends a row to `raw.load_log` (source path, SHA-256, row count, load time). Both happen in one transaction. A file whose SHA-256 matches its last load is skipped, unless its table is missing or `--force` is given. `source_path` uses PhysioNet's `SHA256SUMS.txt` format (`hosp/patients.csv.gz`), so the log can be checked against it. A full load takes about 6 s locally and about 55 s to Neon; `raw` is about 180 MB, and `chartevents` (669k rows) is the largest table. `tests/test_loader.py` loads synthetic files into a throwaway `loader_test` schema, so in CI it runs against that run's throwaway Neon branch.

## Architecture and environment

- **Databases:** local Postgres from `docker-compose.yml` (credentials `POSTGRES_USER`/`POSTGRES_PASSWORD`/`POSTGRES_DB` from `.env`), plus the hosted Neon project `icu-warehouse` (project ID `quiet-king-49553823`), whose `main` branch is reached through `NEON_MAIN_URL`. The dashboard connects as the read-only role `dashboard_ro`. The repo secrets for GitHub Actions are `NEON_API_KEY` and `ICU_HMAC_KEY`. `ICU_HMAC_KEY` (64 hex characters, also in `.env`) is the HMAC key for `dim_patient.subject_key`. dbt needs it for every command, because `env_var()` without a default fails if it is missing. It reaches Postgres only through `dim_patient`'s pre_hook, as a transaction-local setting (`app.hmac_key`). The hook is a template string, so the key's value stays out of `manifest.json`. dbt's local `partial_parse.msgpack` and `dbt.log` do contain it, so never publish `dbt/target` or `dbt/logs` beyond the generated docs. The fixed `ci` branch and the `NEON_CI_URL` secret are no longer used by CI.
- **Dashboard:** `dashboard/app.py` reads `DATABASE_URL` from `.streamlit/secrets.toml` via `st.secrets` and connects with psycopg 3. `dashboard/requirements.txt` holds its own dependency list for deployment, separate from `pyproject.toml`.
- **Package:** `src/icu_data_warehouse/` (uv_build backend, console script `icu-data-warehouse` → `main`).
- **CI** (`.github/workflows/ci.yml`, on every push): `uv sync --locked` and ruff check, then it creates a fresh Neon branch `ci-<run id>-<attempt>` from `main`. It checks the connection and runs pytest with `DATABASE_URL` pointing at that branch, then deletes the branch through the Neon API, even if the tests failed. Each branch also expires after 1 hour as a fallback. If you change dependencies, update `uv.lock`, or CI fails. Check runs with `gh run list` / `gh run view --log-failed`; on this machine `gh` is at `C:\Program Files\GitHub CLI\gh.exe` and may not be on PATH.
- **Source data:** `data/mimic-iv-demo/` has gzipped CSVs in `hosp/` (hospital-wide tables such as patients, admissions, labevents) and `icu/` (icustays, chartevents, inputevents, and so on, with `d_items` as the item dictionary). `data/` is gitignored and so are both secrets files (`.env`, `.streamlit/secrets.toml`). Never commit them; gitleaks runs in pre-commit.
