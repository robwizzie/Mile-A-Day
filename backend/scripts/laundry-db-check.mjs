/**
 * Laundry check — POST /laundry/report, the owner's admin endpoints, the
 * desk feed's laundry block and the "done" push, over real HTTP and a real
 * database.
 *
 * Proves:
 *  - only a live, well-formed plug key can report (missing, malformed,
 *    unknown, revoked, a display key, a user bearer: all 401), and a plug key
 *    opens nothing else (not the desk feed, not /admin);
 *  - readings are strictly checked (shape, count, range);
 *  - plugs are per person: another admin can't see, make, revoke or empty
 *    someone else's, and their feed never carries someone else's laundry;
 *  - only the key's hash is stored; the key is shown once;
 *  - a whole washer load (fill > wash > ... > spin > done) shows on the
 *    owner's feed, is stored as a load, and pushes "Washer's done" to the
 *    owner's phone only;
 *  - "emptied" clears it, and a new plug for the same machine replaces the
 *    old one (old key dead, what it learned kept).
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/laundry-db-check.mjs
 */
import express from "express";
import { PostgresService } from "../dist/services/DbService.js";
import displayRoutes from "../dist/routes/displayRoutes.js";
import laundryRoutes from "../dist/routes/laundryRoutes.js";
import adminRoutes from "../dist/routes/adminRoutes.js";
import { requireAdmin } from "../dist/middleware/auth.js";
import { createDisplayKey } from "../dist/services/displayService.js";
import { setPushSenderForTests } from "../dist/services/deskPushService.js";
import { hashLaundryKey, reportReadings, resolveLaundryKey } from "../dist/services/laundryService.js";

const db = PostgresService.getInstance();
const P = "laundry-check-";
// Laundry is on for these accounts only (the server's default is Rob's).
process.env.LAUNDRY_USER_IDS = "laundry-check-owner, laundry-check-other";
const OWNER = P + "owner"; // admin with a desk and laundry plugs
const OTHER = P + "other"; // another admin with a desk, no plugs
const NODESK = P + "nodesk"; // admin without a desk
const OFFLIST = P + "offlist"; // admin with a desk, not on the laundry list
const ALL = [OWNER, OTHER, NODESK, OFFLIST];

let failures = 0;
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  console.log(`${ok ? "ok  " : "FAIL"}  ${label} → ${JSON.stringify(actual)} (expected ${JSON.stringify(expected)})`);
}

async function cleanup() {
  await db.query(`DELETE FROM laundry_loads WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM laundry_plugs WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM desk_push_subscriptions WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM desk_push_log WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM display_keys WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1::text[])`, [ALL]);
}

