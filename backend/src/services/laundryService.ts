import crypto from "node:crypto";
import { PostgresService } from "./DbService.js";
import { pushTo } from "./deskPushService.js";
import {
  type LaundryEvent,
  type Machine,
  type MachineState,
  type MachineView,
  SAMPLE_S,
  newState,
  step,
  view,
} from "./laundryEngine.js";

const db = PostgresService.getInstance();

/**
 * Laundry on the desk: a smart plug (Shelly Plug US Gen4) under the washer
 * and one under the dryer send their power readings; laundryEngine.ts turns
 * them into "washing / spinning / drying / done" for the owner's desk box,
 * remote and phone.
 *
 * SECURITY MODEL
 *  - A plug key ("madl_" + 256 random bits) is a bearer secret for ONE plug
 *    of ONE person, made by that person in their own desk remote and shown
 *    once. Only its SHA-256 is stored. It authenticates exactly one route
 *    (POST /laundry/report) and can only add power readings for that one
 *    plug: it can't read anything back, not even its own machine's state.
 *  - What a plug sends is numbers (watts) and nothing else; anything else in
 *    the body is ignored, and the readings are bounded and counted.
 *  - The machine's state goes only to its owner: their own desk feed, their
 *    own remote, their own phone. Nobody else's box or remote ever sees it.
 *  - The owner can turn a plug off (revoke) any time; a new plug for the
 *    same machine replaces the old one.
 */

export const LAUNDRY_KEY_PREFIX = "madl_";
export const MACHINES: readonly Machine[] = ["washer", "dryer"];
const MAX_READINGS = 150; // one request: up to 5 min of readings (a plug catching up)
const TRACE_MAX = 4 * 3600 / SAMPLE_S; // a load's power trace, kept for tuning
const LOAD_DAYS = 60;
const LAST_SEEN_STAMP_MS = 60_000;

export function hashLaundryKey(key: string): string {
  return crypto.createHash("sha256").update(key, "utf8").digest("hex");
}

export function isWellFormedLaundryKey(key: string): boolean {
  return /^madl_[A-Za-z0-9_-]{43}$/.test(key);
}

export function isMachine(m: unknown): m is Machine {
  return m === "washer" || m === "dryer";
}

/** The readings a plug sent, cleaned: finite, 0..4000 W, at most 150. Else null. */
export function cleanReadings(body: unknown): { watts: number[]; on: boolean | null } | null {
  const b = body as { p?: unknown; on?: unknown; dt?: unknown } | null;
  if (!b || !Array.isArray(b.p) || b.p.length === 0 || b.p.length > MAX_READINGS) return null;
  if (b.dt !== undefined && b.dt !== SAMPLE_S) return null;
  const watts: number[] = [];
  for (const x of b.p) {
    if (typeof x !== "number" || !Number.isFinite(x) || x < 0 || x > 4000) return null;
    watts.push(Math.round(x * 10) / 10);
  }
  return { watts, on: typeof b.on === "boolean" ? b.on : null };
}

interface Stored {
  engine: MachineState;
  /** Readings (W) since the current load started, for tuning from real loads. */
  trace: number[];
  /** The relay, as the plug last said (false = someone switched it off). */
  on: boolean | null;
}

function load(raw: unknown, machine: Machine): Stored {
  const s = raw as Partial<Stored> | null;
  if (s && s.engine && s.engine.machine === machine) {
    return { engine: s.engine, trace: Array.isArray(s.trace) ? s.trace : [], on: s.on ?? null };
  }
  return { engine: newState(machine), trace: [], on: null };
}

// ─── plugs (the owner's own, from their desk remote) ───────────────────────

export interface LaundryPlug {
  id: string;
  machine: Machine;
  key_prefix: string;
  created_at: string;
  last_seen_at: string | null;
}

/** A new plug key for one of my machines; replaces that machine's old plug.
 *  The key is returned once and never stored. */
export async function createLaundryPlug(userId: string, machine: Machine): Promise<{ key: string; plug: LaundryPlug }> {
  const key = LAUNDRY_KEY_PREFIX + crypto.randomBytes(32).toString("base64url");
  const client = await db.getClient();
  try {
    await client.query("BEGIN");
    // What the old plug learned (this machine's typical loads) carries over.
    const old = await client.query<{ state: unknown }>(
      `UPDATE laundry_plugs SET revoked_at = NOW()
        WHERE user_id = $1 AND machine = $2 AND revoked_at IS NULL
        RETURNING state`,
      [userId, machine],
    );
    const prev = old.rows[0] ? load(old.rows[0].state, machine) : null;
    const fresh = newState(machine);
    if (prev) fresh.history = prev.engine.history;
    const ins = await client.query<LaundryPlug>(
      `INSERT INTO laundry_plugs (user_id, machine, key_hash, key_prefix, state)
       VALUES ($1, $2, $3, $4, $5::jsonb)
       RETURNING id, machine, key_prefix, created_at::text, last_seen_at::text`,
      [userId, machine, hashLaundryKey(key), key.slice(0, 9), JSON.stringify({ engine: fresh, trace: [], on: null })],
    );
    await client.query("COMMIT");
    return { key, plug: ins.rows[0] };
  } catch (e) {
    await client.query("ROLLBACK").catch(() => undefined);
    throw e;
  } finally {
    client.release();
  }
}

