---
status: accepted
date: 2026-11-03
decision-makers: Nick Christoforakis
---


# Type 1 dimensions everywhere

## Context and Problem Statement

A dimension's attributes can change: a patient's recorded age group, a care unit's name or type. Should the warehouse keep the history of those changes (a slowly changing dimension of Type 2), or overwrite them (Type 1)?

## Decision Drivers

* MIMIC is published as versioned snapshots; within a version, nothing changes.
* Every build rebuilds the warehouse from scratch.
* The analytic questions ask about each stay as it happened, not about how attributes changed.

## Considered Options

* Type 1: a change overwrites the row; no history
* Type 2: a new row per version, with validity dates

## Decision Outcome

Chosen option: **Type 1 for every dimension**, because the source is a fixed snapshot with no changes to track, so history would add columns and joins for nothing.

### Consequences

* Good, because each dimension has one row per thing, and facts join on a single key.
* Good, because full rebuilds stay simple.
* Bad, because if the source did change, the old values would be lost: a past stay would show its unit's current name.

### What Type 2 would look like for `dim_care_unit`

Suppose a hospital renamed a unit, or reclassified it, say from "medical" to "mixed". With Type 2, `dim_care_unit` would keep one row per version of each unit, with `valid_from`, `valid_to` and `is_current` columns, and each version would get its own `care_unit_key`. `fact_icu_stay` would join to the version that was valid at the stay's `intime`, so a 2140 stay keeps the name it had then. A durable key, the same for every version of a unit, would let a query group all versions under the unit's current name. In dbt, a snapshot over the care-unit source would build the versions. Type 2 would be worth it once the warehouse loads data over time rather than rebuilding from one snapshot.

### Confirmation

Each dimension has a uniqueness test on its natural key (such as `hadm_id` or `care_unit`), which a second version of a row would fail.

## Pros and Cons of the Options

### Type 1

* Good, because it is simple and matches a snapshot source.
* Bad, because history is lost if the source changes.

### Type 2

* Good, because facts keep the attributes valid at the time.
* Bad, because it needs validity columns, a time-aware join and snapshot jobs, with nothing to track in this source.
