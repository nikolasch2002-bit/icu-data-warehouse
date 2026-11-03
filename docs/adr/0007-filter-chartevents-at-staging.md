---
status: accepted
date: 2026-11-03
decision-makers: Nick Christoforakis
---


# Filter `chartevents` to seven vital signs at staging

## Context and Problem Statement

`chartevents` holds everything charted at the ICU bedside: vital signs, ventilator settings, scores, nursing notes and more, under thousands of item IDs. In the demo it has 669k rows; in full MIMIC-IV, hundreds of millions. The spec puts only vital signs in scope. Where should the rest be cut off, and which items count as vital signs?

## Decision Drivers

* Only vital signs are in scope.
* Every model downstream should see the same, already-correct values and units.
* The raw data should stay complete, so the choice can be changed later.

## Considered Options

* Filter at staging, in `stg_icu__chartevents`
* Load all of `chartevents` into a fact and filter in the queries
* Filter in the marts, in `fact_vital_sign`

## Decision Outcome

Chosen option: **filter at staging**. The view keeps seven items and converts temperature to °C, so every later model sees vital signs only, in one unit:

| Item ID | Vital sign | Unit |
| --- | --- | --- |
| 220045 | Heart rate | bpm |
| 220210 | Respiratory rate | breaths/min |
| 220277 | Oxygen saturation (pulse oximetry) | % |
| 220179 | Non-invasive blood pressure, systolic | mmHg |
| 220180 | Non-invasive blood pressure, diastolic | mmHg |
| 220181 | Non-invasive blood pressure, mean | mmHg |
| 223761 | Temperature, charted in °F, converted to °C | °C |

Why these seven: they are the standard bedside vital signs. Blood pressure uses the non-invasive cuff measurements; the mean is the one used for hypotension (below 65 mmHg).
### Consequences

* Good, because staging shrinks from 669k rows to 69,783, and every model downstream works on vitals only.
* Good, because the °F to °C conversion happens once, in one place.
* Good, because `raw.chartevents` keeps everything, so adding an item later is a one-line change in staging.
* Bad, because a new analysis that needs another item requires changing staging, not just writing a query.

### Confirmation

dbt tests on `stg_icu__chartevents` and `dim_chart_item` accept only these seven item IDs, and `dim_chart_item`'s item IDs must be unique.

## Pros and Cons of the Options

### Filter at staging

* Good, because downstream models are small and consistent.
* Bad, because widening the scope means changing staging.

### Everything in a fact

* Good, because any item is available to any query.
* Bad, because the fact would be mostly out-of-scope rows, and every query would have to filter and convert units itself.

### Filter in the marts

* Good, because staging would stay a plain typed copy.
* Bad, because the temperature conversion and the filter would sit in the fact, and staging would still carry 669k rows nobody uses.
