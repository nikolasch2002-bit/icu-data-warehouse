# ICU Data Warehouse — Portfolio Project Spec

Written 2026-10-12.

A SQL-first clinical data warehouse on MIMIC-IV, built from scratch to a hosted dashboard, with a written security and GDPR posture. It is a portfolio piece that joins a biomedical degree to two years of SQL work.

## What this proves

The CV line: "Designed and built an ICU clinical data warehouse on MIMIC-IV — star schema, tested SQL/dbt pipeline, hosted dashboard — with a documented threat model, row-level security and a GDPR analysis for health data."

| Claim | Where the proof lives |
| --- | --- |
| Can model data properly (grain, facts, dimensions, slowly changing attributes) | `docs/data-model.md` + the dbt marts models |
| Can build and test a pipeline, not just write ad-hoc queries | dbt tests, pytest, a green CI badge on the README |
| Understands the clinical meaning of the data | The analytic queries: KDIGO creatinine staging, lactate clearance, ICU-free days, chosen and explained by someone with a biomedical degree |
| Takes personal-data security seriously | `security/` (roles, RLS policies, audit trigger) + `docs/threat-model.md` + `docs/gdpr-note.md` |
| Can take an idea from nothing to a URL | The live dashboard, the repo, the ADRs that record each decision |

Target job titles: **Analytics Engineer** (dbt + SQL + modelling) and **Clinical Data Engineer / Healthcare Data Analyst** (pharma, hospitals, health-tech, CROs in NL, IE, DE, DK; English-only hiring).

## Data: the demo first, the full dataset later

The MIMIC-IV Clinical Database Demo v2.2 has 100 patients, is 15.5 MB uncompressed, has the same schema as full MIMIC-IV, needs no credentialing, and is under the Open Data Commons ODbL v1.0 licence. The whole project is built on the demo; full access is a stretch goal applied for in parallel.

| | Demo (phase 1) | Full MIMIC-IV (phase 2, optional) |
| --- | --- | --- |
| Patients | 100 | ~365,000 (hosp), ~73,000 ICU stays |
| Size | 15.5 MB | tens of GB; labevents alone is >100M rows |
| Access | Open, ODbL | PhysioNet credentialing + CITI course + signed DUA |
| May be hosted publicly | Yes (attribution + share-alike) | No (DUA clause 3) |
| May be pasted into a cloud AI tool | Yes | No (PhysioNet 2025 guidance forbids online LLM platforms) |
| Good for | The whole pipeline, model, security demo, dashboard | Volume: query performance, partitioning, incremental dbt models |

Why this order:

- The schema is the same, so every dbt model written against the demo runs unchanged on the full data.
- The public dashboard must run on demo data anyway. Keeping the two apart is a compliance story: "the deployed system only ever touches open data; credentialed data stays on an encrypted laptop".
- Credentialing is a background task with a wait; it blocks nothing.

**Dates:** MIMIC shifts every patient's dates into 2100–2200 and reports age via `anchor_age` / `anchor_year_group`. The date dimension must cover that range.

## Scope

The warehouse answers a fixed set of clinical questions over admissions, ICU stays, diagnoses, labs and vitals. Nothing else is in scope for version 1.

### In

- Load the demo's `hosp` and `icu` modules into a `raw` schema, verbatim, with checksums.
- A dbt project: staging (typed, renamed, one model per source table) → marts (the star schema below).
- Five source tables drive the facts: `admissions`, `icustays`, `diagnoses_icd`, `labevents`, `chartevents` (vitals only: heart rate, blood pressures, SpO2, respiratory rate, temperature).
- Twelve published analytic queries, each a `.sql` file with a paragraph of clinical meaning and a results table in the README:
    1. Cohort counts: patients, admissions, ICU stays, by year group and care unit
    2. Length of stay distribution (median, IQR) per ICU unit
    3. In-hospital mortality by care unit and by admission type
    4. 30-day hospital readmission rate
    5. Top 20 diagnoses by ICD chapter
    6. Creatinine trend per ICU stay (window functions: first, peak, last)
    7. AKI staging by the KDIGO creatinine criteria (≥1.5× baseline within 7 days, or ≥0.3 mg/dL rise within 48 h) — the biomedical showpiece
    8. Lactate clearance in the first 24 h for stays with a lactate ≥2 mmol/L
    9. Hyperkalemia flags (K⁺ ≥5.5) and what happened in the following 6 h of vitals
    10. ICU-free days at day 28
    11. Vital-sign trajectory in the 24 h before death vs. matched survivors
    12. Data-quality report: orphan rows, out-of-range values, duplicate charting
