---
status: accepted
date: 2026-11-03
decision-makers: Nick Christoforakis
---


# Pseudonymize patients with a keyed HMAC, not a plain hash

## Context and Problem Statement

`dim_patient` needs a stable patient code that does not reveal the patient's `subject_id`: stable so a patient can be followed across admissions, unrevealing so a code in a report cannot be looked up. How should the code be made?

## Decision Drivers

* The same patient must always get the same code.
* Nobody without a secret may turn a code back into an ID (GDPR Art. 4(5)).
* A leaked secret must be replaceable.
* The secret must not be stored in the database.

## Considered Options

* HMAC-SHA256 of `subject_id` with a secret key kept outside the database
* A plain SHA-256 hash of `subject_id`
* A random code per patient, kept in a mapping table
* Keep `subject_id`

## Decision Outcome

Chosen option: **HMAC-SHA256 with a key kept outside the database**, because it is the only option that is stable, cannot be reversed without the key, and can be rotated by changing one secret.

The key is `ICU_HMAC_KEY`, kept in `.env` and in GitHub's secrets. dbt passes it to `dim_patient`'s transaction as a setting that ends with the transaction, and `privacy.pseudonymize()` computes the code. Keys shorter than 32 characters are refused.

### Consequences

* Good, because without the key nobody can compute the codes, so nobody can build a lookup table; someone who copies the whole database still cannot reverse them.
* Good, because rotating the key changes every code and nothing else, cutting every old link at once.
* Bad, because the key must be managed: if it is lost, the codes can never be matched to new loads; if it leaks, it must be rotated.
* Bad, because rotation breaks every join on old codes that was saved outside the warehouse.
* Bad, because dbt's local files contain the key, so they must never be published.

### Confirmation

`tests/test_security.py` recomputes every `subject_key` in Python from the key, and rebuilds `dim_patient` with a fresh key to show that every code changes and every other column does not. A dbt test fails if a code ever equals a plain hash.

## Pros and Cons of the Options

### Keyed HMAC

* Good, because it is stable, irreversible without the key, and rotatable.
* Bad, because the key needs managing.

### Plain SHA-256

* Good, because it needs no key.
* Bad, because MIMIC's IDs are 8-digit numbers: anyone can hash all 100 million in minutes and look every code up. It is not pseudonymization.

### Random code in a mapping table

* Good, because the codes carry no information at all.
* Bad, because the mapping table is the secret, and it would live in the database it is meant to be kept apart from, or need a separate store and syncing.

### Keep `subject_id`

* Bad, because every report and extract would carry the real ID.
