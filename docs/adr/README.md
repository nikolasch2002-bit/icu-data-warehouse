# Architecture decision records

Each record states one decision, the options that lost, and why, in [MADR](https://adr.github.io/madr/) format. A record stays `proposed` until the author has written it in their own words, then becomes `accepted`.

| ADR | Decision | Status |
| --- | --- | --- |
| [0001](0001-postgres-over-duckdb.md) | Use PostgreSQL, hosted on Neon, rather than DuckDB | accepted |
| [0002](0002-dbt.md) | Transform with dbt rather than hand-rolled SQL scripts | accepted |
| [0003](0003-demo-data-only-in-prod.md) | Only the open demo data ever reaches anything deployed | accepted |
| [0004](0004-hmac-over-plain-hashing.md) | Pseudonymize patients with a keyed HMAC, not a plain hash | accepted |
| [0005](0005-surrogate-keys.md) | Surrogate integer keys on every dimension; facts never join on `subject_id` | accepted |
| [0006](0006-type-1-dimensions.md) | Type 1 dimensions everywhere | accepted |
| [0007](0007-filter-chartevents-at-staging.md) | Filter `chartevents` to seven vital signs at staging | accepted |
| [0008](0008-security-objects-built-by-dbt.md) | Create the row-level security, audit triggers and public views with dbt | accepted |
