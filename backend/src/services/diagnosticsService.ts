import { createHash } from "crypto";
import { PostgresService } from "./DbService.js";

const db = PostgresService.getInstance();

/**
 * MetricKit crash / hang reporting.
 *
 * The iOS app ships no third-party crash SDK, so MetricKit is the only
 * witness to a crash in the field: the OS delivers an `MXDiagnosticPayload`
 * on the next launch (up to a day later), the app trims it and POSTs it here,
 * and the admin dashboard groups the rows by `signature`.
 *
 * Everything here assumes the client is untrusted and possibly looping:
 *   - items are capped per request (`MAX_ITEMS_PER_REQUEST`) and per user per
 *     rolling day (`MAX_ROWS_PER_USER_PER_DAY`), under an advisory lock so
 *     two concurrent uploads can't both see room;
 *   - every payload is re-trimmed here, whatever the client already did, to
 *     `MAX_PAYLOAD_BYTES` — a call-stack tree is the one unbounded thing in it;
 *   - `client_id` is the client's own id for one diagnostic, so a retry after
 *     a lost response stores nothing twice.
 * The signature is computed HERE rather than on the phone, so the grouping
 * rule can change without waiting for an App Store release.
 */

export const DIAGNOSTIC_KINDS = [
  "crash",
  "hang",
  "cpu_exception",
  "disk_write_exception",
  "metrics",
] as const;
export type DiagnosticKind = (typeof DIAGNOSTIC_KINDS)[number];
const KIND_SET = new Set<string>(DIAGNOSTIC_KINDS);

/** A looping or broken client can't fill the table past this per user/day. */
export const MAX_ROWS_PER_USER_PER_DAY = 50;
/** Items beyond this in one request are rejected, not stored. */
export const MAX_ITEMS_PER_REQUEST = 25;
/** One stored payload, serialized. A trimmed crash tree is ~5-15KB. */
export const MAX_PAYLOAD_BYTES = 64 * 1024;
/** Rows older than this are deleted by `diagnostics.prune`. */
export const RETENTION_DAYS = 90;
/** Window the admin panel reads. */
export const OVERVIEW_DAYS = 14;

const MAX_STACK_DEPTH = 64;
const MAX_SIBLINGS = 3;
const MAX_STACKS = 2;

// ─── Trimming ────────────────────────────────────────────────────────

const str = (v: unknown, max: number): string | null => {
  if (typeof v === "string") return v.slice(0, max);
  if (typeof v === "number" && Number.isFinite(v)) return String(v).slice(0, max);
  return null;
};

const isObj = (v: unknown): v is Record<string, any> =>
  typeof v === "object" && v !== null && !Array.isArray(v);

/**
 * The only `diagnosticMetaData` keys worth keeping. An allowlist rather than
 * a passthrough: MetricKit grows keys every OS release, and anything stored
 * here is shown on an admin page — nothing new should reach it unreviewed.
 * `regionFormat` is deliberately absent (a locale is not a crash fact).
 */
const META_KEYS: Record<string, number> = {
  appVersion: 32,
  appBuildVersion: 32,
  osVersion: 64,
  deviceType: 64,
  platformArchitecture: 16,
  bundleIdentifier: 128,
  exceptionType: 16,
  exceptionCode: 32,
  signal: 16,
  terminationReason: 1000,
  virtualMemoryRegionInfo: 500,
  hangDuration: 32,
  totalCPUTime: 32,
  totalSampledTime: 32,
  writesCaused: 32,
  isTestFlightApp: 8,
  lowPowerModeEnabled: 8,
};

function trimMeta(meta: unknown): Record<string, unknown> {
  if (!isObj(meta)) return {};
  const out: Record<string, unknown> = {};
  for (const [key, max] of Object.entries(META_KEYS)) {
    const v = meta[key];
    if (typeof v === "boolean") out[key] = v;
    else {
      const s = str(v, max);
      if (s !== null) out[key] = s;
    }
  }
  // iOS 17+: the uncaught Objective-C exception, when there was one.
  if (isObj(meta.exceptionReason)) {
    const r = meta.exceptionReason;
    out.exceptionReason = {
      exceptionName: str(r.exceptionName, 128),
      className: str(r.className, 128),
      composedMessage: str(r.composedMessage, 500),
    };
  }
  return out;
}