async function seed() {
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, apple_sub, email, username, first_name, last_name, role)
       VALUES ($1, $2, $3, $4, 'Secret', 'Surname', 'admin')`,
      [id, `sub-${id}`, `${id}@example.com`, id.slice(P.length)],
    );
  }
}

function server() {
  const app = express();
  app.use(express.json());
  app.use("/display", displayRoutes);
  app.use("/laundry", laundryRoutes);
  app.use((req, _res, next) => { req.userId = req.headers["x-test-user"]; next(); });
  app.use("/admin", requireAdmin, adminRoutes);
  return new Promise((resolve) => { const s = app.listen(0, () => resolve(s)); });
}

let seedN = 11;
const rnd = () => ((seedN = (seedN * 16807) % 2147483647) / 2147483647);
const jit = (w, p = 0.06) => Math.max(0, Math.round(w * (1 + (rnd() * 2 - 1) * p) * 10) / 10);
function washerTrace() {
  const segs = [[120, () => jit(1.5, 0.1)], [240, () => jit(7)], [720, () => (rnd() < 0.5 ? jit(360, 0.15) : jit(12, 0.3))],
    [120, () => jit(45)], [300, () => jit(240, 0.08)], [240, () => jit(7)], [360, () => (rnd() < 0.5 ? jit(360, 0.15) : jit(12, 0.3))],
    [120, () => jit(45)], [420, () => jit(240, 0.08)], [600, () => jit(1.5, 0.1)]];
  const out = [];
  for (const [len, fn] of segs) for (let t = 0; t < len; t += 2) out.push(fn());
  return out;
}

async function main() {
  await cleanup();
  await seed();
  await createDisplayKey(OWNER, "desk", OWNER);
  await createDisplayKey(OFFLIST, "desk", OFFLIST);
  const { key: otherDisplayKey } = await createDisplayKey(OTHER, "desk", OTHER);
  const s = await server();
  const base = `http://127.0.0.1:${s.address().port}`;
  const admin = (path, method = "GET", user = OWNER) =>
    fetch(`${base}/admin/${path}`, { method, headers: { "x-test-user": user } });
  const report = (auth, body) =>
    fetch(`${base}/laundry/report`, {
      method: "POST",
      headers: { "content-type": "application/json", ...(auth ? { authorization: auth } : {}) },
      body: typeof body === "string" ? body : JSON.stringify(body),
    });
  const ownerFeedKey = (await createDisplayKey(OWNER, "desk 2", OWNER)).key;
  const feed = async (key) => (await (await fetch(`${base}/display/feed`, { headers: { authorization: `Display ${key}` } })).json());

  // ── who may make a plug ──
  check("no desk → 404", (await admin("desk/laundry/plug?machine=washer", "POST", NODESK)).status, 404);
  check("not on the laundry list → 404", (await admin("desk/laundry/plug?machine=washer", "POST", OFFLIST)).status, 404);
  check("not on the list: no laundry card", (await admin("desk/laundry", "GET", OFFLIST)).status, 404);
  check("bad machine → 400", (await admin("desk/laundry/plug?machine=oven", "POST")).status, 400);
  const made = await admin("desk/laundry/plug?machine=washer", "POST");
  check("make my washer plug → 201", made.status, 201);
  check("no-store", made.headers.get("cache-control"), "no-store");
  const { key, plug, report_url } = await made.json();
  check("key format", /^madl_[A-Za-z0-9_-]{43}$/.test(key), true);
  check("report url", report_url.endsWith("/laundry/report"), true);
  const stored = await db.query(`SELECT key_hash, key_prefix FROM laundry_plugs WHERE id = $1`, [plug.id]);
  check("only the hash is stored", stored[0].key_hash === hashLaundryKey(key) && !JSON.stringify(stored[0]).includes(key.slice(9)), true);
  const listed = await (await admin("desk/laundry")).json();
  check("listing never has the key", JSON.stringify(listed).includes(key.slice(9)), false);
  check("my plugs", listed.plugs.map((p) => p.machine), ["washer"]);

  // ── the report route: keys ──
  const ok = { v: 1, dt: 2, on: true, p: [1.5, 1.6, 1.4] };
  check("no key → 401", (await report(null, ok)).status, 401);
  check("malformed → 401", (await report("Laundry nope", ok)).status, 401);
  check("unknown → 401", (await report("Laundry madl_" + "A".repeat(43), ok)).status, 401);
  check("a display key → 401", (await report(`Laundry ${otherDisplayKey}`, ok)).status, 401);
  check("bearer scheme → 401", (await report(`Bearer ${key}`, ok)).status, 401);
  check("good key → 200", (await report(`Laundry ${key}`, ok)).status, 200);
  check("plug key can't open the desk feed", (await fetch(`${base}/display/feed`, { headers: { authorization: `Display ${key}` } })).status, 401);
  // ── the report route: readings ──
  for (const [label, body] of [
    ["no readings", { v: 1, p: [] }],
    ["too many", { v: 1, p: Array(151).fill(1) }],
    ["negative", { v: 1, p: [1, -2] }],
    ["huge", { v: 1, p: [1, 99999] }],
    ["a string", { v: 1, p: [1, "2"] }],
    ["wrong interval", { v: 1, dt: 5, p: [1] }],
    ["not json", "p=1"],
  ]) check(`bad body (${label}) → 400`, (await report(`Laundry ${key}`, body)).status, 400);

  // ── per person ──
  check("other admin sees no laundry", (await (await admin("desk/laundry", "GET", OTHER)).json()).status, null);
  check("other admin can't revoke mine", (await admin(`desk/laundry/plug/${plug.id}/revoke`, "POST", OTHER)).status, 404);
  check("other admin can't empty mine", (await admin("desk/laundry/washer/emptied", "POST", OTHER)).status, 404);
  check("other admin's feed: no laundry", (await feed(otherDisplayKey)).laundry, null);
  check("my feed: washer idle, no dryer", (await feed(ownerFeedKey)).laundry, { w: { s: "idle", m: 0, l: -1, ok: 0, t: -1 }, d: null });

  // ── a whole load (readings stamped as if live: 45 min, 30 at a time) ──
  const pushed = [];
  setPushSenderForTests(async (sub, payload) => { pushed.push({ endpoint: sub.endpoint, ...JSON.parse(payload) }); });
  const sub = (user, host) => db.query(
    `INSERT INTO desk_push_subscriptions (user_id, endpoint, p256dh, auth, kinds) VALUES ($1, $2, $3, $4, $5)`,
    [user, `https://${host}/x/${user}`, "B".repeat(87), "A".repeat(22), ["laundry", "doodle"]]);
  await sub(OWNER, "web.push.apple.com");
  await sub(OTHER, "fcm.googleapis.com");
  const plugRow = await resolveLaundryKey(key);
  const tr = washerTrace();
  const t0 = Date.now() + 60_000;
  let midStage = null;
  for (let i = 0; i < tr.length; i += 30) {
    const batch = tr.slice(i, i + 30);
    await reportReadings(plugRow, batch, true, t0 + (i + batch.length - 1) * 2000);
    if (i === 30 * 10) {
      const st = await db.query(`SELECT state FROM laundry_plugs WHERE id = $1`, [plug.id]);
      midStage = st[0].state.engine.stage;
    }
  }
  check("10 min in it's washing", midStage, "wash");
  const loads = await db.query(`SELECT machine, seconds, length(trace) > 1000 AS traced FROM laundry_loads WHERE user_id = $1`, [OWNER]);
  check("the load is stored with its trace", loads.map((l) => [l.machine, Math.abs(l.seconds - 2520) < 90, l.traced]), [["washer", true, true]]);
  check("one push, to my phone only", pushed.map((p) => [p.endpoint.includes(OWNER), p.title, p.kind]), [[true, "Washer's done 🧺", "laundry"]]);
  const log = await db.query(`SELECT user_id, kind FROM desk_push_log WHERE user_id = ANY($1::text[])`, [ALL]);
  check("activity log: mine only", log.map((l) => [l.user_id, l.kind]), [[OWNER, "laundry"]]);

  // ── empty it; replace the plug ──
  check("emptied → 200", (await admin("desk/laundry/washer/emptied", "POST")).status, 200);
  const st = await db.query(`SELECT state FROM laundry_plugs WHERE id = $1`, [plug.id]);
  check("done cleared", st[0].state.engine.stage, "idle");
  const again = await (await admin("desk/laundry/plug?machine=washer", "POST")).json();
  check("old key dead after a new plug", (await report(`Laundry ${key}`, ok)).status, 401);
  check("new key works", (await report(`Laundry ${again.key}`, ok)).status, 200);
  const st2 = await db.query(`SELECT state FROM laundry_plugs WHERE id = $1`, [again.plug.id]);
  check("what it learned carries over", st2[0].state.engine.history.length, 1);
  check("still one live washer plug", (await (await admin("desk/laundry")).json()).plugs.length, 1);
  check("revoke → 200", (await admin(`desk/laundry/plug/${again.plug.id}/revoke`, "POST")).status, 200);
  check("revoked key dead", (await report(`Laundry ${again.key}`, ok)).status, 401);
  // Taken off the list with a plug still live: can still remove it, nothing else.
  const left = await (await admin("desk/laundry/plug?machine=dryer", "POST")).json();
  process.env.LAUNDRY_USER_IDS = OTHER;
  check("off the list: no card", (await admin("desk/laundry")).status, 404);
  check("off the list: can't make plugs", (await admin("desk/laundry/plug?machine=washer", "POST")).status, 404);
  check("off the list: can still remove one", (await admin(`desk/laundry/plug/${left.plug.id}/revoke`, "POST")).status, 200);
  process.env.LAUNDRY_USER_IDS = `${OWNER},${OTHER}`;
  check("no plugs → feed laundry null", (await feed(ownerFeedKey)).laundry, null);

  setPushSenderForTests(null);
  s.close();
}

try {
  await main();
} catch (e) {
  failures++;
  console.error(e);
} finally {
  await cleanup();
  await db.close();
}
console.log(failures ? `laundry-db-check: ${failures} FAILED` : "laundry-db-check: all good");
process.exit(failures ? 1 : 0);
