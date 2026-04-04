---
name: db-query
description: Run a SQL query against the PostgreSQL database. Use when the user wants to query, inspect, or debug database contents.
---

# Run a Database Query

Execute a SQL query against the project's PostgreSQL database. Use `$ARGUMENTS` for the query or a description of what data to find.

## Steps

1. If `$ARGUMENTS` is raw SQL, use it directly.
2. If `$ARGUMENTS` is a natural language description, write the appropriate SQL query first and show it to the user.

3. Run the query using the Postgres MCP tools if available (check for `mcp__postgres__query` or similar tools).

4. If no MCP tools are available, run via `psql`:
   ```bash
   psql "$DATABASE_URL" -c "<query>"
   ```
   If `DATABASE_URL` is not set, check `backend/.env` for the connection string.

5. Format results as a readable table.

## Safety

- For SELECT queries: run directly
- For INSERT/UPDATE/DELETE: show the query first and ask for confirmation before executing
- NEVER run DROP, TRUNCATE, or ALTER without explicit user confirmation
- Always use the production database with caution — confirm with the user which database to target

## Useful Tables

Reference the backend service files in `backend/src/services/` to understand the schema. Key tables include:
- `users` — user accounts
- `workouts` — workout records
- `workout_splits` — per-mile splits
- `friendships` — friend relationships
- `competitions` — competition data