type Frame = {
  binaryName?: string;
  binaryUUID?: string;
  offsetIntoBinaryTextSegment?: number;
  address?: number;
  sampleCount?: number;
  subFrames?: Frame[];
};

function trimFrames(frames: unknown, depth: number, siblings: number): Frame[] {
  if (!Array.isArray(frames) || depth <= 0) return [];
  return frames
    .filter(isObj)
    .sort((a, b) => (Number(b.sampleCount) || 0) - (Number(a.sampleCount) || 0))
    .slice(0, siblings)
    .map((f) => {
      const out: Frame = {};
      const name = str(f.binaryName, 128);
      if (name !== null) out.binaryName = name;
      const uuid = str(f.binaryUUID, 64);
      if (uuid !== null) out.binaryUUID = uuid;
      if (Number.isFinite(f.offsetIntoBinaryTextSegment))
        out.offsetIntoBinaryTextSegment = Number(f.offsetIntoBinaryTextSegment);
      if (Number.isFinite(f.address)) out.address = Number(f.address);
      if (Number.isFinite(f.sampleCount)) out.sampleCount = Number(f.sampleCount);
      const sub = trimFrames(f.subFrames, depth - 1, siblings);
      if (sub.length) out.subFrames = sub;
      return out;
    });
}

/**
 * Keeps the thread that matters: the attributed (crashed / hung) thread when
 * MetricKit marks one, else the first. A crash tree carries EVERY thread and
 * is most of a payload's size; the other threads almost never change the
 * diagnosis.
 */
function trimTree(tree: unknown, depth: number, siblings: number): unknown {
  if (!isObj(tree) || !Array.isArray(tree.callStacks)) return undefined;
  const stacks = tree.callStacks.filter(isObj);
  const attributed = stacks.filter((s) => s.threadAttributed === true);
  const chosen = (attributed.length ? attributed : stacks).slice(0, MAX_STACKS);
  return {
    callStackPerThread: tree.callStackPerThread === true,
    callStacks: chosen.map((s) => ({
      threadAttributed: s.threadAttributed === true,
      callStackRootFrames: trimFrames(s.callStackRootFrames, depth, siblings),
    })),
  };
}

const byteSize = (v: unknown) => Buffer.byteLength(JSON.stringify(v), "utf8");

/**
 * One diagnostic, trimmed to what the dashboard reads and under
 * MAX_PAYLOAD_BYTES. Degrades in steps — shallower, then single-path, then
 * no tree at all (`truncated: true`) — rather than refusing a crash report
 * outright, because the metadata alone (exception, signal, version) is still
 * worth a row.
 */
export function trimDiagnostic(kind: DiagnosticKind, raw: unknown): Record<string, unknown> | null {
  if (!isObj(raw)) return null;
  if (kind === "metrics") {
    // Assembled by the client from MXMetricPayload (histograms + exit
    // counts). No stack to trim, so an oversize one is simply refused.
    return byteSize(raw) <= MAX_PAYLOAD_BYTES ? raw : null;
  }
  const meta = trimMeta(raw.diagnosticMetaData);
  for (const [depth, siblings] of [
    [MAX_STACK_DEPTH, MAX_SIBLINGS],
    [32, 1],
    [12, 1],
  ] as const) {
    const out: Record<string, unknown> = { diagnosticMetaData: meta };
    const tree = trimTree(raw.callStackTree, depth, siblings);
    if (tree) out.callStackTree = tree;
    if (byteSize(out) <= MAX_PAYLOAD_BYTES) return out;
  }
  return { diagnosticMetaData: meta, truncated: true };
}

// ─── Signature ───────────────────────────────────────────────────────

/** The heaviest path through the attributed stack, innermost frame first. */
export function heaviestPath(payload: unknown, limit = 30): Frame[] {
  if (!isObj(payload) || !isObj(payload.callStackTree)) return [];
  const stacks = Array.isArray(payload.callStackTree.callStacks)
    ? payload.callStackTree.callStacks.filter(isObj)
    : [];
  const stack = stacks.find((s) => s.threadAttributed === true) ?? stacks[0];
  const path: Frame[] = [];
  let level: unknown = stack?.callStackRootFrames;
  while (Array.isArray(level) && level.length && path.length < limit) {
    const next = [...level]
      .filter(isObj)
      .sort((a, b) => (Number(b.sampleCount) || 0) - (Number(a.sampleCount) || 0))[0];
    if (!next) break;
    path.push(next as Frame);
    level = next.subFrames;
  }
  return path;
}

