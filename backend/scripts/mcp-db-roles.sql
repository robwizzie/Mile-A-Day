-- Database roles for the MCP connector (backend/src/mcp). Run ONCE per
-- database, as the owner of the tables (DATABASE_URL's user) or a superuser —
-- for production, from the Mac (the only machine that can reach the prod database):
--
--   psql "$PROD_OWNER_URL" -v ro_pw="$(openssl rand -hex 24)" -v rw_pw="$(openssl rand -hex 24)" \
--        -f backend/scripts/mcp-db-roles.sql
--
-- Re-running is safe (it resets both passwords). Coolify then gets
--   MCP_DATABASE_URL_RO = DATABASE_URL with user mad_mcp_ro and ro_pw
--   MCP_DATABASE_URL_RW = DATABASE_URL with user mad_mcp_rw and rw_pw
--
-- The boundary is Postgres's, not the connector's:
--   mad_mcp_ro  pg_read_all_data                     -> reads everything, writes nothing
--   mad_mcp_rw  + INSERT/UPDATE/DELETE on tables,     -> edits rows. DROP, ALTER, TRUNCATE
--               USAGE on sequences, OWNS NOTHING        need ownership; setval() needs
--                                                       sequence UPDATE: all refused
-- Not pg_write_all_data: it also grants UPDATE on every sequence, and setval()
-- is never rolled back — not even by a dry run — so one call could reset an id
-- sequence and break the app's inserts.
-- Neither role bypasses row-level security, which is what hides the
-- connector's own mcp_* tables from it. The server re-checks all of this itself
-- (checkRoleBoundary) and refuses to run anything if a role is stronger.
-- Separate from the Mac-only claude_ro/claude_rw roles on purpose: revoking
-- one never touches the other. scripts/mcp-check.mjs runs this very file.

\set ON_ERROR_STOP on

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'mad_mcp_ro') THEN CREATE ROLE mad_mcp_ro LOGIN; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'mad_mcp_rw') THEN CREATE ROLE mad_mcp_rw LOGIN; END IF;
END $$;

ALTER ROLE mad_mcp_ro WITH LOGIN PASSWORD :'ro_pw' NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB NOREPLICATION;
ALTER ROLE mad_mcp_rw WITH LOGIN PASSWORD :'rw_pw' NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB NOREPLICATION;

-- Reads: every table, including ones created later.
GRANT pg_read_all_data TO mad_mcp_ro, mad_mcp_rw;

-- Writes: rows only, in schema public.
GRANT USAGE ON SCHEMA public TO mad_mcp_rw;
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO mad_mcp_rw;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO mad_mcp_rw;   -- nextval() for serial ids; not setval()
-- …and on tables later migrations create (they run as the owner of public.users).
SELECT tableowner AS owner FROM pg_tables WHERE schemaname = 'public' AND tablename = 'users' \gset
ALTER DEFAULT PRIVILEGES FOR ROLE :"owner" IN SCHEMA public GRANT INSERT, UPDATE, DELETE ON TABLES TO mad_mcp_rw;
ALTER DEFAULT PRIVILEGES FOR ROLE :"owner" IN SCHEMA public GRANT USAGE ON SEQUENCES TO mad_mcp_rw;

-- Undo anything broader a previous version (or a hand) may have granted.
SELECT format('REVOKE %I FROM %I', g.rolname, m.rolname)
  FROM pg_auth_members a
  JOIN pg_roles g ON g.oid = a.roleid
  JOIN pg_roles m ON m.oid = a.member
 WHERE m.rolname IN ('mad_mcp_ro', 'mad_mcp_rw')
   AND g.rolname <> 'pg_read_all_data' \gexec
REVOKE CREATE ON SCHEMA public FROM mad_mcp_ro, mad_mcp_rw;
SELECT format('GRANT CONNECT ON DATABASE %I TO mad_mcp_ro, mad_mcp_rw', current_database()) \gexec

-- What each role can actually do. Every column must read f (false), except
-- can_update_users for mad_mcp_rw. A t in can_create means PUBLIC still has
-- CREATE on schema public (Postgres < 15 default); the connector will refuse
-- to run until that is revoked.
SELECT r.rolname,
       r.rolsuper AS superuser,
       r.rolbypassrls AS bypasses_rls,
       (SELECT count(*) FROM pg_class c WHERE c.relowner = r.oid) > 0 AS owns_tables,
       has_table_privilege(r.rolname, 'public.users', 'UPDATE') AS can_update_users,
       has_schema_privilege(r.rolname, 'public', 'CREATE') AS can_create,
       -- CASE, not AND: the planner may test a non-sequence first, and that errors.
       EXISTS (SELECT 1 FROM pg_class c WHERE c.relnamespace = 'public'::regnamespace
                 AND CASE WHEN c.relkind = 'S' THEN has_sequence_privilege(r.rolname, c.oid, 'UPDATE') END) AS can_setval
  FROM pg_roles r
 WHERE r.rolname IN ('mad_mcp_ro', 'mad_mcp_rw')
 ORDER BY 1;
