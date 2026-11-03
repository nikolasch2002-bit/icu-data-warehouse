---
status: accepted
date: 2026-11-03
decision-makers: Nick Christoforakis
---


# Only the open demo data ever reaches anything deployed

## Context and Problem Statement

MIMIC-IV comes in two forms. The Clinical Database Demo v2.2 has 100 patients, needs no credentialing and is published under the ODbL. The full database has hundreds of thousands of patients and needs PhysioNet credentialing and a signed data use agreement, which forbids hosting it publicly and sharing it with online AI tools. Both have the same schema. Which data may the deployed system use?

## Decision Drivers

* The dashboard is public.
* The full database's data use agreement forbids public hosting and online AI tools.
* The project is built with an AI assistant.
* The same models should work on both, so the full data could be used later.

## Considered Options

* The demo everywhere; the full data, if obtained, only on an encrypted laptop
* The full data in the warehouse, with only aggregates on the dashboard
* The demo only, with no plan for the full data

## Decision Outcome

Chosen option: **the demo everywhere that is deployed or shared**, meaning the repository, Neon, CI, the dashboard and any AI chat. The full data, if obtained, stays on an encrypted laptop and is used only to test performance at scale.

### Consequences

* Good, because the dashboard can be public and the data can be discussed with an AI assistant without breaching any agreement.
* Good, because the schema is the same, so every dbt model runs unchanged on the full data.
* Good, because it is a clear compliance line: the deployed system only ever touches open data.
* Bad, because 100 patients make small groups: percentages are noisy, and the queries and dashboard must show the counts behind them.
* Bad, because the demo cannot show performance work at scale, such as partitioning or incremental models.

### Confirmation

The loader reads only `data/mimic-iv-demo/`, which is gitignored; `CLAUDE.md` and the spec state the rule for every contributor, human or AI.

## Pros and Cons of the Options

### Demo everywhere, full data on the laptop only

* Good, because it stays within both licences.
* Bad, because scale is not demonstrated in the deployed system.

### Full data in the warehouse, aggregates on the dashboard

* Good, because results would be clinically meaningful.
* Bad, because the warehouse would hold credentialed data on a hosted service, against the agreement, and CI and AI tools could not touch it.

### Demo only

* Good, because it is the simplest.
* Bad, because it closes the door on testing at scale later.