export const frameLabel = (f: Frame): string =>
  `${f.binaryName ?? "???"} +0x${Number(f.offsetIntoBinaryTextSegment ?? 0).toString(16)}`;

const EXCEPTION_NAMES: Record<string, string> = {
  "1": "EXC_BAD_ACCESS",
  "2": "EXC_BAD_INSTRUCTION",
  "3": "EXC_ARITHMETIC",
  "4": "EXC_EMULATION",
  "5": "EXC_SOFTWARE",
  "6": "EXC_BREAKPOINT",
  "10": "EXC_CRASH",
  "11": "EXC_RESOURCE",
  "12": "EXC_GUARD",
};
const SIGNAL_NAMES: Record<string, string> = {
  "4": "SIGILL",
  "5": "SIGTRAP",
  "6": "SIGABRT",
  "8": "SIGFPE",
  "9": "SIGKILL",
  "10": "SIGBUS",
  "11": "SIGSEGV",
};

/** "Namespace SPRINGBOARD, Code 0x8badf00d …" → the stable half of it. */
function terminationKey(reason: unknown): string {
  if (typeof reason !== "string") return "";
  const m = reason.match(/Namespace\s+([A-Z_]+),\s*Code\s+(0x[0-9a-fA-F]+|\d+)/);
  return m ? `${m[1]}:${m[2]}` : "";
}

/**
 * The grouping key: kind, exception, signal, the stable part of the
 * termination reason, and the top five frames of the heaviest path. Offsets
 * are binary-relative, so the same crash in the same build groups exactly;
 * a new build (new offsets) starts a new group, which is the honest answer
 * without server-side symbolication.
 */
export function signatureFor(kind: DiagnosticKind, payload: Record<string, unknown>): {
  signature: string;
  summary: string;
} {
  if (kind === "metrics") return { signature: "metrics", summary: "Daily metrics" };
  const meta = isObj(payload.diagnosticMetaData) ? payload.diagnosticMetaData : {};
  const frames = heaviestPath(payload, 5);
  const parts = [
    kind,
    String(meta.exceptionType ?? ""),
    String(meta.signal ?? ""),
    terminationKey(meta.terminationReason),
    ...frames.map(frameLabel),
  ];
  const signature = createHash("sha1").update(parts.join("|")).digest("hex").slice(0, 16);

  const head: string[] = [];
  if (kind === "crash") {
    const exc = meta.exceptionType != null ? EXCEPTION_NAMES[String(meta.exceptionType)] ?? `EXC ${meta.exceptionType}` : null;
    const sig = meta.signal != null ? SIGNAL_NAMES[String(meta.signal)] ?? `signal ${meta.signal}` : null;
    const objc = isObj(meta.exceptionReason) ? meta.exceptionReason.exceptionName : null;
    head.push([exc, sig && `(${sig})`].filter(Boolean).join(" ") || "Crash");
    if (typeof objc === "string" && objc) head.push(objc);
    const term = terminationKey(meta.terminationReason);
    if (term) head.push(term);
  } else if (kind === "hang") {
    head.push(`Hang ${meta.hangDuration ?? ""}`.trim());
  } else if (kind === "cpu_exception") {
    head.push(`CPU ${meta.totalCPUTime ?? ""}`.trim());
  } else {
    head.push(`Disk writes ${meta.writesCaused ?? ""}`.trim());
  }
  if (frames[0]) head.push(frameLabel(frames[0]));
  return { signature, summary: head.join(" · ").slice(0, 300) };
}

// ─── Ingest ──────────────────────────────────────────────────────────

export interface DiagnosticEnvelope {
  app_version?: unknown;
  build?: unknown;
  os_version?: unknown;
  device_model?: unknown;
}

interface NormalizedItem {
  clientId: string | null;
  kind: DiagnosticKind;
  appVersion: string | null;
  build: string | null;
  osVersion: string | null;
  deviceModel: string | null;
  occurredAt: string | null;
  payload: Record<string, unknown>;
  signature: string;
  summary: string;
}

