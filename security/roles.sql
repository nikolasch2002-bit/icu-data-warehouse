-- Roles for the warehouse, each with the least privilege it needs.
--
--   etl_writer     the pipeline: writes raw, staging and marts
--   analyst_micu   reads marts, read-only (row-level security in rls.sql
--   analyst_sicu   limits each to its own care unit)
--   auditor        nothing yet; audit.sql grants it the audit table
--
-- These are group roles (NOLOGIN): a real person would log in as their
-- own user and be made a member, e.g. grant analyst_micu to jane. Access
-- is then managed per group, and no password lives in this file.
--
-- Run as the role that owns the schemas and runs dbt (icu_user locally,
-- neondb_owner on Neon), after dbt has created raw, staging and marts.
-- Safe to run again: existing roles are kept and grants are repeated.

do $$
declare
    role_name text;
begin
    foreach role_name in array array[
        'etl_writer', 'analyst_micu', 'analyst_sicu', 'auditor'
    ]
    loop
        if not exists (select 1 from pg_roles where rolname = role_name) then
            -- Spelled out although most are the defaults, so the file
            -- states that none of these roles can log in, create roles or
            -- databases, or bypass row-level security.
            execute format(
                'create role %I nologin nosuperuser nocreatedb'
                ' nocreaterole nobypassrls',
                role_name
            );
        end if;
        -- Lets the owner switch into the role with set role, which is how
        -- the tests act as it. In Postgres 16 a role's creator cannot do
        -- that unless granted it, when it is not a superuser (Neon).
        -- inherit false: the owner does not silently gain the role's
        -- privileges, it has to switch.
        execute format(
            'grant %I to current_user with inherit false, set true', role_name
        );
    end loop;
end
$$;

-- etl_writer: writes every layer the pipeline builds. The loader writes
-- raw; dbt builds staging (views) and marts (tables).
--
-- The spec first gave etl_writer raw and staging only, but its own proof
-- for audit.sql has etl_writer insert, update and delete a dim_patient
-- row, which is in marts. The two cannot both hold, and dbt does write
-- marts, so etl_writer writes marts too. Recorded in docs/project-spec.md
-- under "Changes to the spec".
grant usage, create on schema raw, staging, marts to etl_writer;
grant select, insert, update, delete on all tables in schema raw, marts
to etl_writer;
grant select on all tables in schema staging to etl_writer;

-- Analysts: read marts, nothing else.
grant usage on schema marts to analyst_micu, analyst_sicu;
grant select on all tables in schema marts to analyst_micu, analyst_sicu;

-- The loader and dbt drop and recreate their tables on every run, which
-- loses the grants above. Default privileges apply them again to each new
-- table this role creates in these schemas.
alter default privileges in schema raw
grant select, insert, update, delete on tables to etl_writer;
alter default privileges in schema staging
grant select on tables to etl_writer;
alter default privileges in schema marts
grant select, insert, update, delete on tables to etl_writer;
alter default privileges in schema marts
grant select on tables to analyst_micu, analyst_sicu;
