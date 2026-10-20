/**
 * MCP database connector — the database side.
 *
 * Safety is enforced by POSTGRES, not by this file and not by the model:
 *   read role   pg_read_all_data                    -> cannot write at all
 *   write role  + INSERT/UPDATE/DELETE on tables,   -> edits rows; DROP, ALTER and
 *               USAGE (not UPDATE) on sequences,       TRUNCATE need ownership, and
 *               owns nothing                           setval() needs sequence UPDATE
 *   (backend/scripts/mcp-db-roles.sql. Not pg_write_all_data: that includes
 *   sequence UPDATE, and setval() is never rolled back — not even by a dry run.)
 * Neither bypasses row-level security, so neither can see or touch the mcp_*
 * tables (tokens, audit log). `checkRoleBoundary` refuses to run anything if a
 * role turns out to be stronger than that — e.g. the app's own URL pasted in.
 *
 * What this file adds on top:
 *   - only statement types the tool is for (reads: SELECT…; writes: INSERT,
 *     UPDATE, DELETE, MERGE, WITH), and exactly one per call (a cursor is one
 *     Parse/Bind/Execute), so `UPDATE …; COMMIT;`, ALTER ROLE, DO blocks and
 *     COPY never reach Postgres;
 *   - a fresh connection per call with a hard byte cap and deadline, so no
 *     statement can exhaust the live API's memory, hang a request, or leave
 *     session state behind;
 *   - a write commits only with the confirm token from a dry run of the SAME
 *     statement that changed the SAME rows per table, as counted by Postgres;
 *   - an audit row is written, by the app's own role, BEFORE anything runs.
 */
import crypto from "node:crypto";
import pg from "pg";
import Cursor from "pg-cursor";
import { PostgresService } from "../services/DbService.js";
import { logError } from "../services/errorLogService.js";

const appDb = PostgresService.getInstance();

export const MAX_ROWS = 200;
const MAX_CELL_CHARS = 2_000;
const MAX_OUTPUT_CHARS = 60_000;
const DRAIN_BATCH = 100;
/** Everything Postgres may send back for one call. Far above anything shown. */
export const MAX_RESULT_BYTES = 8 * 1024 * 1024;
/** Past both statement timeouts: only for what those cannot stop. */
const STATEMENT_DEADLINE_MS = 25_000;
const CONFIRM_TOKEN_TTL_S = 10 * 60;
const BOUNDARY_RECHECK_MS = 5 * 60 * 1000;

export interface Caller {
  userId: string;
  grantId: string;
}

type Kind = "read" | "write";

const pools: Partial<Record<Kind, pg.Pool>> = {};
const boundaryOkUntil: Partial<Record<Kind, number>> = {};
const urls: Partial<Record<Kind, string>> = {};

export function configureDatabase(readUrl: string, writeUrl: string) {
  urls.read = readUrl;
  urls.write = writeUrl;
}

function pool(kind: Kind): pg.Pool {
  const url = urls[kind];
  if (!url) throw new Error("MCP connector database is not configured");
  return (pools[kind] ??= new pg.Pool({
    connectionString: url,
    max: 2,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 10_000,
    application_name: `mad_mcp_${kind}`,
    // Writes hold row locks the app may be waiting on, so they get less time.
    statement_timeout: kind === "write" ? 8_000 : 15_000,
    // Wait at most 3s for a lock instead of queueing behind (and in front of)
    // the app's own traffic.
    lock_timeout: 3_000,
    idle_in_transaction_session_timeout: 30_000,
    // NOT query_timeout: node-pg's timer expects a query callback, which a
    // cursor never sets, so it would throw (uncaught — the whole API process)
    // 30s after every call. runOne carries its own deadline instead.
  }));
}

// ---- what may be sent at all ----

const READ_STATEMENTS = new Set(["select", "with", "explain", "show", "values", "table"]);
const WRITE_STATEMENTS = new Set(["insert", "update", "delete", "merge", "with"]);

/**
 * The statement's first keyword, lowercased, past whitespace, comments, empty
 * statements (Postgres drops a leading `;`) and opening parentheses.
 */