/** A timestamp a device reported: kept only if it parses and is plausible. */
function plausibleInstant(v: unknown): string | null {
  if (typeof v !== "string" && typeof v !== "number") return null;
  const d = new Date(typeof v === "number" ? v * 1000 : v);
  const t = d.getTime();
  if (!Number.isFinite(t)) return null;
  const now = Date.now();
  if (t > now + 24 * 3600_000 || t < now - (RETENTION_DAYS + 1) * 24 * 3600_000) return null;
  return d.toISOString();
}

export function normalizeItem(raw: unknown, env: DiagnosticEnvelope): NormalizedItem | null {
  if (!isObj(raw)) return null;
  const kind = raw.kind;
  if (typeof kind !== "string" || !KIND_SET.has(kind)) return null;
  const payload = trimDiagnostic(kind as DiagnosticKind, raw.diagnostic);
  if (!payload) return null;
  const meta = isObj(payload.diagnosticMetaData) ? payload.diagnosticMetaData : {};
  const { signature, summary } = signatureFor(kind as DiagnosticKind, payload);
  const clientId =
    typeof raw.id === "string" && /^[A-Za-z0-9_-]{8,64}$/.test(raw.id) ? raw.id : null;
  return {
    clientId,
    kind: kind as DiagnosticKind,
    // The diagnostic's own metadata describes the build that CRASHED, which
    // may be older than the build uploading it (MetricKit delivers a day
    // late, often after an update). Envelope values are only the fallback.
    appVersion: str(meta.appVersion, 32) ?? str(env.app_version, 32),
    build: str(meta.appBuildVersion, 32) ?? str(env.build, 32),
    osVersion: str(meta.osVersion, 64) ?? str(env.os_version, 64),
    deviceModel: str(meta.deviceType, 64) ?? str(env.device_model, 64),
    occurredAt: plausibleInstant(raw.occurred_at),
    payload,
    signature,
    summary,
  };
}

export interface IngestResult {
  stored: number;
  duplicates: number;
  capped: number;
  rejected: number;
}

export async function recordDiagnostics(
  userId: string,
  env: DiagnosticEnvelope,
  items: unknown[],
): Promise<IngestResult> {
  const result: IngestResult = { stored: 0, duplicates: 0, capped: 0, rejected: 0 };
  const accepted: NormalizedItem[] = [];
  items.forEach((raw, i) => {
    if (i >= MAX_ITEMS_PER_REQUEST) {
      result.rejected++;
      return;
    }
    const item = normalizeItem(raw, env);
    if (item) accepted.push(item);
    else result.rejected++;
  });
  if (!accepted.length) return result;

  const client = await db.getClient();
  try {
    await client.query("BEGIN");
    // Serialises one user's uploads so two concurrent requests can't both
    // read the same remaining allowance.
    await client.query(`SELECT pg_advisory_xact_lock(hashtext('client_diagnostics:' || $1::text))`, [userId]);
    const { rows } = await client.query<{ n: number }>(
      `SELECT COUNT(*)::int AS n FROM client_diagnostics
       WHERE user_id = $1::varchar AND received_at > now() - interval '1 day'`,
      [userId],
    );
    let remaining = Math.max(0, MAX_ROWS_PER_USER_PER_DAY - (rows[0]?.n ?? 0));
    for (const item of accepted) {
      if (remaining <= 0) {
        result.capped++;
        continue;
      }
      const inserted = await client.query(
        `INSERT INTO client_diagnostics
           (user_id, client_id, kind, app_version, build, os_version, device_model,
            signature, summary, payload, occurred_at)
         VALUES ($1::varchar, $2::varchar, $3::varchar, $4::varchar, $5::varchar,
                 $6::varchar, $7::varchar, $8::varchar, $9::varchar, $10::jsonb,
                 $11::timestamptz)
         ON CONFLICT (user_id, client_id) DO NOTHING
         RETURNING id`,
        [
          userId,
          item.clientId,
          item.kind,
          item.appVersion,
          item.build,
          item.osVersion,
          item.deviceModel,
          item.signature,
          item.summary,
          JSON.stringify(item.payload),
          item.occurredAt,
        ],
      );
      if (inserted.rowCount) {
        result.stored++;
        remaining--;
      } else result.duplicates++;
    }
    await client.query("COMMIT");
  } catch (err) {
    await client.query("ROLLBACK").catch(() => {});
    throw err;
  } finally {
    client.release();
  }
  return result;
}

