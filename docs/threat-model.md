# Threat model

> What could go wrong, what the repository does about it, and what is left. Checked against the repository and Neon `main` on 2026-11-03. The pipeline and its trust boundaries are drawn in [architecture.md](architecture.md).

The data is the open MIMIC-IV demo: de-identified, published under the ODbL, with every date shifted. None of the controls below is legally required for it. They are built as if the data were a real hospital's, because that is the job; the last section says what would have to change if it were.

## Assets

| Asset | Where it lives | Why it matters |
| --- | --- | --- |
| Patient rows | Neon `main` (`raw`, `staging`, `marts`); local Docker | `raw` and `marts.dim_patient` hold `subject_id` and the date of death. With real data, this is the health data the system exists to protect |
| Owner connection string (`NEON_MAIN_URL`) | `.env` on the laptop | Reads, changes and deletes everything on Neon `main` |
| Dashboard connection string (`dashboard_ro`) | `.streamlit/secrets.toml` on the laptop; the app's secrets on Streamlit Cloud | Reads the four `marts_public` views, nothing else |
| `NEON_API_KEY` | GitHub Actions secret | Manages the Neon project: creates and deletes branches, including `main` |
| `ICU_HMAC_KEY` | `.env`; GitHub Actions secret | Without it, a `subject_key` cannot be traced back to a `subject_id` |
| GitHub access | `gh` login and an SSH key with a passphrase, on the laptop | Pushing code: CI runs whatever is pushed, with the secrets above |
| Streamlit account | Streamlit Community Cloud | Changing the dashboard's code source or its secrets |

## Trust boundaries

| Boundary | What crosses it | What is trusted on each side |
| --- | --- | --- |
| Laptop → Neon | CSVs loaded with `COPY`; dbt builds; owner credentials, encrypted (Neon accepts only TLS connections) | The laptop holds the source data and every secret |
| GitHub Actions → Neon | Branch create and delete via the Neon API; a branch-scoped connection | CI never sees `NEON_MAIN_URL`. It works on a throwaway copy of `main` and deletes it afterwards |
| Streamlit Cloud → Neon | `SELECT` on `marts_public` as `dashboard_ro`, encrypted | Streamlit Cloud holds only the `dashboard_ro` password |
| Internet → Streamlit Cloud | Page views of the public dashboard | Anyone; no sign-in, by design (out of scope in the spec) |
| Laptop → GitHub | Code only: `data/`, `.env` and `secrets.toml` are gitignored | gitleaks runs before every commit |

## Threats (STRIDE)

STRIDE sorts threats into six kinds: **S**poofing (pretending to be someone), **T**ampering (changing data), **R**epudiation (denying having done something), **I**nformation disclosure, **D**enial of service and **E**levation of privilege. "Residual" is what remains after the mitigation.

