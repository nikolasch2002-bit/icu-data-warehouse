-- Row-level security (RLS) per care unit: each analyst role sees only the
-- ICU stays of its own care unit, and the vitals and labs that go with
-- them.
--
-- The policies are not created here but by dbt, in
-- dbt/macros/row_level_security.sql, as a post_hook on fact_icu_stay,
-- fact_vital_sign and fact_lab_result. dbt drops and recreates those
-- tables on every build, which erases their policies. Run from a separate
-- file after the build, a forgotten run would leave the new tables without
-- policies, and the analysts, who keep their select grant, would see every
-- care unit. In the post_hook, the policies are added in the same
-- transaction that creates each table, so it never exists without them.
-- See "Changes to the spec" in docs/project-spec.md.
--
-- Who sees what:
--   analyst_micu   stays whose first or last care unit is the MICU
--   analyst_sicu   stays whose first or last care unit is the SICU
--   both           vitals of their stays; every lab of an admission with
--                  one of their stays, including ward labs and labs from
--                  the admission's other ICU stays (the whole admission)
--   etl_writer     every row (the pipeline)
--   owner          every row: RLS does not apply to a table's owner
--
-- Why the role, not a setting: the spec allowed filtering on a session
-- setting such as current_setting('app.care_unit'). Any user can change
-- their own settings with set, so a setting cannot be a security boundary.
-- The policies are attached to roles, which only an administrator grants.
--
-- The proof is tests/test_security.py. This query lists the policies in
-- place, to inspect them by hand:

select
    tablename,
    policyname,
    roles,
    cmd,
    qual
from pg_policies
where schemaname = 'marts'
order by tablename asc, policyname asc;