export function firstKeyword(sql: string): string {
  let s = sql;
  for (;;) {
    const t = s.replace(/^\s+/, "");
    if (t.startsWith(";") || t.startsWith("(")) {
      s = t.slice(1);
    } else if (t.startsWith("--")) {
      const nl = t.indexOf("\n");
      s = nl < 0 ? "" : t.slice(nl + 1);
    } else if (t.startsWith("/*")) {
      // Postgres block comments nest.
      let depth = 0;
      let i = 0;
      for (; i < t.length; i++) {
        if (t.startsWith("/*", i)) { depth++; i++; }
        else if (t.startsWith("*/", i)) { depth--; i++; if (depth === 0) break; }
      }
      s = t.slice(i + 1);
    } else {
      return (/^[A-Za-z]+/.exec(t)?.[0] ?? "").toLowerCase();
    }
  }
}

function assertStatementType(kind: Kind, sql: string) {
  const word = firstKeyword(sql);
  const allowed = kind === "read" ? READ_STATEMENTS : WRITE_STATEMENTS;
  if (!allowed.has(word)) {
    throw new Error(
      kind === "read"
        ? `query only runs SELECT, WITH, EXPLAIN, SHOW, VALUES or TABLE — not ${word.toUpperCase() || "that"}.`
        : `execute only runs INSERT, UPDATE, DELETE, MERGE or WITH — not ${word.toUpperCase() || "that"}.`,
    );
  }
}

/**
 * What the role behind each URL can actually do, asked of Postgres itself.
 * An allow-list: any role membership beyond pg_read_all_data is refused, as is
 * anything that would let a statement reach past rows. Returns the first
 * reason it is unsafe, or null. A pass is trusted for five minutes.
 */
export async function checkRoleBoundary(kind: Kind): Promise<string | null> {
  if ((boundaryOkUntil[kind] ?? 0) > Date.now()) return null;
  const rows = (
    await pool(kind).query(`
      SELECT current_user AS who, r.rolsuper, r.rolbypassrls, r.rolcreaterole, r.rolcreatedb, r.rolreplication,
             (SELECT coalesce(string_agg(b.rolname, ', ' ORDER BY b.rolname), '') FROM pg_roles b
               WHERE b.oid <> r.oid AND b.rolname <> 'pg_read_all_data'
                 AND pg_has_role(r.oid, b.oid, 'MEMBER')) AS extra_roles,
             (SELECT count(*)::int FROM pg_class c
               WHERE c.relowner = r.oid AND c.relnamespace = 'public'::regnamespace) AS owned,
             has_table_privilege('public.users', 'UPDATE') AS can_update,
             has_schema_privilege('public', 'CREATE') AS can_create,
             (SELECT count(*)::int FROM pg_class
               WHERE relnamespace = 'public'::regnamespace AND relkind = 'r'
                 AND (relname LIKE 'mcp\\_%' OR relname LIKE 'coach\\_mcp\\_%')
                 AND NOT relrowsecurity) AS unprotected,
             current_setting('track_counts')::boolean AS track_counts,
             -- CASE, not AND: the planner may test a non-sequence first, and that errors.
             (SELECT count(*)::int FROM pg_class
               WHERE relnamespace = 'public'::regnamespace
                 AND CASE WHEN relkind = 'S' THEN has_sequence_privilege(oid, 'UPDATE') END) AS settable_sequences
        FROM pg_roles r WHERE r.rolname = current_user`)
  ).rows;
  const r = rows[0];
  const problem = !r
    ? "role not found"
    : r.rolsuper
      ? `${r.who} is a superuser`
      : r.rolbypassrls
        ? `${r.who} bypasses row-level security`
        : r.rolcreaterole || r.rolcreatedb || r.rolreplication
          ? `${r.who} can create roles or databases, or replicate`
          : r.extra_roles
            ? `${r.who} is a member of ${r.extra_roles} (only pg_read_all_data is allowed)`
            : r.owned > 0
              ? `${r.who} owns ${r.owned} table(s)`
              : r.can_create
                ? `${r.who} can create objects in schema public`
                : r.unprotected > 0
                  ? `${r.unprotected} mcp_* table(s) lack row-level security`
                  : kind === "read" && r.can_update
                    ? `${r.who} (read role) can write`
                    : kind === "write" && !r.track_counts
                      ? "track_counts is off, so changed rows cannot be counted"
                      : r.settable_sequences > 0
                        ? `${r.who} can setval() ${r.settable_sequences} sequence(s) (pg_write_all_data?)`
                        : null;
  if (problem) {
    delete boundaryOkUntil[kind];
    logError("api", "MCP connector refused: database role is too powerful", { context: { kind, problem } });
    return problem;
  }
  boundaryOkUntil[kind] = Date.now() + BOUNDARY_RECHECK_MS;
  return null;
}