export async function revokeLaundryPlug(userId: string, plugId: string): Promise<boolean> {
  if (!/^[0-9a-f-]{36}$/i.test(plugId)) return false;
  const rows = await db.query(
    `UPDATE laundry_plugs SET revoked_at = NOW()
      WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL RETURNING id`,
    [plugId, userId],
  );
  return rows.length > 0;
}

/** "I emptied it": clears a waiting "done" (no more reminder). */
export async function markEmptied(userId: string, machine: Machine): Promise<boolean> {
  const client = await db.getClient();
  try {
    await client.query("BEGIN");
    const r = await client.query<{ id: string; state: unknown }>(
      `SELECT id, state FROM laundry_plugs
        WHERE user_id = $1 AND machine = $2 AND revoked_at IS NULL FOR UPDATE`,
      [userId, machine],
    );
    if (!r.rows[0]) {
      await client.query("ROLLBACK");
      return false;
    }
    const st = load(r.rows[0].state, machine);
    if (st.engine.stage === "done") {
      st.engine.stage = "idle";
      st.engine.doneAt = null;
      st.engine.doneLen = null;
      await client.query(`UPDATE laundry_plugs SET state = $2::jsonb WHERE id = $1`, [r.rows[0].id, JSON.stringify(st)]);
    }
    await client.query("COMMIT");
    return true;
  } catch (e) {
    await client.query("ROLLBACK").catch(() => undefined);
    throw e;
  } finally {
    client.release();
  }
}

// ─── readings in (a plug's key) ─────────────────────────────────────────────

/** The plug for a live key, else null. */
export async function resolveLaundryKey(key: string): Promise<{ plugId: string; userId: string; machine: Machine } | null> {
  if (!isWellFormedLaundryKey(key)) return null;
  const rows = await db.query<{ id: string; user_id: string; machine: string }>(
    `SELECT p.id, p.user_id, p.machine FROM laundry_plugs p JOIN users u ON u.user_id = p.user_id
      WHERE p.key_hash = $1 AND p.revoked_at IS NULL`,
    [hashLaundryKey(key)],
  );
  const r = rows[0];
  return r && isMachine(r.machine) ? { plugId: r.id, userId: r.user_id, machine: r.machine } : null;
}

/**
 * A plug's readings, oldest first, the last one taken just now. The server
 * stamps the times (a plug's own clock is never trusted). Runs the engine,
 * stores its state, keeps finished loads, and pushes "done" / "still in
 * there" to the owner's phone.
 */
export async function reportReadings(
  plug: { plugId: string; userId: string; machine: Machine },
  watts: number[],
  on: boolean | null,
  nowMs = Date.now(),
): Promise<void> {
  const now = nowMs / 1000;
  const events: LaundryEvent[] = [];
  let finished: { start: number; end: number; seconds: number; trace: number[] } | null = null;
  const client = await db.getClient();
  try {
    await client.query("BEGIN");
    const r = await client.query<{ state: unknown; stale: boolean }>(
      `SELECT state, (last_seen_at IS NULL OR last_seen_at < NOW() - ($2 || ' milliseconds')::interval) AS stale
         FROM laundry_plugs WHERE id = $1 AND revoked_at IS NULL FOR UPDATE`,
      [plug.plugId, String(LAST_SEEN_STAMP_MS)],
    );
    if (!r.rows[0]) {
      await client.query("ROLLBACK");
      return;
    }
    const st = load(r.rows[0].state, plug.machine);
    const n = watts.length;
    // Never step backwards in time (two requests landing out of order).
    const first = Math.max(now - (n - 1) * SAMPLE_S, (st.engine.lastAt ?? 0) + SAMPLE_S);
    for (let i = 0; i < n; i++) {
      const at = first + i * SAMPLE_S;
      if (at > now + 1) break;
      const wasRunning = st.engine.loadStart !== null;
      const evs = step(st.engine, at, watts[i]);
      if (!wasRunning && st.engine.loadStart !== null) st.trace = st.engine.win.map((p) => p[1]);
      else if (st.engine.loadStart !== null && st.trace.length < TRACE_MAX) st.trace.push(watts[i]);
      for (const e of evs) {
        events.push(e);
        if (e.kind === "done") {
          finished = { start: e.at - e.seconds, end: e.at, seconds: e.seconds, trace: st.trace };
          st.trace = [];
        }
      }
      if (st.engine.loadStart === null && !finished) st.trace = [];
    }
    st.on = on;
    await client.query(
      `UPDATE laundry_plugs SET state = $2::jsonb${r.rows[0].stale ? ", last_seen_at = NOW()" : ""} WHERE id = $1`,
      [plug.plugId, JSON.stringify(st)],
    );
    if (finished) {
      await client.query(
        `INSERT INTO laundry_loads (user_id, plug_id, machine, started_at, ended_at, seconds, trace)
         VALUES ($1, $2, $3, to_timestamp($4), to_timestamp($5), $6, $7)`,
        [plug.userId, plug.plugId, plug.machine, finished.start, finished.end, finished.seconds,
         finished.trace.map((x) => Math.round(x)).join(",")],
      );
    }
    await client.query("COMMIT");
  } catch (e) {
    await client.query("ROLLBACK").catch(() => undefined);
    throw e;
  } finally {
    client.release();
  }
  for (const e of events) await notify(plug.userId, e).catch(() => undefined);
}

