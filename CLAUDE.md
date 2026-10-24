# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A SQL-first clinical data warehouse, built as a public portfolio project (MIT) for Analytics Engineer and Clinical Data Engineer roles. It loads the open MIMIC-IV Clinical Database Demo v2.2 (100 patients, ODbL) into Postgres, models a star schema with dbt, answers 12 clinical questions in plain SQL, and serves a public Streamlit dashboard. It also includes a security and GDPR layer: roles, row-level security, an audit trigger, minimization views, HMAC pseudonymization, a threat model and a GDPR note.

**[docs/project-spec.md](docs/project-spec.md) is the source of truth.** It defines the scope (what is in and out), the grain of every fact and the attributes of every dimension, the 12 analytic queries, the security deliverables and how each is proven, the target repo layout, and the README outline. Read the relevant section before building any part.

Current state: early. The repo has tooling, CI, a placeholder package in `src/`, and a dashboard that only checks the DB connection. There is no loader, dbt project, `analytics/`, `security/` or `Makefile` yet. The spec's target layout uses `loader/`, `dbt/`, `analytics/` and `security/` at the top level.

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
```

## Architecture and environment

- **Databases:** local Postgres from `docker-compose.yml` (credentials `POSTGRES_USER`/`POSTGRES_PASSWORD`/`POSTGRES_DB` from `.env`), plus the hosted Neon project `icu-warehouse`, which has the branches `main` (`NEON_MAIN_URL`) and `ci` (`NEON_CI_URL`). The dashboard connects as the read-only role `dashboard_ro`. Repo secrets for GitHub Actions: `NEON_CI_URL`, `NEON_API_KEY`.
- **Dashboard:** `dashboard/app.py` reads `DATABASE_URL` from `.streamlit/secrets.toml` via `st.secrets` and connects with psycopg 3. `dashboard/requirements.txt` holds its own dependency list for deployment, separate from `pyproject.toml`.
- **Package:** `src/icu_data_warehouse/` (uv_build backend, console script `icu-data-warehouse` → `main`).
- **CI** (`.github/workflows/ci.yml`, on every push): `uv sync --locked`, ruff check, pytest, then a psycopg connection check against `DATABASE_URL` (GitHub secret `NEON_CI_URL`). If you change dependencies, update `uv.lock`, or CI fails.
- **Source data:** `data/mimic-iv-demo/` has gzipped CSVs in `hosp/` (hospital-wide tables such as patients, admissions, labevents) and `icu/` (icustays, chartevents, inputevents, and so on, with `d_items` as the item dictionary). `data/` is gitignored and so are both secrets files (`.env`, `.streamlit/secrets.toml`). Never commit them; gitleaks runs in pre-commit.