- A dashboard with four pages: Overview, Length of stay, Mortality, Lab trends.
- `security/`: Postgres roles, row-level security per care unit, an audit trigger, column-level minimization views, a pseudonymization function.
- `docs/`: architecture, data model (ERD), threat model, GDPR note, ADRs.

### Out (say so in the README)

- Machine learning or prediction. The queries are descriptive.
- Free-text notes (not in the demo), medications (`emar`, `prescriptions`), microbiology — "phase 2 facts".
- OMOP CDM mapping. Mention it as the industry standard and why it was not done (scope).
- Real-time or streaming ingestion.
- Authentication on the dashboard. It serves open data and aggregates only.

## Architecture

Each step left to right is a trust boundary: the laptop downloads and loads, Neon holds every layer, and only the `marts_public` views (minimized columns, row-level security) are readable by the role the public dashboard uses. CI gets its own Neon branch per run, so a bad model never touches main. Base tables are never granted to anything outside the database.

## Data model: the star schema

Five facts share eight conformed dimensions. State the grain of every fact in one sentence before writing SQL.

| Fact | Grain: one row per… | Measures | Dimensions |
| --- | --- | --- | --- |
| `fact_hospital_admission` | `hadm_id` | LOS (days), in-hospital death flag, came-through-ED flag, 30-day readmission flag | patient, admission, date (admit), date (discharge) |
| `fact_icu_stay` | `stay_id` | ICU LOS (hours), died-in-ICU flag, transfers count | patient, admission, care_unit (first), care_unit (last), date (in) |
| `fact_diagnosis` | `hadm_id` × ICD code | `seq_num` (priority) | patient, admission, diagnosis |
| `fact_lab_result` | row of `labevents` | `valuenum`, abnormal flag, reference range | patient, admission, lab_item, date, time |
| `fact_vital_sign` | charted vital (`chartevents` filtered to 7 item ids) | `valuenum` | patient, icu stay, chart_item, date, time |

| Dimension | Attributes | Note |
| --- | --- | --- |
| `dim_patient` | `subject_key` (HMAC of `subject_id`), gender, anchor_age, anchor_year_group, dod | `dod` is the one column the public views never expose |
| `dim_admission` | admission type and location, discharge location, insurance, language, marital status, race | One row per admission, kept separate to keep the fact narrow |
| `dim_date` | 2100–2214, year, month, day of week, weekend flag | Covers MIMIC's shifted dates; role-playing dimension (used twice by the admission fact) |
| `dim_time` | hour of day, shift (day / evening / night) | Lets the vitals queries ask "night-time hypotension" |
| `dim_care_unit` | care unit name, derived type (medical, surgical, cardiac, neuro, trauma, mixed) | The derived type is a hand-curated, documented mapping |
| `dim_lab_item` | itemid, label, fluid, category | From `d_labitems` |
| `dim_chart_item` | itemid, label, unit | The 7 vital-sign items only |
| `dim_diagnosis` | ICD code, ICD version (9/10), title, chapter | Chapter derived from code ranges |

Decisions to record as ADRs:

- Surrogate integer keys on every dimension; never join facts on `subject_id`.
- Type 1 dimensions everywhere, with a paragraph on what Type 2 would look like for `dim_care_unit` if units were renamed.
- `chartevents` filtered at staging rather than loaded whole into a fact (document the item ids and why those seven).

The Mermaid ERD in `docs/data-model.md` is the picture of this.

## Technology stack

Everything is free at this project's size, and deliberately boring.

| Layer | Choice | Why this and not the alternative |
| --- | --- | --- |
| Database | PostgreSQL 16, locally in Docker, hosted on Neon (free: 1 GB/project, scales to zero after 5 min, 10 branches) | Plain Postgres; branches give CI a throwaway database. Supabase's free tier pauses after a week idle |
| Extract + load | Python 3.12 + uv, httpx for download, psycopg 3 with `COPY` into a `raw` schema | `COPY` is the right tool for CSV-to-Postgres; pandas adds nothing. Checksums recorded in a `raw.load_log` table |
| Transform + test + docs | dbt-core with dbt-postgres | Staging → marts, built-in tests (unique, not_null, relationships, accepted_values), lineage docs published to GitHub Pages |
| Analytic queries | Plain `.sql` files in `analytics/`, run by `make analytics`, results snapshotted as markdown | Shows SQL craft (CTEs, window functions) outside dbt |
| Dashboard | Streamlit on Streamlit Community Cloud, reads Neon via a secret | Free hosting that stays up. Metabase needs a paid or always-on host; Evidence.dev is the runner-up |
| CI | GitHub Actions: ruff, sqlfluff, pytest, dbt build against a Neon branch created per run | A green badge on the README |
| Local tooling | Docker Desktop, psql, DBeaver, pre-commit with gitleaks | |
| Security demo | Postgres roles + `CREATE POLICY` (RLS), trigger-based audit table, pgcrypto HMAC for pseudonymous keys | Native Postgres features |
| Diagrams + docs | Markdown in `docs/`, Mermaid for the ERD, ADRs in MADR format | |