// ─── Retention ───────────────────────────────────────────────────────

/** Deletes rows past RETENTION_DAYS in bounded batches. Returns rows removed. */
export async function pruneOldDiagnostics(
  retentionDays = RETENTION_DAYS,
  batchSize = 5000,
  maxBatches = 50,
): Promise<number> {
  let total = 0;
  for (let i = 0; i < maxBatches; i++) {
    const rows = await db.query<{ n: number }>(
      `WITH doomed AS (
         SELECT id FROM client_diagnostics
         WHERE received_at < now() - make_interval(days => $1::int)
         ORDER BY id
         LIMIT $2::int
       ), gone AS (
         DELETE FROM client_diagnostics d USING doomed WHERE d.id = doomed.id
         RETURNING 1
       )
       SELECT COUNT(*)::int AS n FROM gone`,
      [retentionDays, batchSize],
    );
    const n = rows[0]?.n ?? 0;
    total += n;
    if (n < batchSize) break;
  }
  if (total) console.log(`[CRON] Pruned ${total} client diagnostic row(s).`);
  return total;
}

// ─── Admin reads ─────────────────────────────────────────────────────

export interface DiagnosticsOverview {
  days: number;
  totals: {
    crashes: number;
    hangs: number;
    cpu_exceptions: number;
    disk_write_exceptions: number;
    users_affected: number;
    metrics_payloads: number;
  };
  daily: { date: string; crashes: number; hangs: number; other: number }[];
  by_version: {
    app_version: string | null;
    build: string | null;
    crashes: number;
    hangs: number;
    other: number;
    users: number;
    latest_at: string;
  }[];
  top_signatures: {
    signature: string;
    kind: DiagnosticKind;
    summary: string | null;
    count: number;
    users: number;
    first_at: string;
    latest_at: string;
    app_versions: string[];
    example: {
      app_version: string | null;
      build: string | null;
      os_version: string | null;
      device_model: string | null;
      frames: string[];
      meta: Record<string, unknown>;
      truncated: boolean;
    } | null;
  }[];
}

const iso = (v: unknown) => (v instanceof Date ? v.toISOString() : String(v));