const NAME: Record<Machine, string> = { washer: "Washer", dryer: "Dryer" };

/** The owner's phone (if they turned laundry notifications on). */
async function notify(userId: string, e: LaundryEvent) {
  if (e.kind === "done") {
    const min = Math.round(e.seconds / 60);
    await pushTo([userId], "laundry", {
      title: e.machine === "washer" ? "Washer's done 🧺" : "Dryer's done 🧺",
      body: e.machine === "washer"
        ? `Took ${min} min. Time to move it to the dryer.`
        : `Took ${min} min. Grab it before it wrinkles.`,
      tag: `laundry-${e.machine}`,
    });
  } else if (e.kind === "remind") {
    const min = Math.round(e.waiting / 60);
    await pushTo([userId], "laundry", {
      title: `Laundry's still in the ${e.machine}`,
      body: `It finished ${min} min ago.`,
      tag: `laundry-${e.machine}`,
    });
  }
}

// ─── what the owner sees ────────────────────────────────────────────────────

export interface LaundryStatus {
  washer: (MachineView & { plug_off: boolean }) | null;
  dryer: (MachineView & { plug_off: boolean }) | null;
}

/** The owner's machines right now; null when they have no laundry plugs. */
export async function getLaundryStatus(userId: string, nowMs = Date.now()): Promise<LaundryStatus | null> {
  const rows = await db.query<{ machine: string; state: unknown }>(
    `SELECT machine, state FROM laundry_plugs WHERE user_id = $1 AND revoked_at IS NULL`,
    [userId],
  );
  if (!rows.length) return null;
  const out: LaundryStatus = { washer: null, dryer: null };
  for (const r of rows) {
    if (!isMachine(r.machine)) continue;
    const st = load(r.state, r.machine);
    out[r.machine] = { ...view(st.engine, nowMs / 1000), plug_off: st.on === false };
  }
  return out;
}

/** The desk box's compact version (see mad/laundry.py): stage, minutes,
 *  minutes left (or -1), sure, how long a finished load took (or -1). */
export function boxLaundry(s: LaundryStatus | null) {
  if (!s) return null;
  const one = (v: LaundryStatus["washer"]) =>
    v ? { s: v.plug_off ? "offline" : v.stage, m: v.minutes, l: v.left ?? -1, ok: v.sure ? 1 : 0, t: v.took ?? -1 } : null;
  return { w: one(s.washer), d: one(s.dryer) };
}

export async function listLaundryPlugs(userId: string): Promise<LaundryPlug[]> {
  return db.query<LaundryPlug>(
    `SELECT id, machine, key_prefix, created_at::text, last_seen_at::text
       FROM laundry_plugs WHERE user_id = $1 AND revoked_at IS NULL ORDER BY machine`,
    [userId],
  );
}

/** My last finished loads (no traces). */
export async function recentLoads(userId: string, limit = 10) {
  return db.query<{ machine: string; started_at: string; ended_at: string; seconds: number }>(
    `SELECT machine, started_at::text, ended_at::text, seconds
       FROM laundry_loads WHERE user_id = $1 ORDER BY ended_at DESC LIMIT $2`,
    [userId, Math.min(50, Math.max(1, limit))],
  );
}

/** Old loads go (their traces were only for tuning). */
export async function pruneLaundryLoads() {
  await db.query(`DELETE FROM laundry_loads WHERE ended_at < NOW() - INTERVAL '${LOAD_DAYS} days'`);
}