SQL is the main language of the repo (dbt models, analytics, security). Python is only for loading, tests and the dashboard.

## Security and compliance deliverables

The demo data is open and de-identified, so none of this is legally required. It is built as if the data were a real hospital's, because that is the job. Say that sentence in the README.

| Deliverable | What it contains | Proof it works |
| --- | --- | --- |
| `docs/threat-model.md` | STRIDE table: assets (patient rows, the Neon connection string, the GitHub token), trust boundaries (laptop / Neon / Streamlit Cloud / GitHub Actions), top risks and mitigations. Ends with "what changes if this were real PHI" | Reviewed against the repo at the end of week 7 |
| `security/roles.sql` | Four roles: `etl_writer` (raw + staging only), `analyst_micu`, `analyst_sicu` (marts, read-only), `auditor` (audit table only). Least privilege via GRANT, no superuser after setup | A pytest that connects as each role and asserts what it can and cannot see |
| `security/rls.sql` | `ENABLE ROW LEVEL SECURITY` + `CREATE POLICY` on `fact_icu_stay` and the lab/vital facts, filtering by care unit via `current_setting('app.care_unit')` or the role name | Same pytest: `analyst_micu` counts only MICU stays |
| `security/audit.sql` | `audit.change_log` (who, when, table, old row, new row as jsonb) fed by a trigger on the dimensions; a note on pgaudit / `log_statement` for read auditing | Insert, update, delete a `dim_patient` row as `etl_writer`; three audit rows appear |
| `security/minimization.sql` | `marts_public` views: age in 10-year bands, no dod, no insurance/language/race unless needed; the dashboard role reads only these views | The dashboard role has no grant on base tables |
| `security/pseudonymize.sql` | `subject_key = encode(hmac(subject_id::text, key, 'sha256'), 'hex')` with the key from a setting outside the database; a paragraph on rotation and on why hashing without a key is not pseudonymization | Re-running with a new key changes every key and nothing else |
| `docs/gdpr-note.md` | Two pages: Art. 9 special category; lawful basis options (Art. 6(1)(e) + Art. 9(2)(j) with Art. 89 safeguards, or explicit consent); pseudonymization (Art. 4(5)) vs anonymization, and why HIPAA-de-identified is not automatically GDPR-anonymous; minimization (Art. 5(1)(c)); retention and purge; DPIA (Art. 35); data-subject rights and research exemptions; US→EU transfer; what the project does for each point | Cross-checked against the GDPR text, article by article |
| Secrets hygiene | `.env.example`, gitleaks in pre-commit and CI, Neon password rotated once (documented in the README's "operations" section) | CI fails on a planted fake key, then the commit is reverted |

The GDPR note reads as "here is what the law asks and here is what this system does", not legal advice. Cite article numbers, not blog posts.

## Setup checklist

1. GitHub account (real name) and a public repo `icu-data-warehouse`, MIT licence, secret scanning and Dependabot on.
2. Git installed, SSH key added to GitHub, `user.name` / `user.email` set.
3. Docker Desktop for local Postgres (`docker compose up db`).
4. Python 3.12 + uv; `uv add psycopg[binary] httpx dbt-core dbt-postgres streamlit pytest ruff sqlfluff pre-commit`.
5. DBeaver Community; psql comes with the Postgres Docker image.
6. Download the demo zip from physionet.org/content/mimic-iv-demo/2.2 into `data/` (gitignored); the loader records the SHA-256 of each CSV.
7. Neon account: project `icu-warehouse`, branches `main` and `ci`. Connection string into `.env`, never the repo.
8. Streamlit Community Cloud: deploy `dashboard/app.py`; paste the Neon read-only connection string into the app's Secrets.
9. GitHub Actions: `ci.yml` on every push; `NEON_API_KEY` and the CI connection string as repository secrets.
10. pre-commit with ruff, sqlfluff, gitleaks; `pre-commit install`.
11. ORCID iD.
12. PhysioNet credentialing (Independent Researcher) → CITI "Data or Specimens Only Research" (MIT affiliates option) → upload the completion report.
13. A Google Cloud account only if the full dataset is granted (BigQuery access).

## Repository layout (target)

```
icu-data-warehouse/
├── README.md                 the page a recruiter actually reads
├── docs/
│   ├── architecture.md       pipeline diagram, one paragraph per stage
│   ├── data-model.md         star schema, grain of every fact, Mermaid ERD
│   ├── threat-model.md
│   ├── gdpr-note.md
│   └── adr/                  0001-postgres-over-duckdb.md, 0002-dbt.md, 0003-demo-data-only-in-prod.md ...
├── loader/                   download.py, load_raw.py (COPY), verify.py (checksums, row counts)
├── dbt/
│   ├── models/staging/       stg_hosp__admissions.sql ... one per source table, with schema.yml tests
│   ├── models/marts/         dim_*.sql, fact_*.sql
│   └── tests/                singular tests: los_non_negative.sql, death_after_admission.sql
├── analytics/                01_cohort_counts.sql ... 12_data_quality.sql + RESULTS.md
├── security/                 roles.sql, rls.sql, audit.sql, minimization.sql, pseudonymize.sql
├── dashboard/                app.py + pages/
├── tests/                    test_loader.py, test_security_roles.py
├── .github/workflows/ci.yml
├── docker-compose.yml        local Postgres 16
├── Makefile                  make db, make load, make build, make test, make analytics
├── pyproject.toml
└── .env.example
```

README, top to bottom:

1. One-line pitch, CI badge, link to the live dashboard, link to the dbt docs.
2. A screenshot of the dashboard and the architecture diagram.
3. "What it answers": the 12 queries as a table (question, clinical why, link to the SQL).
4. The star schema picture and three sentences on grain.
5. Security and compliance: links to each file in `security/` and `docs/`.
6. "Run it yourself": five commands.
7. Decisions and trade-offs: a link to each ADR, plus "what I would do with the full dataset".
8. Data citation and licence (the ODbL and PhysioNet citations are a condition of use).

## Milestones

Start Monday 2026-10-19, roughly 10–15 hours a week, about eight weeks. Each week ends with something a stranger can see: a passing `make build`, a green CI run, a query with a result, a URL. Credentialing runs in the background; nothing in weeks 2–8 depends on it.

## Using AI without undermining the portfolio

The risk is that the author cannot defend the code in an interview.

- **Design before prompting.** The star schema, the grain of each fact and the 12 questions are decided in `docs/data-model.md` before code is generated. The AI implements a design; it does not invent one.
- **One ADR per decision, written by a human.** Postgres over DuckDB, dbt over hand-rolled scripts, demo-only in production, HMAC over plain hashing. Short, dated, with the alternative that lost.
- **Explain-back rule.** Nothing is committed until the author can explain every line out loud.
- **Commit history tells the story.** Small commits, messages that say why. Sixty commits over eight weeks read as work.
- **Hard rule:** demo rows may be pasted into a cloud AI tool; full MIMIC-IV rows may not. In phase 2 the assistant gets the schema and typed sample values, never real rows.

The README says plainly that the code was written with AI assistance and links to the ADRs.

## Rules of the road: licence, DUA, GitHub

| | Demo (ODbL v1.0) | Full MIMIC-IV (PhysioNet Credentialed Health Data DUA) |
| --- | --- | --- |
| Commit the raw CSVs to GitHub | Allowed, but don't (the loader downloads them; attribution still required) | Never |
| Host a public dashboard over it | Allowed, with the citation on the page | Never (clause 3) |
| Publish aggregate results | Allowed | Allowed in principle; derived datasets go back to PhysioNet; code must be opened if results are published (clause 9) |
| Paste rows into an AI chat | Allowed | Never (PhysioNet 2025 guidance) |
| Store it | Anywhere | Local disk, encrypted (clause 4). Not in Neon, a repo, or a shared drive |
| Attempt to identify anyone | Pointless, and forbidden | Forbidden (clause 1); found PHI is reported to PHI-report@physionet.org (clause 5) |
| Share-alike | Derived databases of the demo must be ODbL too (mention in the LICENSE section) | n/a |

Citations for the README and the dashboard footer:

- Johnson et al. (2023), MIMIC-IV Clinical Database Demo v2.2, PhysioNet, DOI 10.13026/dp1f-ex47.
- Pollard et al. (2026), PhysioNet, Nature Health, DOI 10.1038/s44360-026-00096-z.

## Sources

Pages opened on 2026-10-12: MIMIC-IV Clinical Database Demo v2.2 (licence, size, contents, citation); MIMIC-IV getting started (credentialing); MIMIC-IV cloud access (BigQuery, GCS); PhysioNet Credentialed Health Data Use Agreement 1.5.0 (clauses 1, 3, 4, 5, 9); MIMIC-IV hosp and icu modules; Neon, Supabase and Metabase pricing.
