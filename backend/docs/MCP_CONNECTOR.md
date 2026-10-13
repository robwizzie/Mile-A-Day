# MCP database connector

Lets Claude (Claude Code, and optionally claude.ai) read and edit the production database for
the people listed in `MCP_ALLOWED_USERS`, from anywhere, without a database URL on anyone's
machine. Code: `src/mcp/`. Check: `scripts/mcp-check.mjs` (in CI).

```
Claude ──POST /mcp──► 401 + where to sign in
   │
   ├─ /register            Claude Code registers itself (loopback redirect only)
   ├─ /authorize           parks the request, sets a browser-binding cookie,
   │                       sends the browser to mileaday.run/admin/connect
   │      └─ Sign in with Apple (the admin dashboard's own Services ID and return URL)
   │      └─ form POST /oauth/apple/callback  → cookie + nonce + Apple signature + pinned Apple ID
   ├─ /token               code (PKCE S256) → 1-hour access token + rotating refresh token
   └─ POST /mcp            query (read role) · execute (write role) · audit_log
```

## Who gets in

`MCP_ALLOWED_USERS` is the whole list, as `<users.user_id>:<Apple sub>` pairs, in the host's env.
A sign-in succeeds only for an Apple ID pinned there, and it signs in as the user it's paired
with. That user must also still have `users.role = 'admin'` (`isUserAllowed`, oauth.ts). The
check runs at sign-in, at every refresh, and on every MCP request.

Neither the list nor the Apple-ID-to-user mapping comes from the database, because the
connector can edit rows. If they did, `UPDATE users SET role = 'admin'` or
`UPDATE users SET apple_sub = '<someone else>'` would let a stranger in as Dave.

**Clients.**

- **Claude Code:** registers itself, but only with a loopback redirect. A phished sign-in link
  then delivers its code to the victim's own machine, where the phisher has nothing listening.
- **claude.ai:** does not self-register. Its callback is shared by every claude.ai user, so a
  link from someone else's connector, signed into by Dave, could hand them Dave's access. It uses
  one pre-registered client (`mad-claude-ai`) whose secret is `MCP_CLAUDE_AI_CLIENT_SECRET`. That
  variable is optional: unset means Claude Code only.

## What Postgres enforces

| Role | Grants | Can | Cannot |
|---|---|---|---|
| `mad_mcp_ro` | `pg_read_all_data` | read every table | write anything |
| `mad_mcp_rw` | + INSERT/UPDATE/DELETE on public tables, USAGE on sequences; owns nothing | change rows, `nextval()` | DROP, ALTER, TRUNCATE, CREATE, `setval()` |

The write role does NOT get `pg_write_all_data`. That role also grants UPDATE on every sequence,
and `setval()` is never rolled back, not even by a dry run. One call could reset an id sequence
and break the app's inserts. Default privileges cover tables that later migrations create.

Neither role bypasses row-level security. All six `mcp_*` tables have RLS on and no policies,
so through the connector they read as empty and refuse writes. A session can't read token
hashes, plant a token, or erase the audit log; only the app's role (the owner) touches them.

`checkRoleBoundary` asks Postgres what each role can actually do, as an allow-list:

- any role membership other than `pg_read_all_data`
- superuser, BYPASSRLS, CREATEROLE, CREATEDB or REPLICATION
- owning a table, or being able to CREATE in `public`
- the read role being able to UPDATE
- being able to `setval()` a sequence
- an `mcp_*` table without RLS
- `track_counts` being off

Any of these refuses every statement. A pass is trusted for 5 minutes. This catches the app's
own `DATABASE_URL`, or an over-granted role, pasted into a connector variable.

## Statement safety

- **Only the right statement types, one per call.**
  - `query` runs SELECT, WITH, EXPLAIN, SHOW, VALUES or TABLE, in a READ ONLY transaction.
  - `execute` runs INSERT, UPDATE, DELETE, MERGE or WITH.
  - The first keyword is checked before anything is sent (`firstKeyword`). ALTER ROLE, DO
    blocks, LOCK, CALL, COPY and DDL never reach Postgres.
  - Everything runs through a cursor (one Parse/Bind/Execute), so Postgres rejects
    `UPDATE …; COMMIT;`.
- **Dry run by default, counted by Postgres.** "Rows changed" is the difference in
  `pg_stat_xact_user_tables` before and after the statement, per table. That includes rows
  touched by data-modifying CTEs, `ON DELETE CASCADE` and triggers, all of which the statement's
  own row count misses.
- **Token-confirmed commit.**
  - A dry run that changes something returns a `confirm_token`: an HMAC over the caller, the
    exact SQL and the per-table changes, valid 10 minutes, keyed per process (a deploy just
    means dry-running again).
  - `commit=true` re-runs the statement and commits only if the token matches what it changed
    this time. A different statement, or data that moved since the dry run, rolls back.
  - A statement that changes nothing can't be committed at all.