// ---- audit: the app's role writes it, before the statement runs ----

async function auditStart(caller: Caller, tool: string, statement: string, commit: boolean) {
  const rows = await appDb.query<{ id: string }>(
    `INSERT INTO mcp_audit_log (user_id, grant_id, tool, statement, commit_requested)
     VALUES ($1, $2, $3, $4, $5) RETURNING id`,
    [caller.userId, caller.grantId, tool, statement, commit],
  );
  return rows[0].id;
}

async function auditFinish(
  id: string,
  started: number,
  out: { rowCount: number | null; committed: boolean; error: string | null; changes?: TableChange[] },
) {
  await appDb
    .query(
      `UPDATE mcp_audit_log
          SET row_count = $2, committed = $3, error = $4, duration_ms = $5, changes = $6::jsonb, finished_at = now()
        WHERE id = $1`,
      [id, out.rowCount, out.committed, out.error, Date.now() - started, out.changes ? JSON.stringify(out.changes) : null],
    )
    .catch((err) => console.error("[mcp] audit finish failed", err));
}

/**
 * Sign-ins, refusals and token alarms go in the same RLS-protected table as
 * the statements — not error_log, which the write role can delete from.
 */
export async function recordAuthEvent(event: string, userId: string | null, detail: string): Promise<void> {
  await appDb
    .query(
      `INSERT INTO mcp_audit_log (user_id, tool, statement, finished_at) VALUES ($1, $2, $3, now())`,
      [userId, event, detail],
    )
    .catch((err) => console.error("[mcp] auth event not recorded", err));
}

// ---- running one statement ----

export interface StatementResult {
  columns: string[];
  rows: unknown[][];
  /** Rows the statement returned; null when a read was cut short. */
  rowCount: number | null;
  truncated: boolean;
  durationMs: number;
}

export interface TableChange {
  table: string;
  inserted: number;
  updated: number;
  deleted: number;
}

/**
 * pg-cursor has no COPY handlers, and node-pg calls them from its socket
 * listener: a `COPY … TO STDOUT` through a plain Cursor throws there, uncaught,
 * and takes the whole API process down. COPY is never sent (it is not an
 * allowed statement type); this cursor answers COPY messages harmlessly in case
 * one ever gets through anyway.
 */
export class SafeCursor extends Cursor {
  handleCopyInResponse(connection: { sendCopyFail(msg: string): void }) {
    connection.sendCopyFail("COPY is not supported by the MCP connector");
  }
  handleCopyData() {}
}

type Session = pg.PoolClient & { mcpOverflow?: boolean };

/**
 * A connection for one call. Destroyed afterwards (see release(true) below),
 * with an error listener so a dropped connection rejects the call instead of
 * crashing the API, and a byte meter on the socket: past MAX_RESULT_BYTES the
 * socket is cut, so no result — however many rows, however wide — can pile up
 * in the API's memory.
 */
async function connect(kind: Kind): Promise<Session> {
  const client = (await pool(kind).connect()) as Session;
  client.on("error", (err) => {
    if (!client.mcpOverflow) console.error(`[mcp] ${kind} connection lost: ${err.message}`);
  });
  // node-pg's socket. Internal, but it is the only place a size limit can sit
  // before node-pg buffers a whole message.
  const socket = (client as unknown as { connection: { stream: NodeJS.ReadableStream & { destroy(): void } } })
    .connection.stream;
  let received = 0;
  socket.on("data", (chunk: Buffer) => {
    received += chunk.length;
    if (received > MAX_RESULT_BYTES && !client.mcpOverflow) {
      client.mcpOverflow = true;
      socket.destroy();
    }
  });
  return client;
}

function explain(client: Session, err: unknown): Error {
  if (client.mcpOverflow) {
    return new Error(
      `Result too large: more than ${MAX_RESULT_BYTES / 1024 / 1024} MB came back. ` +
        "Select fewer or narrower columns (left(col, 200)), or add a LIMIT. Nothing was saved.",
    );
  }
  return err instanceof Error ? err : new Error(String(err));
}

