/**
 * MetricKit diagnostics check.
 *
 * POST /diagnostics/metrickit is the app's only crash reporter, and every way
 * it can go wrong is silent: a row that never lands, a payload that grows
 * until one crash report is megabytes of jsonb, a looping client filling the
 * table, a retry storing the same crash twice, a signature that stops
 * grouping. This drives the REAL router + auth middleware over HTTP (an
 * in-process express app, same body limit as server.ts) against a real DB.
 *
 * Every assertion is a DELTA or membership test scoped to this script's own
 * users — CI shares one database across every check.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... APP_JWT_SECRET=... node scripts/diagnostics-check.mjs
 */
import express from "express";
import { PostgresService } from "../dist/services/DbService.js";
import { authenticateToken, requireAdmin } from "../dist/middleware/auth.js";
import diagnosticsRoutes from "../dist/routes/diagnosticsRoutes.js";
import adminRoutes from "../dist/routes/adminRoutes.js";
import { generateAccessToken } from "../dist/services/tokenService.js";
import {
  MAX_ROWS_PER_USER_PER_DAY,
  MAX_PAYLOAD_BYTES,
  pruneOldDiagnostics,
  resetDiagnosticsCache,
  signatureFor,
} from "../dist/services/diagnosticsService.js";

const db = PostgresService.getInstance();
const USER = "diag-user";
const LOOPER = "diag-looper";
const ADMIN = "diag-admin";
const ALL = [USER, LOOPER, ADMIN];

let failures = 0;
function check(label, actual, expected) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${JSON.stringify(actual)}${ok ? "" : ` (expected ${JSON.stringify(expected)})`}`,
  );
}

async function cleanup() {
  await db.query(`DELETE FROM client_diagnostics WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1)`, [ALL]);
}

async function rowsFor(userId) {
  const [{ n }] = await db.query(
    `SELECT COUNT(*)::int AS n FROM client_diagnostics WHERE user_id = $1`,
    [userId],
  );
  return n;
}

/** A crash tree shaped like MetricKit's: innermost frame first, callers in subFrames. */
function crashDiagnostic(topBinary = "Mile A Day", topOffset = 0x1a2b, depth = 8) {
  let frame = null;
  for (let i = depth - 1; i >= 0; i--) {
    const f = {
      binaryName: i === 0 ? topBinary : i < 3 ? "Mile A Day" : "UIKitCore",
      binaryUUID: "11111111-2222-3333-4444-555555555555",
      offsetIntoBinaryTextSegment: i === 0 ? topOffset : 0x1000 + i * 16,
      address: 4300000000 + i,
      sampleCount: 1,
    };
    if (frame) f.subFrames = [frame];
    frame = f;
  }
  return {
    diagnosticMetaData: {
      appVersion: "9.9.9",
      appBuildVersion: "999",
      osVersion: "iPhone OS 18.1 (22B83)",
      deviceType: "iPhone15,2",
      exceptionType: 1,
      exceptionCode: 0,
      signal: 11,
      regionFormat: "US",
      bundleIdentifier: "com.mileaday.app",
    },
    callStackTree: {
      callStackPerThread: true,
      callStacks: [
        { threadAttributed: false, callStackRootFrames: [{ binaryName: "libsystem_kernel.dylib", offsetIntoBinaryTextSegment: 4, sampleCount: 1 }] },
        { threadAttributed: true, callStackRootFrames: [frame] },
      ],
    },
  };
}

/** 400 frames deep with junk keys on every frame: ~150KB raw, far past 64KB. */
function monsterDiagnostic() {
  const make = (depth) => {
    const f = {
      binaryName: "VeryLongBinaryName".repeat(6),
      binaryUUID: "11111111-2222-3333-4444-555555555555",
      offsetIntoBinaryTextSegment: depth,
      address: depth,
      sampleCount: 1,
      junk: "x".repeat(200),
    };
    if (depth > 0) f.subFrames = [make(depth - 1)];
    return f;
  };
  return {
    diagnosticMetaData: { appVersion: "9.9.9", appBuildVersion: "999", hangDuration: "5.1 sec" },
    callStackTree: { callStackPerThread: false, callStacks: [{ threadAttributed: true, callStackRootFrames: [make(400)] }] },
  };
}

const app = express();
app.use(express.json({ limit: "2mb" }));
app.use(authenticateToken);
app.use("/admin", requireAdmin, adminRoutes);
app.use("/diagnostics", diagnosticsRoutes);
const server = await new Promise((resolve) => {
  const s = app.listen(0, "127.0.0.1", () => resolve(s));
});
const base = `http://127.0.0.1:${server.address().port}`;

