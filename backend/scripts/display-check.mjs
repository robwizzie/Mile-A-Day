/**
 * Desk display check — GET /display/feed and the admin key endpoints.
 *
 * Proves the privacy rules end to end over real HTTP:
 *  - only a live, well-formed display key opens the feed (missing, malformed,
 *    unknown, revoked, a user JWT, a key in the query string: all 401);
 *  - the response is an exact field whitelist (no ids, emails, names, hashes);
 *  - friends out running respect friendship, share_live_presence, blocks
 *    (both directions) and freshness;
 *  - alerts are only the owner's own nudges/hypes, never another user's,
 *    never from a blocked account;
 *  - key management needs role=admin and never returns the stored hash.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/display-check.mjs
 */
import express from "express";
import { PostgresService } from "../dist/services/DbService.js";
import displayRoutes from "../dist/routes/displayRoutes.js";
import adminRoutes from "../dist/routes/adminRoutes.js";
import { requireAdmin } from "../dist/middleware/auth.js";
import { createDisplayKey, hashDisplayKey } from "../dist/services/displayService.js";

const db = PostgresService.getInstance();
const P = "display-check-";
const OWNER = P + "owner";
const ADMIN = P + "admin";
const RUNNER = P + "runner";          // friend, running, sharing → shown
const HIDDEN = P + "hidden";          // friend, running, opted out → not shown
const BLOCKED = P + "blocked";        // friend, running, owner blocked them → not shown
const BLOCKER = P + "blocker";        // friend, running, they blocked owner → not shown
const STALE = P + "stale";            // friend, session stale → not shown
const STRANGER = P + "stranger";      // not a friend, running → not shown
const NUDGER = P + "nudger";          // friend who nudged owner → alert
const OTHER = P + "other";            // someone else with their own inbox
const ALL = [OWNER, ADMIN, RUNNER, HIDDEN, BLOCKED, BLOCKER, STALE, STRANGER, NUDGER, OTHER];

let failures = 0;
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  console.log(`${ok ? "ok  " : "FAIL"}  ${label} → ${JSON.stringify(actual)} (expected ${JSON.stringify(expected)})`);
}

async function cleanup() {
  await db.query(`DELETE FROM display_keys WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM in_app_notifications WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM live_tracking_sessions WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM notification_settings WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM user_blocks WHERE blocker_id = ANY($1::text[]) OR blocked_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM friendships WHERE user_id = ANY($1::text[]) OR friend_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1::text[])`, [ALL]);
}