function readBatch(cursor: SafeCursor, n: number): Promise<{ rows: unknown[][]; result?: pg.QueryResult }> {
  return new Promise((resolve, reject) =>
    cursor.read(n, (err, rows, result) => (err ? reject(err) : resolve({ rows: rows as unknown[][], result }))),
  );
}

/**
 * One statement, under a hard deadline. If Postgres has not answered in time
 * the connection is closed — the server then rolls the transaction back — and
 * the call fails; it can never hang a request on the live API.
 */
async function runOne(client: Session, sql: string, drain: boolean) {
  let timer: NodeJS.Timeout | undefined;
  const deadline = new Promise<never>((_, reject) => {
    timer = setTimeout(() => {
      // PoolClient hides end(); release(true) here would double-release in the caller.
      void (client as unknown as pg.Client).end().catch(() => {});
      reject(new Error(`No answer from Postgres in ${STATEMENT_DEADLINE_MS / 1000}s; the connection was closed and nothing was saved.`));
    }, STATEMENT_DEADLINE_MS);
  });
  try {
    return await Promise.race([readStatement(client, sql, drain), deadline]);
  } finally {
    clearTimeout(timer);
  }
}

/**
 * One statement through a cursor. A cursor is a single Parse/Bind/Execute, so
 * Postgres itself rejects a second statement. `drain` reads (and discards) past
 * the first MAX_ROWS to learn the full count — writes need it; reads do not.
 */
async function readStatement(client: Session, sql: string, drain: boolean) {
  const cursor = client.query(new SafeCursor(sql, undefined, { rowMode: "array" }));
  // On error the cursor has already re-synced the connection; close() is only
  // for the success path (calling it after an error waits for a second
  // ReadyForQuery that never comes).
  const first = await readBatch(cursor, MAX_ROWS + 1);
  const columns = (first.result?.fields ?? []).map((f) => f.name);
  let seen = first.rows.length;
  let result = first.result;
  let done = seen <= MAX_ROWS;
  if (drain) {
    while (!done) {
      const next = await readBatch(cursor, DRAIN_BATCH);
      seen += next.rows.length;
      result = next.result ?? result;
      done = next.rows.length < DRAIN_BATCH;
    }
  }
  await cursor.close();
  // A row-returning statement is counted by the rows that came back: the
  // command tag of a portal read in batches only counts the LAST batch.
  const tagged = typeof result?.rowCount === "number" ? result.rowCount : 0;
  return {
    columns,
    rows: first.rows.slice(0, MAX_ROWS),
    rowCount: done ? (columns.length ? seen : tagged) : null,
    truncated: first.rows.length > MAX_ROWS,
  };
}

/**
 * Postgres's own per-table insert/update/delete counters for this backend.
 * Read before and after the statement, inside one transaction, the difference
 * is exactly what the statement changed — including rows touched by
 * data-modifying CTEs, ON DELETE CASCADE and triggers, which the statement's
 * own row count misses (`WITH d AS (DELETE FROM users) SELECT 1` "returns 1
 * row"). A diff, not the raw value: the counters can also hold earlier
 * transactions on the backend until it flushes them, which it never does
 * mid-transaction.
 */
async function tableCounters(client: Session): Promise<Map<string, [number, number, number]>> {
  const rows = (
    await client.query<{ table: string; i: string; u: string; d: string }>(
      `SELECT relid::regclass::text AS table, n_tup_ins AS i, n_tup_upd AS u, n_tup_del AS d
         FROM pg_stat_xact_user_tables WHERE n_tup_ins + n_tup_upd + n_tup_del > 0`,
    )
  ).rows;
  return new Map(rows.map((r) => [r.table, [Number(r.i), Number(r.u), Number(r.d)]]));
}

function diffCounters(before: Map<string, [number, number, number]>, after: Map<string, [number, number, number]>) {
  const changes: TableChange[] = [];
  for (const [table, [i, u, d]] of after) {
    const [i0, u0, d0] = before.get(table) ?? [0, 0, 0];
    const c = { table, inserted: i - i0, updated: u - u0, deleted: d - d0 };
    if (c.inserted || c.updated || c.deleted) changes.push(c);
  }
  const total = (c: TableChange) => c.inserted + c.updated + c.deleted;
  return changes.sort((a, b) => total(b) - total(a) || a.table.localeCompare(b.table));
}