async function call(method, path, token, body) {
  const res = await fetch(base + path, {
    method,
    headers: {
      "content-type": "application/json",
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let json = null;
  try {
    json = await res.json();
  } catch {}
  return { status: res.status, json };
}

const envelope = { app_version: "9.9.9", build: "999", os_version: "18.1", device_model: "iPhone15,2" };
const runTag = Date.now().toString(36);

try {
  await cleanup();
  for (const [id, role] of [
    [USER, "user"],
    [LOOPER, "user"],
    [ADMIN, "admin"],
  ]) {
    await db.query(
      `INSERT INTO users (user_id, username, apple_sub, email, role, created_at)
       VALUES ($1, $2, $3, $4, $5, NOW())`,
      [id, id, id, `${id}@example.com`, role],
    );
  }
  const userToken = await generateAccessToken(USER);
  const looperToken = await generateAccessToken(LOOPER);
  const adminToken = await generateAccessToken(ADMIN);

  // ── Auth ──
  const unauth = await call("POST", "/diagnostics/metrickit", null, { ...envelope, items: [] });
  check("unauthenticated upload is 401", unauth.status, 401);
  const badToken = await call("POST", "/diagnostics/metrickit", "not-a-jwt", { ...envelope, items: [] });
  check("a garbage token is 401", badToken.status, 401);
  const noItems = await call("POST", "/diagnostics/metrickit", userToken, envelope);
  check("a body without items is 400", noItems.status, 400);

  // ── Store ──
  const occurred = new Date(Date.now() - 3600_000).toISOString();
  const batch = {
    ...envelope,
    items: [
      { id: `crashA1-${runTag}`, kind: "crash", occurred_at: occurred, diagnostic: crashDiagnostic() },
      { id: `crashA2-${runTag}`, kind: "crash", occurred_at: occurred, diagnostic: crashDiagnostic() },
      { id: `hang1-${runTag}`, kind: "hang", occurred_at: occurred, diagnostic: { diagnosticMetaData: { hangDuration: "3.2 sec" }, callStackTree: crashDiagnostic().callStackTree } },
      { id: `bogus-${runTag}`, kind: "not_a_kind", diagnostic: {} },
    ],
  };
  const before = await rowsFor(USER);
  const first = await call("POST", "/diagnostics/metrickit", userToken, batch);
  check("upload is 200", first.status, 200);
  check("…stores the three valid items", first.json?.stored, 3);
  check("…rejects the unknown kind", first.json?.rejected, 1);
  check("row delta is 3", (await rowsFor(USER)) - before, 3);

  const [stored] = await db.query(
    `SELECT app_version, build, device_model, signature, summary, occurred_at, payload
     FROM client_diagnostics WHERE user_id = $1 AND client_id = $2`,
    [USER, `crashA1-${runTag}`],
  );
  check("app version comes from the diagnostic's own metadata", stored?.app_version, "9.9.9");
  check("device model stored", stored?.device_model, "iPhone15,2");
  check("occurred_at kept", stored?.occurred_at instanceof Date, true);
  check("summary names the exception", /EXC_BAD_ACCESS \(SIGSEGV\)/.test(stored?.summary ?? ""), true);
  check("regionFormat is not stored", stored?.payload?.diagnosticMetaData?.regionFormat, undefined);
  check(
    "only the attributed thread survives trimming",
    stored?.payload?.callStackTree?.callStacks?.length,
    1,
  );
  const expected = signatureFor("crash", stored.payload).signature;
  check("stored signature is the recomputable one", stored?.signature, expected);

  // ── Retry is idempotent ──
  const retry = await call("POST", "/diagnostics/metrickit", userToken, batch);
  check("a retried batch stores nothing", retry.json?.stored, 0);
  check("…and reports the duplicates", retry.json?.duplicates, 3);
  check("row delta still 3 after retry", (await rowsFor(USER)) - before, 3);

  // ── Signature grouping ──
  const sameA = signatureFor("crash", { diagnosticMetaData: { exceptionType: 1, signal: 11 }, callStackTree: crashDiagnostic().callStackTree });
  const otherTop = signatureFor("crash", { diagnosticMetaData: { exceptionType: 1, signal: 11 }, callStackTree: crashDiagnostic("Mile A Day", 0x9999).callStackTree });
  check("same stack → same signature", sameA.signature, expected);
  check("different top frame → different signature", otherTop.signature === expected, false);

  // ── Oversize ──
  const monsterRaw = JSON.stringify(monsterDiagnostic()).length;
  check("the monster payload really is oversize", monsterRaw > MAX_PAYLOAD_BYTES, true);
  const big = await call("POST", "/diagnostics/metrickit", userToken, {
    ...envelope,
    items: [
      { id: `monster-${runTag}`, kind: "hang", diagnostic: monsterDiagnostic() },
      { id: `bigmetrics-${runTag}`, kind: "metrics", diagnostic: { blob: "y".repeat(MAX_PAYLOAD_BYTES + 10) } },
    ],
  });
  check("oversize crash tree is trimmed and stored", big.json?.stored, 1);
  check("oversize metrics payload is rejected", big.json?.rejected, 1);
  const [{ bytes }] = await db.query(
    `SELECT octet_length(payload::text) AS bytes FROM client_diagnostics WHERE user_id = $1 AND client_id = $2`,
    [USER, `monster-${runTag}`],
  );
  check("trimmed payload fits the cap", bytes <= MAX_PAYLOAD_BYTES, true);

  // ── Per-user daily cap ──
  const looperBefore = await rowsFor(LOOPER);
  let storedTotal = 0;
  let cappedTotal = 0;
  for (let r = 0; r < 3; r++) {
    const items = Array.from({ length: 20 }, (_, i) => ({
      id: `loop-${runTag}-${r}-${i}`,
      kind: "crash",
      diagnostic: crashDiagnostic("Mile A Day", 0x2000 + r * 100 + i),
    }));
    const res = await call("POST", "/diagnostics/metrickit", looperToken, { ...envelope, items });
    storedTotal += res.json?.stored ?? 0;
    cappedTotal += res.json?.capped ?? 0;
  }
  check("a looping client stores at most the daily cap", storedTotal, MAX_ROWS_PER_USER_PER_DAY);
  check("…and the rest are reported as capped", cappedTotal, 60 - MAX_ROWS_PER_USER_PER_DAY);
  check("looper row delta equals the cap", (await rowsFor(LOOPER)) - looperBefore, MAX_ROWS_PER_USER_PER_DAY);
  const tooMany = await call("POST", "/diagnostics/metrickit", userToken, {
    ...envelope,
    items: Array.from({ length: 30 }, () => ({ kind: "nope" })),
  });
  check("items past the per-request cap are rejected", tooMany.json?.rejected, 30);

  // ── Admin aggregate ──
  resetDiagnosticsCache();
  const civilian = await call("GET", "/admin/diagnostics", userToken);
  check("a non-admin cannot read diagnostics", civilian.status, 403);
  const overview = await call("GET", "/admin/diagnostics", adminToken);
  check("admin overview is 200", overview.status, 200);
  const sig = overview.json?.top_signatures?.find((s) => s.signature === expected);
  check("the seeded signature is in the top list", Boolean(sig), true);
  check("…counted at least twice (A1 + A2)", (sig?.count ?? 0) >= 2, true);
  check("…with an example stack", (sig?.example?.frames?.length ?? 0) > 0, true);
  check("…whose top frame is the crashing one", sig?.example?.frames?.[0], "Mile A Day +0x1a2b");
  const version = overview.json?.by_version?.find((v) => v.app_version === "9.9.9" && v.build === "999");
  check("the seeded version is in the per-version table", Boolean(version), true);
  check("…with crashes counted", (version?.crashes ?? 0) >= 2, true);
  check("daily series covers the window", overview.json?.daily?.length, overview.json?.days);

  const drill = await call("GET", `/admin/drilldown?kind=diagnostic_signature&id=${expected}`, adminToken);
  check("signature drill-down is 200", drill.status, 200);
  check(
    "…and lists the user who hit it",
    Boolean(drill.json?.rows?.some((r) => r.user_id === USER)),
    true,
  );

  // ── Retention prune ──
  await db.query(
    `INSERT INTO client_diagnostics (user_id, client_id, kind, signature, payload, received_at)
     VALUES ($1, $2, 'crash', 'old', '{}'::jsonb, now() - interval '100 days')`,
    [USER, `ancient-${runTag}`],
  );
  const beforePrune = await rowsFor(USER);
  const pruned = await pruneOldDiagnostics();
  check("prune removed at least the ancient row", pruned >= 1, true);
  check("…and only it, for this user", beforePrune - (await rowsFor(USER)), 1);
} finally {
  await cleanup().catch((e) => console.error("cleanup failed:", e.message));
  server.close();
  await db.close();
}

if (failures) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log("\nAll diagnostics checks passed.");
