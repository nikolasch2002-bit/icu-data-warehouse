# Lessons learned

> What building the ICU Data Warehouse taught, written to be reused on the next project. It has two readers: the author, as a reference and interview preparation, and an AI assistant (Claude Code), as working instructions from day one. Every lesson here comes from something that happened in this repository; the commit history and [Changes to the spec](project-spec.md#changes-to-the-spec) hold the details.

**How to use it on a new project.** Read sections 1 and 2 once. Copy section 5 into the new project's `CLAUDE.md` and adjust it. Go through the checklist in section 4 before writing code. Keep section 3 open while building: each rule there cost time to learn.

## 1. The concepts, in plain words

| Concept | What it is | Where this project uses it |
| --- | --- | --- |
| ELT | Load the raw data first, then transform it inside the database with SQL | The Python loader fills `raw`; dbt does the rest |
| Raw layer | An untouched copy of the source, every column as text | `raw.*`, with a SHA-256 per file in `raw.load_log` |
| Staging | One view per source table that fixes types, nulls and units, and changes nothing else | `stg_<module>__<table>` |
| Star schema | Facts (things that happened, with numbers) joined to dimensions (the things they describe) | `marts`: 5 facts, 8 dimensions |
| Grain | What one row of a fact means, in one sentence | "One row per ICU stay"; a move between units inside a stay is still one row |
| Surrogate key | An integer key the warehouse makes, instead of the source's ID | `patient_key`; `-1` for "outside an admission" |
| Type 1 dimension | A change overwrites the row; no history is kept | Every dimension |
| dbt | A tool that turns `select` files into tables and views, in the right order, with tests | `dbt/`, 235 checks |
| `ref()` and `source()` | How a dbt model names what it reads, so dbt knows the build order | Staging reads sources; marts read staging |
| CI | A server that builds and tests the project on every push | GitHub Actions, on a throwaway Neon branch |
| Least privilege | Each role gets only the access its job needs | `security/roles.sql` |
| Row-level security (RLS) | The database hides rows from a role, whatever query it runs | Analysts see only their care unit |
| Data minimization | Publish only what the purpose needs, in the least revealing form | `marts_public`: age bands, no IDs, no dates |
| Pseudonymization | Replace an ID with a code that cannot be reversed without a secret kept elsewhere | HMAC with a key outside the database |
| Audit trail | A log of who changed what, that the person logged cannot edit | `audit.change_log` |
| Separation of duties | Whoever is watched must not control the record | `etl_writer` can add audit rows, not read or delete them |
| Fail open / fail closed | What happens when a safety step is missed: access is given (open) or refused (closed) | Policies are created with the table, so a rebuild fails closed |
| Threat model (STRIDE) | A list of what could go wrong, what is done about it, and what remains | `docs/threat-model.md` |
| ADR | A short record of one decision and the options that lost | `docs/adr/` |
| Branch protection | The main branch accepts only changes that passed CI, through a pull request | `main` |

## 2. What worked: the way of working

- **A written spec is the source of truth.** Scope, grain, questions and proofs were fixed before any code. When the spec turned out to be wrong, the change went into a dated "Changes to the spec" table with the reason, and the old wording stayed visible. A deviation with a recorded reason is a strength; a silent one looks like a mistake.
- **Design before code.** The grain of every fact was written in one sentence first. The one design gap (no exact timestamps in the facts) showed up only when the queries were written. Next time: write the questions' SQL in outline against the model *before* building the model.
- **One step at a time, each ending in something visible:** a passing build, a query result, a green CI run, a URL.
- **Small commits whose messages say why.** The history became part of the portfolio.
- **Every claim has a proof that runs.** Each security feature has a test in CI. Each document was checked against the real system, and that check found real gaps (section 3).
- **A test must be able to fail.** After writing a test, break the thing it protects (switch RLS off, drop the trigger, plant a fake key) inside a transaction or a throwaway branch, and watch the test fail.
- **Check an important result a second way.** The KDIGO baselines were computed with window frames and again with plain subqueries; all 3,003 rows matched.
- **Say what is not done.** Small numbers are shown with their counts. Limits (creatinine-only staging, no retention period, no DPIA) are written down, not hidden.
- **The human decides clinical and design questions.** The assistant gives options and a recommendation, then waits: which vital signs, which stays an analyst sees, how the baseline is defined.
- **Explain-back.** Nothing stays in the repository that the author cannot explain out loud.

## 3. Pitfalls we hit, and the rule each one left

### SQL

| What happened | Rule |
| --- | --- |
| `last_value()` returned the current row | With only `order by`, the frame ends at the current row. Add `rows between unbounded preceding and unbounded following` |
| `fetch first 20 rows with ties` dropped tied rows | A tie means equal on *every* `order by` column. Pick the rows sorted by the one column, then sort for display outside |
| Two lab results shared a timestamp with different values, so "first" and "last" could change between runs | Every `order by` that picks a row needs a unique tie-breaker (an ID) |
| A "within 7 days" baseline was needed | `range between interval '7 days' preceding and current row` measures time, not rows; `exclude group` keeps same-time rows out |
| The facts had date and hour keys but no exact time | Keys are for grouping, timestamps for intervals. Keep both, and test that they agree |
| A macro pasted `a + b - c` into `floor(x / 10)` and divided only `c` | Wrap pasted expressions in parentheses. An `accepted_values` test caught it |
| `COLLATE` inside `BETWEEN` is not valid | Set the collation on the columns in a CTE |
| Column names that are keywords (`position`, `operation`) failed lint | Rename, or list the few worth keeping in the linter's config |

### dbt and Postgres

| What happened | Rule |
| --- | --- |
| dbt drops and recreates tables, which erased RLS policies, triggers and dependent views | Anything attached to a table is created by dbt, in a `post_hook`, in the same transaction. Setup that belongs to no table (roles, functions) runs before the build |
| Rebuilding only some tables silently dropped the views that read them | Build downstream too (`-s model+`), or build everything |
| A new table had no grants | `alter default privileges` grants each new table automatically |
| Re-running "grant select on all tables" gave back a column a hook had taken away | Grants must be safe to run again without undoing a later restriction; a test caught it |
| The secret key appeared in dbt's `manifest.json` | Pass secrets as a template string filled in at run time, never joined into the SQL text at parse time. Some local dbt files still hold it: never publish `dbt/target` or `dbt/logs` |
| The spec filtered RLS by a session setting | A user can change their own settings. A security boundary must be a role |
| A hosted Postgres owner is not a superuser | Test on the host, not only locally: `set role` needed an explicit grant there, and one role could not be switched into at all |
| An audit function could run as its owner or as the caller | As the caller, so the log records who it really was; the caller then needs insert on the log and nothing else |

### CI and GitHub

| What happened | Rule |
| --- | --- |
| A long-lived CI database branch expired and CI broke | One throwaway branch per run, deleted at the end even on failure, with an expiry as a fallback |
| Tests would have skipped quietly without a database | In CI, a missing prerequisite fails; it never skips |
| The pre-commit secret scan checks only staged changes | In CI, scan the pushed commits with full history, and prove it once with a planted fake key on a throwaway branch |
| Actions were pinned by tag | Pin to commit hashes; let Dependabot propose updates |
| The main branch accepted direct pushes | Protect it from the start: pull request, required check, merge commit so small commits survive |
| CI reads real rows on runners in another country | With real personal data that is a cross-border transfer. Use synthetic data in CI |
| The Makefile could not be run on Windows | Let CI prove it: run one target for real and dry-run the rest |

### Secrets

| What happened | Rule |
| --- | --- |
| `.gitignore` had no final newline, and an appended line merged into the one before | Check the file ends with a newline before appending, and verify with `git check-ignore` |
| The assistant must never see secret values | Deny the secrets files in the assistant's settings. Check a secret by presence or length. Compare parsed values by "matches: true/false", never by printing |
| A docs site was about to be published from a folder that holds a key | Publish one named file, and fail the build if it contains any secret |
| Passwords are rotated rarely, so nobody knows how | Rotate once on purpose, write the steps down, keep a log |

### Tooling on Windows

| What happened | Rule |
| --- | --- |
| `localhost` tried IPv6 first and made every connection slow | Use `127.0.0.1` |
| Backslash paths broke in Git Bash | Forward slashes in Git Bash |
| An SSH key with a passphrase blocked pushes | Run the ssh-agent and point git at Windows OpenSSH |
| Tools were not on PATH | Call them by module or full path (`python -m uv`, the `gh` install path), and write that into `CLAUDE.md` |

### Documents and the assistant's own mistakes

| What happened | Rule |
| --- | --- |
| A left-to-right diagram was too wide to read on GitHub | Render every diagram before committing; prefer top to bottom |
| The threat model's first draft assumed things | Check every claim against the real system. The check found six real gaps, all later fixed |
| A row count was reported wrong from memory | Report numbers from the command's output, not from memory |
| An existing config file was overwritten without being read | Look at a file before writing to its path; `git status` showing "modified" for a "new" file is the warning |
| Decision records were drafted by the assistant | Mark drafts as drafts. The author rewrites them before they count as accepted |

## 4. Checklist for the next project

1. **Write the spec:** what it proves, scope in and out, the questions it answers, each deliverable with the test that proves it.
2. **Check the data's licence** and write down where each kind of data may go: repository, hosted database, dashboard, AI chat.
3. **Set up the repository:** `.gitignore` (secrets, data, caches), `.env.example`, pre-commit with lint and a secret scan, a `CLAUDE.md` from section 5, the assistant's deny rules for secrets files.
4. **Set up CI before features:** lint, tests, a throwaway database per run, a secret scan, pinned actions. Then protect `main`.
5. **Write the data model:** the grain of each fact in one sentence. Outline the questions' SQL against it and look for what is missing.
6. **Build in layers,** each with tests: load, staging, model, questions.
7. **Add security with its proofs,** and decide early which objects the build tool recreates.
8. **Deploy early** to a real host, even with one page, so host-only problems appear soon.
9. **Write the documents against the real system:** architecture, threat model, decisions. Fix what the check finds.
10. **Finish:** README as the front page, a Makefile, a changes-to-the-spec table, and a pass through the explain-back rule.

## 5. Starter text for the next project's `CLAUDE.md`

Copy and adjust:

```markdown
## How we work

- The spec (`docs/project-spec.md`) is the source of truth. Implement the design; do not
  invent scope. If the spec is wrong, say so, and record the change with its reason.
- One step at a time. After each step, explain in plain words what changed and why,
  then ask before committing. Never commit, push or merge without my word.
- Clinical, domain and design decisions are mine. Give options and a recommendation,
  then wait.
- I must be able to explain every line. Keep changes small; comment non-obvious SQL.
- Small commits whose messages say why. Changes reach main through a pull request,
  merged with a merge commit after CI passes. Auto-merge stays off.
- Every claim needs a proof that runs. After writing a test, show that it can fail.
- Report numbers from command output. Say plainly what is not done or not verified.
- Never read or print secrets: check them by presence or length only.
- Read a file before overwriting it.
- Documents I must own (decision records, legal notes) are drafts until I rewrite them.
```

## 6. Questions I should be able to answer

- Why are staging models views and marts tables?
- What is the grain of each fact, and why is a unit change inside a stay still one row?
- Why surrogate keys, and what is the `-1` row for?
- Why does `last_value` need an explicit frame? What does `exclude group` do?
- Why is a plain hash of a patient ID not pseudonymization? What does rotating the key change?
- Why are the RLS policies created by dbt and not by a script? What does "fail open" mean here?
- Why does the audit trigger run as the caller? What can `etl_writer` do to the log?
- What can the dashboard's role read, and how is that proven?
- Why is HIPAA-de-identified data not automatically anonymous under the GDPR?
- What does CI do on a push, and why does each run get its own database branch?
- What would change with the full dataset, or with real patient data?