// ---- confirm tokens: a commit must repeat its own dry run exactly ----

// Per process: a deploy invalidates outstanding tokens, which only means dry-running again.
const confirmKey = crypto.randomBytes(32);

function confirmMac(issuedAt: number, caller: Caller, sql: string, changes: TableChange[]): string {
  return crypto
    .createHmac("sha256", confirmKey)
    .update(`${issuedAt}\n${caller.userId}\n${sql}\n${JSON.stringify(changes)}`)
    .digest("base64url")
    .slice(0, 32);
}

function confirmToken(caller: Caller, sql: string, changes: TableChange[]): string {
  const issuedAt = Math.floor(Date.now() / 1000);
  return `${issuedAt}.${confirmMac(issuedAt, caller, sql, changes)}`;
}

/** Same statement, same caller, same rows changed per table, within 10 minutes. */
function confirmTokenMatches(token: string, caller: Caller, sql: string, changes: TableChange[]): boolean {
  const [ts, mac] = token.split(".");
  const issuedAt = Number(ts);
  if (!Number.isInteger(issuedAt) || !mac) return false;
  const want = Buffer.from(confirmMac(issuedAt, caller, sql, changes));
  const got = Buffer.from(mac);
  return want.length === got.length && crypto.timingSafeEqual(want, got);
}

function confirmTokenAge(token: string): number | null {
  const issuedAt = Number(token.split(".")[0]);
  return Number.isInteger(issuedAt) ? Math.floor(Date.now() / 1000) - issuedAt : null;
}

// ---- the two tools ----

export async function runRead(sql: string, caller: Caller): Promise<StatementResult> {
  assertStatementType("read", sql);
  const problem = await checkRoleBoundary("read");
  if (problem) throw new Error(`Connector misconfigured (${problem}); nothing was run.`);
  const started = Date.now();
  const auditId = await auditStart(caller, "query", sql, false);
  const client = await connect("read");
  try {
    await client.query("BEGIN TRANSACTION READ ONLY");
    const out = await runOne(client, sql, false);
    await client.query("ROLLBACK");
    await auditFinish(auditId, started, { rowCount: out.rowCount ?? out.rows.length, committed: false, error: null });
    return { ...out, durationMs: Date.now() - started };
  } catch (raw) {
    const err = explain(client, raw);
    await client.query("ROLLBACK").catch(() => {});
    await auditFinish(auditId, started, { rowCount: null, committed: false, error: err.message });
    throw err;
  } finally {
    // Destroyed, never reused: nothing a statement leaves on its session
    // (advisory locks, temp tables, prepared statements, LISTEN) outlives it.
    client.release(true);
  }
}

export interface WriteResult extends StatementResult {
  committed: boolean;
  changed: number;
  changes: TableChange[];
  /** Dry runs that changed something: pass back as confirm_token to commit. */
  confirmToken: string | null;
}

