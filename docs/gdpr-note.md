# GDPR note

> What the General Data Protection Regulation (Regulation (EU) 2016/679) asks of a system like this, and what this system does about each point. This is a portfolio note, not legal advice. Article numbers refer to the GDPR unless another law is named. Checked against the repository on 2026-11-03.

**The starting point.** The MIMIC-IV demo describes 100 patients of a hospital in Boston, de-identified under the US HIPAA rules and published openly under the ODbL. Whether the GDPR applies to it at all depends on where it is processed (Art. 3) and on whether it still counts as personal data (Art. 4(1), Recital 26). This note does not settle that question. It takes the cautious reading: it treats the data as personal health data, as a hospital's own warehouse would have to.

## 1. Health data is a special category (Art. 9)

**The law.** Data concerning health (Art. 4(15)) is one of the special categories in Art. 9(1), whose processing is prohibited unless one of the exceptions in Art. 9(2) applies. Member States may add conditions for health data (Art. 9(4)).

**This project.** Every table below `marts_public` holds health data: diagnoses, lab results, vital signs, dates of death. The design treats all of it as special-category data: it stays in the database, and only minimized views leave it (sections 4 and 5).

## 2. A lawful basis (Art. 6 and Art. 9(2))

**The law.** Processing needs a basis in Art. 6(1) and, for health data, an exception in Art. 9(2). For a research warehouse there are two realistic routes:

- **Public interest and research:** Art. 6(1)(e), a task carried out in the public interest, together with Art. 9(2)(j), processing necessary for scientific research. Both require a basis in Union or Member State law (Art. 6(3)), and Art. 9(2)(j) requires the safeguards of Art. 89(1).
- **Explicit consent:** Art. 6(1)(a) with Art. 9(2)(a). Consent can be withdrawn at any time (Art. 7(3)), after which the data may have to be erased. That makes consent a poor fit for a retrospective warehouse of past ICU stays, where most patients cannot be asked.

**This project.** The demo is used under its open licence, so no patient basis is needed here. A hospital would take the first route, under its national research law, and the safeguards below are the Art. 89(1) part of it.

## 3. Pseudonymized is not anonymous (Art. 4(5), Recital 26)

**The law.** Data is pseudonymized when it can no longer be attributed to a person "without the use of additional information", kept separately and protected (Art. 4(5)). Pseudonymized data is still personal data. Only anonymous data, where the person is not identifiable by any means "reasonably likely to be used", falls outside the GDPR (Recital 26).

**Why HIPAA-de-identified is not automatically GDPR-anonymous.** HIPAA's Safe Harbor method is a checklist: remove 18 kinds of identifier, such as names, record numbers and exact dates, and group ages above 89 (45 CFR 164.514(b)(2)). The GDPR's test is about risk, not a checklist: could anyone, with means reasonably likely to be used, single the person out or link the record to them? A de-identified dataset can pass the checklist and fail that test. In MIMIC, every record of a patient still carries the same `subject_id`, so a patient's whole history can be followed. Dates are shifted but keep their intervals. And a rare diagnosis or an unusual sequence of stays can still single someone out. Under the GDPR, such data is best treated as pseudonymized: still personal data.

**This project.** [`security/pseudonymize.sql`](../security/pseudonymize.sql) replaces `subject_id` with an HMAC-SHA256 `subject_key`. The key is the "additional information" of Art. 4(5). It is kept outside the database, in `.env` and GitHub's secrets, and reaches Postgres only for the length of one dbt transaction. A plain hash would not qualify: the 8-digit IDs could all be hashed and looked up. A test rebuilds the key column with a new key to prove that rotation changes every code and nothing else. The marts still hold `subject_id` for building the facts; the public views hold neither it nor `subject_key`.

## 4. Data minimization (Art. 5(1)(c), Art. 25)

**The law.** Personal data must be "adequate, relevant and limited to what is necessary" for the purpose (Art. 5(1)(c)), and systems must be built that way by default (Art. 25).

**This project.**

- **Staging** drops the free-text comments on lab results and keeps only 7 of the thousands of charted ICU items (the vital signs).
- **Public views** ([`marts_public`](../dbt/models/marts_public/)) hold no identifiers, no dates and no date of death; ages are in 10-year bands, lengths of stay rounded, and lab values only as quartiles per ICU day. The dashboard's role can read these views and nothing else ([`security/minimization.sql`](../security/minimization.sql)), which a test checks column by column.
- **Analysts** see only their own care unit's ICU stays, vitals and admissions' labs, through row-level security.
- **Analysts** cannot read `dim_patient`'s `subject_id`, MIMIC's patient ID; they keep the pseudonymous `subject_key` and the date of death, which mortality analyses need. The other dimensions are readable in full ([threat model](threat-model.md), I2).

## 5. Security of processing (Art. 32)

**The law.** Art. 32(1)(a) names pseudonymization and encryption as measures. Art. 32 also asks for confidentiality, integrity and a way to test that the measures work.

