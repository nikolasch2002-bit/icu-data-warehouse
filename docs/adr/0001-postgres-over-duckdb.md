---
status: accepted
date: 2026-11-03
decision-makers: Nick Christoforakis
---


# Use PostgreSQL, hosted on Neon, rather than DuckDB

## Context and Problem Statement

The warehouse needs a database that a public dashboard can read over the internet, that can show a real security layer (roles, row-level security, an audit trigger), and that CI can test against without touching the copy the dashboard reads. It must be free at this project's size. Which database?

## Decision Drivers

* Security features in the database itself: roles, `GRANT`, row-level security, triggers.
* A hosted copy the dashboard can reach, with a free tier that does not pause the project.
* Throwaway copies for CI, so a broken model never reaches the dashboard's data.
* Plain SQL that any analytics team would recognise.

## Considered Options

* PostgreSQL: Docker locally, Neon as the host
* DuckDB, locally, with MotherDuck as a host
* Supabase (hosted PostgreSQL)

## Decision Outcome

Chosen option: **PostgreSQL 16, in Docker locally and on Neon as the host**, because it is the only option that offers every security feature the spec asks for and gives CI a fresh database branch per run.

### Consequences

* Good, because roles, RLS policies and triggers are native, so `security/` is plain SQL with no extra service.
* Good, because a Neon branch is a full copy of `main` in seconds: CI builds and tests on its own branch, then deletes it.
* Good, because the same Postgres runs locally and on Neon, so a model behaves the same in both.
* Bad, because Postgres stores data by row, which is slower than a columnar engine for large analytical scans. That does not matter for 100 patients; the full dataset would need partitioning and indexes.
* Bad, because Neon's free compute scales to zero when idle, so the first query after a pause waits a few seconds.

### Confirmation

CI creates a Neon branch on every push and runs the full chain against it; `tests/test_security.py` proves the roles, RLS and audit trigger on that branch.

## Pros and Cons of the Options

### PostgreSQL on Neon

* Good, because it has roles, row-level security and triggers.
* Good, because branches give CI a throwaway database.
* Bad, because it is a row store.

### DuckDB with MotherDuck

* Good, because it is columnar and very fast for analytics, with nothing to install.
* Bad, because it is an embedded, single-process database without roles or row-level security, so the security layer could not be built in it.
* Bad, because a public dashboard would need a hosted service on top (MotherDuck).

### Supabase

* Good, because it is also PostgreSQL, with the same security features.
* Bad, because its free projects pause after a week without activity, which would take the public dashboard down.
