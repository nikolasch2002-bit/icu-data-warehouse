-- Audit trail of changes to the dimensions.
--
-- Every insert, update and delete on a dim_* table writes a row to
-- audit.change_log: who, when, which table, what happened, and the row
-- before and after as jsonb. The trigger is attached by dbt
-- (dbt/macros/audit_trigger.sql), because dbt recreates the dimensions on
-- every build and a trigger is dropped with its table. This file creates
-- what the trigger needs, so it runs before dbt, after roles.sql.
--
-- What it catches: the dimensions are rebuilt from staging by dbt, and
-- that rebuild is a new table, not row changes, so it is not logged (its
-- record is the git history of the models). A row changed by hand between
-- builds, an out-of-band edit, is what the trail records.
--
-- Reads: a trigger only sees writes. Logging who read what needs the
-- pgaudit extension (per-role, per-table read logging) or log_statement =
-- 'all' (every statement into the server log). Both are server settings;
-- on Neon they are managed by Neon, so neither is turned on here.
--
-- Safe to run again.

create schema if not exists audit;

create table if not exists audit.change_log (
    change_id bigint generated always as identity primary key,
    changed_at timestamptz not null default now(),
    -- The role in effect (e.g. etl_writer) and the user who logged in. They
    -- differ when a person logs in as themselves and acts through a role.
    role_name text not null default current_user,
    login_name text not null default session_user,
    table_name text not null,
    change_type text not null,
    old_row jsonb,
    new_row jsonb
);

-- Runs as the role making the change (not security definer), so
-- current_user above records who it was. That role therefore needs
-- insert on the log, but nothing else: it cannot read, change or delete
-- what is already there.
create or replace function audit.log_change()
returns trigger
language plpgsql
as $$
begin
    insert into audit.change_log (table_name, change_type, old_row, new_row)
    values (
        tg_table_schema || '.' || tg_table_name,
        tg_op,
        -- old does not exist for an insert, new not for a delete.
        case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
        case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end
    );
    -- The return value of an after trigger is ignored.
    return null;
end
$$;

-- Nobody reads the log but the auditor; only the pipeline, the one role
-- that writes the dimensions, may add to it.
revoke all on schema audit from public;
revoke all on audit.change_log from public;
grant usage on schema audit to auditor, etl_writer;
grant select on audit.change_log to auditor;
grant insert on audit.change_log to etl_writer;
