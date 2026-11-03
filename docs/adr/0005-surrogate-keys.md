---
status: accepted
date: 2026-11-03
decision-makers: Nick Christoforakis
---


# Surrogate integer keys on every dimension; facts never join on `subject_id`

## Context and Problem Statement

The facts must link to their dimensions. MIMIC offers natural keys: `subject_id`, `hadm_id`, `itemid`, ICD code plus version. Should the facts carry those, or keys the warehouse makes?

## Decision Drivers

* The patient's real ID should live in one place only.
* Some rows have no match in a dimension: about a quarter of lab results were taken outside any admission.
* Joins should be simple and cheap.
* A diagnosis is identified by two columns, the code and its ICD version.

## Considered Options

* An integer surrogate key per dimension, numbered with `row_number()` in natural-key order
* The natural keys from MIMIC
* Hash keys (a hash of the natural key, as `dbt_utils.generate_surrogate_key` makes)

## Decision Outcome

Chosen option: **an integer surrogate key on every dimension**. The facts carry only these keys. `subject_id` exists only in `dim_patient`, where the facts look up `patient_key` while they are built.

### Consequences

* Good, because the facts do not carry `subject_id`, so patient-level fact rows are already pseudonymous.
* Good, because a missing link has a real row to point to: `dim_admission` has an "outside an admission" row with key `-1`, so lab results taken outside an admission keep a non-null key instead of disappearing from joins.
* Good, because one integer column replaces two-column keys such as ICD code and version.
* Bad, because `row_number()` keys are stable only while the source does not change. A new patient in the source would renumber the keys after it. That is acceptable here, because every build rebuilds every table from scratch (Type 1, [ADR 0006](0006-type-1-dimensions.md)). Incremental loads would need hash keys or a key table.

### Confirmation

dbt tests check that every key is unique and not null and that every fact key exists in its dimension; `facts_keep_every_source_row` fails if a lookup ever drops a row.

## Pros and Cons of the Options

### Integer surrogate keys

* Good, because they are narrow, decoupled from the source, and allow an unknown member.
* Bad, because they renumber when the source changes.

### Natural keys

* Good, because there is nothing to build.
* Bad, because `subject_id` would be in every fact, and there is no key for "outside an admission".

### Hash keys

* Good, because they are stable across loads.
* Bad, because they are wide text columns, and a plain hash of `subject_id` would be reversible ([ADR 0004](0004-hmac-over-plain-hashing.md)).