export async function runWrite(
  sql: string,
  opts: { commit: boolean; confirmToken: string | null },
  caller: Caller,
): Promise<WriteResult> {
  assertStatementType("write", sql);
  if (opts.commit) {
    if (!opts.confirmToken) {
      throw new Error("commit=true needs the confirm_token from a dry run of this exact statement.");
    }
    const age = confirmTokenAge(opts.confirmToken);
    if (age === null || age < 0 || age > CONFIRM_TOKEN_TTL_S) {
      throw new Error("That confirm_token is invalid or more than 10 minutes old; dry-run the statement again.");
    }
  }
  const problem = await checkRoleBoundary("write");
  if (problem) throw new Error(`Connector misconfigured (${problem}); nothing was run.`);
  const started = Date.now();
  const auditId = await auditStart(caller, "execute", sql, opts.commit);
  const client = await connect("write");
  let changes: TableChange[] | undefined;
  try {
    await client.query("BEGIN");
    const before = await tableCounters(client);
    const out = await runOne(client, sql, true);
    changes = diffCounters(before, await tableCounters(client));
    const changed = changes.reduce((n, c) => n + c.inserted + c.updated + c.deleted, 0);
    let token: string | null = null;
    if (!opts.commit) {
      await client.query("ROLLBACK");
      token = changed > 0 ? confirmToken(caller, sql, changes) : null;
    } else if (changed === 0) {
      await client.query("ROLLBACK");
      throw new Error("Rolled back: the statement changed no rows, so there is nothing to commit.");
    } else if (!confirmTokenMatches(opts.confirmToken!, caller, sql, changes)) {
      await client.query("ROLLBACK");
      throw new Error(
        `Rolled back: this statement, or what it changes, is not what the dry run showed — it now changes ` +
          `${describeChanges(changes)}. Nothing was saved; dry-run it again.`,
      );
    } else {
      await client.query("COMMIT");
    }
    await auditFinish(auditId, started, { rowCount: changed, committed: opts.commit, error: null, changes });
    return { ...out, committed: opts.commit, changed, changes, confirmToken: token, durationMs: Date.now() - started };
  } catch (raw) {
    const err = explain(client, raw);
    await client.query("ROLLBACK").catch(() => {});
    await auditFinish(auditId, started, { rowCount: null, committed: false, error: err.message, changes });
    throw err;
  } finally {
    client.release(true);
  }
}

/** Recent connector activity, read with the app's role (the tools' roles cannot see it). */
export async function recentAudit(limit: number, writesOnly: boolean) {
  return appDb.query(
    `SELECT a.created_at, coalesce(u.username, a.user_id) AS who, a.tool, a.commit_requested, a.committed,
            a.row_count, a.changes, a.duration_ms, a.error,
            -- Head AND tail: padding a statement with a long comment cannot hide its end.
            CASE WHEN length(a.statement) <= 1200 THEN a.statement
                 ELSE left(a.statement, 600) || ' …[' || (length(a.statement) - 1200) || ' chars]… ' || right(a.statement, 600)
            END AS statement
       FROM mcp_audit_log a LEFT JOIN users u ON u.user_id = a.user_id
      WHERE NOT $2::boolean OR a.tool = 'execute'
      ORDER BY a.created_at DESC
      LIMIT $1`,
    [limit, writesOnly],
  );
}

export function describeChanges(changes: TableChange[]): string {
  if (!changes.length) return "no rows";
  return changes
    .map((c) =>
      `${c.table}: ` +
      [c.inserted && `${c.inserted} inserted`, c.updated && `${c.updated} updated`, c.deleted && `${c.deleted} deleted`]
        .filter(Boolean)
        .join(", "),
    )
    .join("; ");
}

export function errorText(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}

/** Rows as compact JSON, long cells clipped, the whole thing capped. */
export function renderResult(r: StatementResult): string {
  const clip = (v: unknown): unknown => {
    if (typeof v === "string" && v.length > MAX_CELL_CHARS) {
      return `${v.slice(0, MAX_CELL_CHARS)}…[+${v.length - MAX_CELL_CHARS} chars]`;
    }
    if (v && typeof v === "object" && !(v instanceof Date)) {
      const s = JSON.stringify(v);
      if (s.length > MAX_CELL_CHARS) return `${s.slice(0, MAX_CELL_CHARS)}…[+${s.length - MAX_CELL_CHARS} chars]`;
    }
    return v;
  };
  const rows = r.rows.map((row) => row.map(clip));
  let shown = rows.length;
  let body = JSON.stringify({ columns: r.columns, rows });
  while (body.length > MAX_OUTPUT_CHARS && shown > 1) {
    shown = Math.floor(shown / 2);
    body = JSON.stringify({ columns: r.columns, rows: rows.slice(0, shown) });
  }
  const count = r.rowCount === null ? `more than ${MAX_ROWS} rows` : `${r.rowCount} row(s)`;
  const note =
    shown < r.rows.length || r.truncated
      ? ` — showing the first ${shown}; add a LIMIT or narrow the WHERE to see the rest`
      : "";
  return `${count} in ${r.durationMs}ms${note}\n${body}`;
}

export async function closeMcpPools(): Promise<void> {
  await Promise.all(Object.values(pools).map((p) => p?.end()));
  delete pools.read;
  delete pools.write;
  delete boundaryOkUntil.read;
  delete boundaryOkUntil.write;
}