export async function loadDiagnosticsOverview(days = OVERVIEW_DAYS): Promise<DiagnosticsOverview> {
  const window = `received_at > now() - make_interval(days => $1::int)`;
  const [totalsRows, daily, byVersion, sigs] = await Promise.all([
    db.query(
      `SELECT COUNT(*) FILTER (WHERE kind = 'crash')::int AS crashes,
              COUNT(*) FILTER (WHERE kind = 'hang')::int AS hangs,
              COUNT(*) FILTER (WHERE kind = 'cpu_exception')::int AS cpu_exceptions,
              COUNT(*) FILTER (WHERE kind = 'disk_write_exception')::int AS disk_write_exceptions,
              COUNT(DISTINCT user_id) FILTER (WHERE kind <> 'metrics')::int AS users_affected,
              COUNT(*) FILTER (WHERE kind = 'metrics')::int AS metrics_payloads
       FROM client_diagnostics WHERE ${window}`,
      [days],
    ),
    db.query(
      `SELECT to_char(d, 'YYYY-MM-DD') AS date,
              COUNT(c.id) FILTER (WHERE c.kind = 'crash')::int AS crashes,
              COUNT(c.id) FILTER (WHERE c.kind = 'hang')::int AS hangs,
              COUNT(c.id) FILTER (WHERE c.kind IN ('cpu_exception','disk_write_exception'))::int AS other
       FROM generate_series(
              (now() AT TIME ZONE 'UTC')::date - ($1::int - 1),
              (now() AT TIME ZONE 'UTC')::date, interval '1 day') AS d
       LEFT JOIN client_diagnostics c
         ON (c.received_at AT TIME ZONE 'UTC')::date = d::date
        AND c.received_at > now() - make_interval(days => $1::int)
       GROUP BY d ORDER BY d`,
      [days],
    ),
    db.query(
      `SELECT app_version, build,
              COUNT(*) FILTER (WHERE kind = 'crash')::int AS crashes,
              COUNT(*) FILTER (WHERE kind = 'hang')::int AS hangs,
              COUNT(*) FILTER (WHERE kind IN ('cpu_exception','disk_write_exception'))::int AS other,
              COUNT(DISTINCT user_id)::int AS users,
              MAX(received_at) AS latest_at
       FROM client_diagnostics
       WHERE ${window} AND kind <> 'metrics'
       GROUP BY app_version, build
       ORDER BY MAX(received_at) DESC
       LIMIT 20`,
      [days],
    ),
    db.query(
      `SELECT signature, kind,
              (ARRAY_AGG(summary ORDER BY received_at DESC))[1] AS summary,
              COUNT(*)::int AS count,
              COUNT(DISTINCT user_id)::int AS users,
              MIN(received_at) AS first_at,
              MAX(received_at) AS latest_at,
              ARRAY_REMOVE(ARRAY_AGG(DISTINCT app_version), NULL) AS app_versions
       FROM client_diagnostics
       WHERE ${window} AND kind <> 'metrics'
       GROUP BY signature, kind
       ORDER BY COUNT(*) DESC, MAX(received_at) DESC
       LIMIT 25`,
      [days],
    ),
  ]);

  const examples = sigs.length
    ? await db.query(
        `SELECT DISTINCT ON (signature)
                signature, app_version, build, os_version, device_model, payload
         FROM client_diagnostics
         WHERE signature = ANY($1::varchar[]) AND received_at > now() - make_interval(days => $2::int)
         ORDER BY signature, received_at DESC`,
        [sigs.map((s: any) => s.signature), days],
      )
    : [];
  const exampleBy = new Map(examples.map((e: any) => [e.signature, e]));

  const t = totalsRows[0] ?? {};
  return {
    days,
    totals: {
      crashes: t.crashes ?? 0,
      hangs: t.hangs ?? 0,
      cpu_exceptions: t.cpu_exceptions ?? 0,
      disk_write_exceptions: t.disk_write_exceptions ?? 0,
      users_affected: t.users_affected ?? 0,
      metrics_payloads: t.metrics_payloads ?? 0,
    },
    daily,
    by_version: byVersion.map((r: any) => ({ ...r, latest_at: iso(r.latest_at) })),
    top_signatures: sigs.map((s: any) => {
      const e: any = exampleBy.get(s.signature);
      const payload = e?.payload ?? null;
      return {
        signature: s.signature,
        kind: s.kind,
        summary: s.summary,
        count: s.count,
        users: s.users,
        first_at: iso(s.first_at),
        latest_at: iso(s.latest_at),
        app_versions: s.app_versions ?? [],
        example: e
          ? {
              app_version: e.app_version,
              build: e.build,
              os_version: e.os_version,
              device_model: e.device_model,
              frames: heaviestPath(payload, 40).map(frameLabel),
              meta: isObj(payload?.diagnosticMetaData) ? payload.diagnosticMetaData : {},
              truncated: payload?.truncated === true,
            }
          : null,
      };
    }),
  };
}

let overviewCache: { at: number; data: DiagnosticsOverview } | null = null;
/** 15s TTL — the dashboard refetches on every tab mount. */
export async function getDiagnosticsOverview(): Promise<DiagnosticsOverview> {
  if (overviewCache && Date.now() - overviewCache.at < 15_000) return overviewCache.data;
  const data = await loadDiagnosticsOverview();
  overviewCache = { at: Date.now(), data };
  return data;
}
export function resetDiagnosticsCache(): void {
  overviewCache = null;
}

/** Rows behind one signature, for the shared drill-down drawer. */
export async function getSignatureRows(signature: string, limit: number) {
  const [rows, [{ n } = { n: 0 }]] = await Promise.all([
    db.query(
      `SELECT c.user_id, u.username, c.kind, c.summary, c.app_version, c.build,
              c.os_version, c.device_model, c.received_at, c.occurred_at
       FROM client_diagnostics c
       LEFT JOIN users u ON u.user_id = c.user_id
       WHERE c.signature = $1::varchar
       ORDER BY c.received_at DESC
       LIMIT $2::int`,
      [signature, limit],
    ),
    db.query<{ n: number }>(
      `SELECT COUNT(*)::int AS n FROM client_diagnostics WHERE signature = $1::varchar`,
      [signature],
    ),
  ]);
  return { rows, total: n };
}
