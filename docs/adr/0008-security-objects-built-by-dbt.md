---
status: accepted
date: 2026-11-03
decision-makers: Nick Christoforakis
---


# Create the row-level security, audit triggers and public views with dbt

## Context and Problem Statement

The spec places the security layer in `security/*.sql` files. But dbt drops and recreates every marts table on every build, and Postgres drops a table's policies and triggers with it, along with any view that depends on it. Applied once from a file, the security layer would disappear on the next build. Where should these objects be created?

## Decision Drivers

* A table must never exist without its policies. If it did, analysts, who keep their select grant through default privileges, would briefly see every care unit: the system would fail open.
* The security objects must survive every rebuild, with no step that someone could forget.
* The SQL should stay readable and reviewable.

## Considered Options

* dbt hooks and models: policies and triggers as `post_hook`s, public views as dbt models
* Re-apply `security/*.sql` after every `dbt build`
* Build the facts incrementally, so dbt never drops them

## Decision Outcome

Chosen option: **dbt creates them**, because a `post_hook` runs in the same transaction that creates the table, so a rebuilt table never exists without its policies.

* Row-level security: `dbt/macros/row_level_security.sql`, a hook on the three per-stay facts.
* Audit trigger: `dbt/macros/audit_trigger.sql`, a hook on all of marts that acts on the `dim_*` tables.
* Public views: `dbt/models/marts_public/`, built after the marts.
* What does not belong to a table stays in `security/`: roles, grants, the audit log and its function, the pseudonymization function. These files run before `dbt build`, because the hooks depend on them.

### Consequences

* Good, because the system fails closed: if a hook fails, the build fails and the old table stays.
* Good, because one `dbt build` produces the whole secured warehouse.
* Bad, because the security layer is split between `security/` and `dbt/`, and `security/rls.sql` only explains and lists the policies.
* Bad, because order matters: `security/*.sql` must run before dbt, since the hooks name the roles and call the functions.

### Confirmation

`tests/test_security.py` checks after every build in CI that RLS is on for the three facts and that every dimension has its trigger. Switching RLS off in a test transaction makes an analyst see all 140 stays, which the tests catch. The deviation from the spec is recorded under [Changes to the spec](../project-spec.md#changes-to-the-spec).

## Pros and Cons of the Options

### dbt hooks and models

* Good, because the objects are created atomically with their tables.
* Bad, because the security SQL is split across two folders.

### Re-apply the files after each build

* Good, because all security SQL stays in `security/`.
* Bad, because between the build and the re-apply, or if someone forgets it, the tables have no policies: it fails open.

### Incremental facts

* Good, because tables would not be dropped.
* Bad, because it complicates every model to work around the security layer, and a full refresh would still drop them.
