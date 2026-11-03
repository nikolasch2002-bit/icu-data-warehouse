-- Data minimization for the public dashboard.
--
-- The dashboard connects as dashboard_ro and may read only the views in
-- marts_public, never a base table. The views themselves are dbt models
-- (dbt/models/marts_public): rebuilding a marts table drops the views
-- that depend on it, so dbt rebuilds them after the marts on every build.
-- What they leave out: every identifier (subject_id, subject_key, hadm_id,
-- stay_id), every date and time, the date of death, exact ages (10-year
-- bands instead), and insurance, language, race and marital status, which
-- no page uses. Lab values are published only as quartiles per day of
-- stay, never one patient's result.
--
-- A view reads its tables with its owner's rights, so dashboard_ro needs
-- no grant on marts at all. That also means row-level security, which
-- limits the analysts, does not limit the dashboard: the owner sees every
-- care unit, as a public overview should.
--
-- Run as the owner (icu_user locally, neondb_owner on Neon), before dbt
-- builds, like roles.sql. Safe to run again.

-- On Neon, dashboard_ro is a login role made in the console, with its
-- password there. Locally it does not exist; a stand-in without login
-- lets the grants and the tests run the same way.
do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'dashboard_ro') then
        create role dashboard_ro nologin nosuperuser nocreatedb nocreaterole
        nobypassrls;
    end if;
end
$$;

-- Neon's setup gave dashboard_ro select on every table created in public.
-- Remove it, so the only grants the role holds are the ones in this file.
-- neondb_owner exists only on Neon.
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'neondb_owner') then
        alter default privileges for role neondb_owner in schema public
        revoke select on tables from dashboard_ro;
    end if;
end
$$;

revoke all on all tables in schema public from dashboard_ro;

-- The public views, and nothing else.
create schema if not exists marts_public;
grant usage on schema marts_public to dashboard_ro;
grant select on all tables in schema marts_public to dashboard_ro;

-- dbt recreates the views on every build; default privileges grant
-- select on each new one.
alter default privileges in schema marts_public
grant select on tables to dashboard_ro;

-- Every dashboard query takes well under a second. Someone with the
-- role's password could still run slow queries to load the database; the
-- timeout ends any statement that runs longer than 15 seconds. It applies
-- to new sessions of the role.
alter role dashboard_ro set statement_timeout = '15s';
