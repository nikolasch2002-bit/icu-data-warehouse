-- Data minimization for the public dashboard.
--
-- The dashboard role (dashboard_ro) may read only the marts_public views,
-- never base tables. The views are added here together with the dbt marts.
--
-- Run as neondb_owner on Neon main; dashboard_ro exists only there.

-- Neon's setup gave dashboard_ro SELECT on every table created in public.
-- Remove it, so the only grants the role holds are the ones in this file.
alter default privileges for role neondb_owner in schema public
revoke select on tables from dashboard_ro;

revoke all on all tables in schema public from dashboard_ro;