| # | Kind | Threat | Mitigation in this repository | Residual |
| --- | --- | --- | --- | --- |
| S1 | Spoofing | Someone gets the `dashboard_ro` password, e.g. from Streamlit's secrets | The role can read only the four `marts_public` views, which are public on the dashboard anyway ([minimization.sql](../security/minimization.sql), proven in [test_security.py](../tests/test_security.py)) | Low. The password has not yet been rotated once, as the spec asks; it has no expiry date |
| S2 | Spoofing | Someone gets `NEON_MAIN_URL`, the owner's login | It exists only in `.env`, which is gitignored; gitleaks blocks commits that contain secrets; CI does not use it | High if it happens: the owner can do anything. Depends on the laptop staying secure |
| S3 | Spoofing | Someone gets `NEON_API_KEY` | Stored as a GitHub secret, masked in logs, used in two CI steps only | High if it happens: the key controls the whole Neon project, including deleting `main` |
| T1 | Tampering | A patient row is changed by hand between builds | An audit trigger on every dimension logs who changed what, with the row before and after ([audit.sql](../security/audit.sql)). The pipeline role can add to the log but not read, change or delete it | The owner can delete audit rows. `etl_writer` could insert fake audit rows, but each carries the real login name. A dbt rebuild is not logged row by row; its record is the git history |
| T2 | Tampering | A broken or malicious model change | Every push is built and tested on a throwaway Neon branch (235 dbt checks, 111 pytest tests); `main` is rebuilt by hand only after that | `main` has no branch protection: a push to it is not blocked by a failing CI run, only reported |
| T3 | Tampering | A compromised dependency (supply chain) | Python dependencies are locked with hashes in `uv.lock` and installed with `uv sync --locked`; Dependabot security updates are on | GitHub Actions are pinned by version tag (`@v7`), not by commit hash, so a moved tag would run new code |
| R1 | Repudiation | Someone denies having changed data | The audit log records the role in effect and the login user, with a timestamp | Reads are not logged. Logging them needs `pgaudit`, which Neon offers but is not turned on |
| I1 | Information disclosure | The public dashboard reveals identifying detail | It reads only `marts_public`: no identifiers, no dates, no date of death, ages in 10-year bands, lengths of stay rounded, labs only as quartiles. Tests check every public column ([test_security.py](../tests/test_security.py)) | Small groups are not suppressed: a unit with one or two stays still shows them, and a rare combination of band, gender and unit can single a person out |
| I2 | Information disclosure | Analysts see more than their care unit | Row-level security on the three per-stay facts, attached by dbt in the same transaction that builds each table, so a rebuilt table is never without it | RLS covers the facts only. Analysts can read every dimension in full, including `dim_patient.subject_id` and the date of death |
| I3 | Information disclosure | `subject_key` is reversed to `subject_id` | An HMAC with a key kept outside the database, not a plain hash; keys shorter than 32 characters are refused; rotation is tested ([pseudonymize.sql](../security/pseudonymize.sql)) | Anyone with the key and the database can reverse it, by design |
| I4 | Information disclosure | The HMAC key leaks through dbt's files | The model passes the key as a template string, so it stays out of `manifest.json`. dbt's `partial_parse.msgpack` and `dbt.log` do contain it; both are gitignored | Publishing `dbt/target` or `dbt/logs` beyond the generated docs would leak it |
| I5 | Information disclosure | A secret is committed to git | `.env`, `secrets.toml` and `data/` are gitignored; gitleaks runs in pre-commit; GitHub secret scanning is on | gitleaks does not run in CI yet, so a commit made without pre-commit is caught only by GitHub's scanning |
| D1 | Denial of service | The dashboard or the database is overloaded | Dashboard results are cached for an hour; Neon scales compute down when idle; queries are aggregates over 100 patients | No `statement_timeout` on `dashboard_ro`: with its password, someone could run long queries |
| D2 | Denial of service | CI branches pile up and hit Neon's branch limit | The branch is deleted at the end of every run, even after a failure, and expires after an hour | Low |
| E1 | Elevation of privilege | SQL injection through the dashboard | Every query is fixed SQL in [queries.py](../dashboard/queries.py), with values passed as parameters; the role is read-only and limited to `marts_public` | Low |
| E2 | Elevation of privilege | A function runs with more rights than its caller | No `security definer` functions: the audit and pseudonymization functions run as their caller; `pseudonymize` fixes its `search_path` | Low |
| E3 | Elevation of privilege | Row-level security is switched off, or worked around with a setting | Policies filter by role, not by a session setting a user could change; tests fail if RLS is off; roles cannot bypass RLS | The owner is not limited by RLS, as on any Postgres table |

## Open actions

The residuals worth fixing, roughly in order of value for effort:

1. Rotate the `dashboard_ro` password once and record it in the README's operations section (spec, "Secrets hygiene").
2. Run gitleaks in CI, and prove it with a planted fake key, as the spec asks.
3. Protect `main`: require the CI check to pass before a merge.
4. Set a `statement_timeout` on `dashboard_ro`.
5. Limit what analysts can read in the dimensions, for example by granting them only some columns of `dim_patient`.
6. Pin GitHub Actions to commit hashes.

## What changes if this were real patient data

The demo is open data, so the dashboard can be public. With real, identifiable health data (special-category data under GDPR, PHI under HIPAA), the design would change:

- **Access.** No public dashboard on patient-level data, however minimized. Every user signs in as their own account, with multi-factor authentication, and is made a member of a role (`analyst_micu`, ...). Access is reviewed regularly and removed when someone leaves.
- **Small numbers.** Published aggregates suppress small cells (a common rule is fewer than 11), so a count cannot point to one patient.
- **Keys and secrets.** The HMAC key and database credentials go into a secrets manager or KMS, not a `.env` file. Credentials rotate on a schedule, and a leaked key is rotated at once.
- **Auditing.** Reads are logged too, with `pgaudit`, shipped to a log store the database owner cannot alter.
- **Where the data lives.** A provider and region chosen for the law that applies (for EU patients, hosting in the EU or a lawful transfer basis), with a data processing agreement or a HIPAA business associate agreement. Encryption at rest and in transit, confirmed with the provider.
- **Environments.** Production separate from development and CI. CI runs on synthetic or de-identified data, never on a copy of production.
- **Laptops.** Data on a laptop only when unavoidable, on an encrypted disk; credentialed data never leaves it, and never reaches the repository, Neon, the dashboard or an AI chat.
- **Governance.** A DPIA before processing starts (GDPR Art. 35), a retention period with a purge job, and a breach-notification process. The [GDPR note](gdpr-note.md) covers these.