**This project.**

- **Pseudonymization:** section 3.
- **Encryption in transit:** Neon accepts only encrypted connections.
- **Least-privilege roles:** [`security/roles.sql`](../security/roles.sql).
- **Row-level security per care unit:** [`security/rls.sql`](../security/rls.sql).
- **An audit trail of every change to the dimensions:** [`security/audit.sql`](../security/audit.sql).
- **Testing the measures:** CI runs the security tests on every push, against a throwaway copy of the database.
- **Analysis of the risks:** the [threat model](threat-model.md) covers what remains.

## 6. Retention and purge (Art. 5(1)(e))

**The law.** Data may be kept identifiable no longer than the purpose needs (Art. 5(1)(e)). Research is an exception: data may be kept longer if the Art. 89(1) safeguards are in place.

**This project.** No retention period is set: the demo is open data, and the whole warehouse can be dropped and rebuilt from the CSVs in minutes. With real data, a retention period would be set when the project starts, and a purge job would drop the patient data when it ends, verified by a query that finds nothing left. That includes Neon's history of past states, which allows a point-in-time restore and so keeps deleted data for a while.

## 7. Impact assessment (Art. 35)

**The law.** A data protection impact assessment (DPIA) is required before processing "on a large scale" of special-category data (Art. 35(3)(b)). It describes the processing, its necessity, the risks to people, and the measures against them (Art. 35(7)).

**This project.** No DPIA was done, since the data is an open demo. A hospital warehouse would need one before loading any data. This repository already holds much of its content: the [architecture](architecture.md) describes the processing, the [spec](project-spec.md) its purpose and scope, and the [threat model](threat-model.md) the risks and measures.

## 8. Data-subject rights and research exemptions (Arts 11, 14, 15–21, 89(2))

**The law.** People have rights to access, rectify, erase and object, among others (Arts 15–21). Research gets some exemptions:

- **Information:** need not be given where that would take disproportionate effort (Art. 14(5)(b)).
- **Erasure:** does not apply where it would seriously impair the research (Art. 17(3)(d)).
- **Access, rectification, restriction and objection:** Union or Member State law may limit these for research (Art. 89(2)).
- **Unidentifiable people:** where the controller cannot identify a person, it need not collect extra information only to comply, and Arts 15–20 apply only if the person provides information that identifies them (Art. 11).

**This project.** The warehouse cannot link a record to a person: MIMIC's IDs map to nothing outside MIMIC, and dates are shifted. Art. 11 is therefore the relevant article. A hospital warehouse would keep the link to its patient records, so it would need a process for access and objection requests, limited only as far as its national research law allows.

## 9. Transfers out of the EU (Chapter V, Arts 44–49)

**The law.** Personal data may leave the EU/EEA only to a country with an adequacy decision (Art. 45), or with appropriate safeguards such as standard contractual clauses (Art. 46). Transfers to US companies certified under the EU–US Data Privacy Framework rely on the Commission's 2023 adequacy decision for that framework.

**This project.**

- **Where the data lives:** the source is a US hospital's data, published by PhysioNet in the US. The warehouse runs on Neon in AWS `eu-central-1` (Frankfurt), so the data at rest is in the EU.
- **The dashboard,** on Streamlit Community Cloud, a US service, receives only the minimized public views.
- **GitHub** holds only code.
- **CI does move data out of the EU:** GitHub's runners connect to a copy of the warehouse during tests and read rows from it.

With real data, that last point would be an Art. 44 transfer. The fix is to run CI on synthetic or de-identified data, as the [threat model](threat-model.md) recommends, and to have a data processing agreement (Art. 28) with every provider that processes it.

## Summary

| Article | What it asks | Where this project answers it |
| --- | --- | --- |
| Art. 9 | Health data is a special category | Section 1; everything below `marts_public` treated as such |
| Arts 6, 9(2), 89(1) | A lawful basis, with research safeguards | Section 2; the safeguards are `security/` |
| Art. 4(5), Recital 26 | Pseudonymization, and how it differs from anonymization | [`pseudonymize.sql`](../security/pseudonymize.sql), with a key-rotation test |
| Arts 5(1)(c), 25 | Data minimization, by design | Staging filters; [`marts_public`](../dbt/models/marts_public/) views; [`minimization.sql`](../security/minimization.sql) |
| Art. 32 | Security of processing | Roles, RLS, audit, encryption in transit; [threat model](threat-model.md) |
| Art. 5(1)(e) | Storage limitation | Not implemented for the demo; section 6 describes the purge |
| Art. 35 | DPIA | Not done for the demo; architecture, spec and threat model are its inputs |
| Arts 11, 14–21, 89(2) | Data-subject rights and research exemptions | Section 8 |
| Arts 44–49 | Transfers out of the EU | Data at rest in Frankfurt; CI is the one transfer to fix for real data |