async function seed() {
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, apple_sub, email, username, first_name, last_name, role)
       VALUES ($1, $2, $3, $4, 'Secret', 'Surname', $5)`,
      [id, `sub-${id}`, `${id}@example.com`, id.slice(P.length), id === ADMIN ? "admin" : "user"],
    );
  }
  for (const f of [RUNNER, HIDDEN, BLOCKED, BLOCKER, STALE, NUDGER]) {
    await db.query(
      `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1,$2,'accepted'),($2,$1,'accepted')`,
      [OWNER, f],
    );
  }
  for (const [id, miles, fresh] of [[RUNNER, 0.84, true], [HIDDEN, 1, true], [BLOCKED, 1, true],
                                     [BLOCKER, 1, true], [STALE, 1, false], [STRANGER, 1, true]]) {
    await db.query(
      `INSERT INTO live_tracking_sessions (user_id, workout_type, distance_miles, last_seen_at)
       VALUES ($1, 'running', $2, NOW() - ($3 || ' seconds')::interval)`,
      [id, miles, fresh ? "10" : "900"],
    );
  }
  await db.query(`INSERT INTO notification_settings (user_id, share_live_presence) VALUES ($1, FALSE)`, [HIDDEN]);
  await db.query(`INSERT INTO user_blocks (blocker_id, blocked_id) VALUES ($1,$2),($3,$1)`, [OWNER, BLOCKED, BLOCKER]);
  // Owner's inbox: a nudge and a hype from NUDGER, a nudge from BLOCKED, an old one, an unrelated type.
  const note = (uid, type, sender, ago) => db.query(
    `INSERT INTO in_app_notifications (user_id, title, body, type, data, created_at)
     VALUES ($1, 'Secret title', 'Secret body', $2, jsonb_build_object('user_id', $3::text),
             NOW() - ($4 || ' minutes')::interval)`,
    [uid, type, sender, String(ago)],
  );
  await note(OWNER, "friend_nudge", NUDGER, 5);
  await note(OWNER, "hype_received", NUDGER, 3);
  await note(OWNER, "friend_nudge", BLOCKED, 2);
  await note(OWNER, "friend_nudge", NUDGER, 60 * 30);   // older than 24h
  await note(OWNER, "comment", NUDGER, 1);              // not a nudge/hype
  await note(OTHER, "friend_nudge", NUDGER, 1);         // someone else's inbox
  // Owner did 1.02 miles today in their own timezone.
  await db.query(
    `INSERT INTO workouts (workout_id, user_id, distance, local_date, date, timezone_offset,
                           workout_type, device_end_date, calories, total_duration)
     VALUES ($1, $2, 1.02, (NOW() AT TIME ZONE 'UTC')::date, (NOW() AT TIME ZONE 'UTC')::date, 0,
             'running', NOW() - INTERVAL '1 minute', 100, 600)`,
    [P + "w1", OWNER],
  );
}

function server() {
  const app = express();
  app.use("/display", displayRoutes);
  // Stand-in for authenticateToken: the header says who the caller is.
  app.use((req, _res, next) => { req.userId = req.headers["x-test-user"]; next(); });
  app.use("/admin", requireAdmin, adminRoutes);
  return new Promise((resolve) => {
    const s = app.listen(0, () => resolve(s));
  });
}

async function main() {
  await cleanup();
  await seed();
  const s = await server();
  const base = `http://127.0.0.1:${s.address().port}`;
  const feed = (headers = {}, qs = "") => fetch(`${base}/display/feed${qs}`, { headers });

  // ── keys ──
  const { key } = await createDisplayKey(OWNER, "desk", ADMIN);
  check("key format", /^madk_[A-Za-z0-9_-]{43}$/.test(key), true);
  const stored = await db.query(`SELECT key_hash FROM display_keys WHERE user_id = $1`, [OWNER]);
  check("only the hash is stored", stored[0].key_hash === hashDisplayKey(key) && !stored[0].key_hash.includes(key.slice(5)), true);

  check("no header → 401", (await feed()).status, 401);
  check("malformed key → 401", (await feed({ authorization: "Display nope" })).status, 401);
  check("unknown well-formed key → 401", (await feed({ authorization: "Display madk_" + "A".repeat(43) })).status, 401);
  check("user JWT style bearer → 401", (await feed({ authorization: `Bearer ${key}` })).status, 401);
  check("key in query string → 401", (await feed({}, `?key=${key}`)).status, 401);

  const res = await feed({ authorization: `Display ${key}` });
  check("valid key → 200", res.status, 200);
  check("no-store", res.headers.get("cache-control"), "no-store");
  check("no CORS header", res.headers.get("access-control-allow-origin"), null);
  const body = await res.json();

  // ── exact whitelist ──
  check("top-level fields", Object.keys(body).sort(), ["alerts", "community", "friends_running", "me", "v"]);
  check("community fields", Object.keys(body.community).sort(), [
    "active_7d", "badges_today", "hypes_today", "longest_streak", "miles_today",
    "miles_yesterday_same_time", "new_friends_today", "nudges_today", "out_running_now",
    "photos_shared", "tokens_spent_today", "total_hypes", "total_miles", "total_users"]);
  check("community values are all numbers", Object.values(body.community).every((v) => typeof v === "number"), true);
  check("me fields", Object.keys(body.me).sort(), [
    "local_time", "mile_done", "miles_today", "minutes_to_midnight", "running_now", "streak", "username"]);
  const text = JSON.stringify(body);
  check("no emails anywhere", text.includes("@"), false);
  check("no real names anywhere", /Secret|Surname/.test(text), false);
  check("no user ids anywhere", text.includes(P), false);
  check("no notification titles/bodies", /Secret title|Secret body/.test(text), false);

  // ── owner data ──
  check("my mile is done", body.me.mile_done, true);
  check("my miles today", body.me.miles_today, 1.02);
  check("my username", body.me.username, "owner");
  check("local_time shape", /^\d{2}:\d{2}:\d{2}$/.test(body.me.local_time), true);

  // ── friends running: only the one who shares, is fresh, not blocked ──
  check("friends running", body.friends_running, [{ name: "runner", miles: 0.8 }]);
  check("friend item fields", Object.keys(body.friends_running[0] ?? {}).sort(), ["miles", "name"]);

  // ── alerts: mine, last 24h, nudge/hype only, not from blocked ──
  check("alerts", body.alerts.map((a) => [a.kind, a.from]), [["hype", "nudger"], ["nudge", "nudger"]]);
  check("alert fields", Object.keys(body.alerts[0] ?? {}).sort(), ["at", "from", "id", "kind"]);
  check("alert ids are opaque", body.alerts.every((a) => /^[0-9a-f]{16}$/.test(a.id)), true);

  // ── admin endpoints ──
  const admin = (path, method = "GET", user = ADMIN) =>
    fetch(`${base}/admin/${path}`, { method, headers: { "x-test-user": user } });
  check("non-admin cannot list keys", (await admin("display-keys", "GET", OWNER)).status, 403);
  check("non-admin cannot create keys", (await admin("display-keys?username=owner", "POST", OWNER)).status, 403);
  const list = await (await admin("display-keys")).json();
  check("admin list has no hash", JSON.stringify(list).includes(stored[0].key_hash), false);
  check("admin list fields", Object.keys(list.keys[0]).sort(),
    ["created_at", "id", "key_prefix", "label", "last_used_at", "revoked_at", "username"]);
  const created = await admin("display-keys?username=nudger&label=Dave%27s%20desk", "POST");
  check("admin can create for a user", created.status, 201);
  const made = await created.json();
  const nudgerFeed = await feed({ authorization: `Display ${made.key}` });
  check("their key shows THEIR data", (await nudgerFeed.json()).me.username, "nudger");
  check("unknown username → 404", (await admin("display-keys?username=nobody-here", "POST")).status, 404);

  // ── revoke ──
  const id = list.keys.find((k) => k.username === "owner").id;
  check("revoke", (await admin(`display-keys/${id}/revoke`, "POST")).status, 200);
  check("revoked key → 401", (await feed({ authorization: `Display ${key}` })).status, 401);
  check("revoking twice → 404", (await admin(`display-keys/${id}/revoke`, "POST")).status, 404);

  // ── deleting the user kills the key ──
  await db.query(`DELETE FROM users WHERE user_id = $1`, [NUDGER]);
  check("key of a deleted user → 401", (await feed({ authorization: `Display ${made.key}` })).status, 401);

  s.close();
  await cleanup();
  console.log(failures === 0 ? "display-check: all assertions passed" : `display-check: ${failures} FAILED`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch(async (err) => {
  console.error(err);
  await cleanup().catch(() => {});
  process.exit(1);
});