- **Audit first.** The app's role writes the `mcp_audit_log` row before the statement runs; with
  no audit row, nothing runs. The row records per-table `changes`.
  - Sign-ins, refused sign-ins and refresh-token alarms go in the same RLS-protected table, not
    `error_log` (which the write role can delete from).
  - The `audit_log` tool shows the head and tail of long statements, so padding one with a
    comment can't hide its end.
- **Bounded.**
  - Statement timeout: 15s for reads, 8s for writes, which hold row locks. Lock timeout: 3s.
  - A hard 25s deadline closes the connection.
  - A byte meter on the socket cuts the connection past 8 MB, so no result can fill the API's
    memory. Without it, `SELECT repeat('x', 1000000) FROM generate_series(1, 201)` added
    262 MB.
  - 2 connections per role.
- **A fresh session every call.** Connections are destroyed after each call, so nothing a
  statement leaves on its session (advisory locks, temp tables, `SET`) outlives it.

### Never do these in this code

- **`query_timeout` on these pools.** node-pg's timer expects a query callback that a cursor never
  sets, so it throws (uncaught) 30s after every call and takes the API process down.
- **A plain `Cursor`.** pg-cursor has no COPY handlers, and node-pg calls them from its socket
  listener, so `COPY … TO STDOUT` through a plain cursor kills the process. Use `SafeCursor`.
- **A checked-out client without an `error` listener.** A dropped connection then crashes the
  process (`connect()` adds one).

## Tokens

Codes, access tokens and refresh tokens are random, opaque, and stored only as SHA-256. Nothing
is signed, so there's no signing key to configure or rotate.

| | Lifetime |
|---|---|
| Sign-in request (`/authorize` → callback) | 10 min, single use, bound to the browser cookie |
| Authorization code | 2 min, single use |
| Access token | 1 hour |
| Sign-in (grant) | 30 days from sign-in, however often it refreshes |

Refresh tokens rotate, and the check is made under a row lock. Presenting a used one more than
60 seconds after it was used revokes the whole sign-in and writes a `refresh_reuse` audit row.
The 60-second grace covers two Claude sessions refreshing one stored login at the same moment.

## Known residual risk

The Apple id_token passes through JavaScript on mileaday.run, the same as the admin dashboard's
own sign-in. A script running on that origin could request a token carrying an attacker's nonce,
for example through a future XSS bug. Closing that would need a dedicated Apple Services ID whose
only return URL is the backend's (`response_mode=form_post`), so the token never touches website
JavaScript. That change is in the Apple Developer portal.

## Setup

1. **Roles (once, from the Mac, as the tables' owner or a superuser):**
   `psql "$PROD_OWNER_URL" -v ro_pw="$(openssl rand -hex 24)" -v rw_pw="$(openssl rand -hex 24)" -f backend/scripts/mcp-db-roles.sql`.
   The last table it prints must be all `f`, except `can_update_users` for `mad_mcp_rw`.
2. **Coolify env (backend):**
   - `MCP_ALLOWED_USERS`: `<user_id>:<apple_sub>` pairs, comma-separated.
     `SELECT username, user_id || ':' || apple_sub FROM users WHERE role = 'admin'` prints them.
   - `MCP_DATABASE_URL_RO`, `MCP_DATABASE_URL_RW`: `DATABASE_URL` with the role user and password.
   - Optional: `MCP_CLAUDE_AI_CLIENT_SECRET` (`openssl rand -hex 32`) enables claude.ai.
   - Optional: `MCP_BASE_URL` (default `https://mad.mindgoblin.tech`) and `MCP_SIGNIN_PAGE_URL`
     (default `https://mileaday.run/admin/connect`).
3. **Deploy.** The boot log says `[mcp] connector on at …/mcp for N user(s)`, or why it's off.
4. **Connect (each person, once):**
   - **Claude Code:** `claude mcp add --transport http mad-db https://mad.mindgoblin.tech/mcp`,
     then `/mcp` to sign in.
   - **claude.ai** (if enabled): Settings → Connectors → Add custom connector, URL
     `https://mad.mindgoblin.tech/mcp`. Under Advanced settings, client ID `mad-claude-ai` and
     the secret.

## Turning it off

- **Everyone, now:** remove `MCP_ALLOWED_USERS` in Coolify and redeploy. Nothing is mounted.
- **One person:** remove their pair from the list and redeploy. Their next request is refused.
- **Every live session, without a deploy:** as the owner, run
  `UPDATE mcp_oauth_grants SET revoked_at = now() WHERE revoked_at IS NULL`. The next request is
  refused, and everyone signs in again.
