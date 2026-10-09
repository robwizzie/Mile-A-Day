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
import { createDisplayKey, hashDisplayKey, listDeskBoxes, setReviewSourceForTests } from "../dist/services/displayService.js";

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
const DONE = P + "done";              // friend, finished 5 min ago → finished
const OLDDONE = P + "olddone";        // friend, finished 2 h ago → not shown
const HIDDONE = P + "hiddone";        // friend, finished, opted out → not shown
const STRDONE = P + "strdone";        // not a friend, finished → not shown
const ALL = [OWNER, ADMIN, RUNNER, HIDDEN, BLOCKED, BLOCKER, STALE, STRANGER, NUDGER, OTHER,
             DONE, OLDDONE, HIDDONE, STRDONE];

let failures = 0;
const insertedBadges = [];   // catalog rows this check added (removed again at cleanup)
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  console.log(`${ok ? "ok  " : "FAIL"}  ${label} → ${JSON.stringify(actual)} (expected ${JSON.stringify(expected)})`);
}

async function cleanup() {
  await db.query(`DELETE FROM display_keys WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM desk_settings WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM desk_commands WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM post_comments WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM post_coauthors WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM posts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM display_messages WHERE to_user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM streak_coverage WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM user_badges WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM badges WHERE badge_id = 'display-check-medal'`);
  if (insertedBadges.length) {
    await db.query(`DELETE FROM badges WHERE badge_id = ANY($1::text[])`, [insertedBadges]);
  }
  await db.query(`DELETE FROM in_app_notifications WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM live_tracking_sessions WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM notification_settings WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM user_blocks WHERE blocker_id = ANY($1::text[]) OR blocked_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM friendships WHERE user_id = ANY($1::text[]) OR friend_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM workout_splits WHERE workout_id LIKE $1`, [P + "%"]);
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
  for (const f of [RUNNER, HIDDEN, BLOCKED, BLOCKER, STALE, NUDGER, DONE, OLDDONE, HIDDONE]) {
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
  await db.query(`INSERT INTO notification_settings (user_id, share_live_presence) VALUES ($1, FALSE), ($2, FALSE)`, [HIDDEN, HIDDONE]);
  // Streaks for the "friends at risk" check (everyone else stays at 0).
  for (const [id, st] of [[RUNNER, 40], [NUDGER, 9], [BLOCKED, 50], [BLOCKER, 45], [STRANGER, 60], [DONE, 30], [HIDDEN, 2]]) {
    await db.query(`UPDATE users SET current_streak = $2 WHERE user_id = $1`, [id, st]);
  }
  await db.query(
    `INSERT INTO workouts (workout_id, user_id, distance, local_date, date, timezone_offset,
                           workout_type, device_end_date, calories, total_duration)
     VALUES ($1, $2, 1.1, (NOW() AT TIME ZONE 'UTC')::date, (NOW() AT TIME ZONE 'UTC')::date, 0,
             'running', NOW() - INTERVAL '2 minutes', 100, 600)`,
    [P + "w2", DONE],
  );
  for (const [id, ago] of [[DONE, 5], [OLDDONE, 120], [HIDDONE, 5], [STRDONE, 5]]) {
    await db.query(
      `INSERT INTO live_tracking_sessions (user_id, workout_type, distance_miles, last_seen_at, ended_at)
       VALUES ($1, 'walking', 1.23, NOW() - ($2 || ' minutes')::interval, NOW() - ($2 || ' minutes')::interval)`,
      [id, String(ago)],
    );
  }
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
  // "<friend> got their mile in!" announcements in the owner's inbox.
  const mileNote = (uid, sender, ago) => db.query(
    `INSERT INTO in_app_notifications (user_id, title, body, type, data, created_at)
     VALUES ($1, 'x got their mile in!', '1.10 mi · 10:00', 'friend_activity',
             jsonb_build_object('user_id', $2::text, 'kind', 'mile_completed'),
             NOW() - ($3 || ' minutes')::interval)`,
    [uid, sender, String(ago)],
  );
  await mileNote(OWNER, DONE, 4);                       // shown
  await mileNote(OWNER, BLOCKED, 3);                    // blocked: no
  await mileNote(OWNER, RUNNER, 90);                    // older than an hour: no
  await mileNote(OTHER, DONE, 2);                       // someone else's inbox
  // Owner did 1.02 miles today in their own timezone.
  await db.query(
    `INSERT INTO workouts (workout_id, user_id, distance, local_date, date, timezone_offset,
                           workout_type, device_end_date, calories, total_duration)
     VALUES ($1, $2, 1.02, (NOW() AT TIME ZONE 'UTC')::date, (NOW() AT TIME ZONE 'UTC')::date, 0,
             'running', NOW() - INTERVAL '1 minute', 100, 600)`,
    [P + "w1", OWNER],
  );
  await db.query(
    `INSERT INTO workout_splits (workout_id, split_number, split_duration, split_distance, split_pace)
     VALUES ($1, 1, 480, 1.0, 480), ($1, 2, 6, 0.02, 300), ($1, 3, 200, 1.0, 200)`,
    [P + "w1"],
  );
  // Medals: two that unlock Closet items, one just for the alert.
  const added = await db.query(
    `INSERT INTO badges (badge_id, category, name, description, icon, rarity) VALUES
       ('miles_25', 'miles', 'Quarter Century', 'x', 'x', 'common'),
       ('streak_30', 'streak', 'Month Strong', 'x', 'x', 'common')
     ON CONFLICT (badge_id) DO NOTHING
     RETURNING badge_id`,
  );
  insertedBadges.push(...added.map((r) => r.badge_id));
  await db.query(
    `INSERT INTO badges (badge_id, category, name, description, icon, rarity)
     VALUES ('display-check-medal', 'special', 'Test <b>Medal</b> \u{1F525}', 'x', 'x', 'rare')`,
  );
  for (const b of ["miles_25", "streak_30", "display-check-medal"]) {
    await db.query(`INSERT INTO user_badges (user_id, badge_id) VALUES ($1, $2)`, [OWNER, b]);
  }
  await db.query(`INSERT INTO user_badges (user_id, badge_id) VALUES ($1, 'display-check-medal')`, [OTHER]);
  // Owner's Closet: a colour + cap they own, glasses + cape they DON'T.
  await db.query(
    `UPDATE users SET flamey_look = $2::jsonb WHERE user_id = $1`,
    [OWNER, JSON.stringify({ color: "sapphire", head: "ball_cap", eyes: "aviators", back: "red_cape" })],
  );
  // Posts the owner is tagged in: RUNNER's collab (scalar coauthor) and
  // DONE's buddy post (post_coauthors). Plus NUDGER's post without a tag,
  // and a deleted collab.
  const post = async (author) => (await db.query(
    `INSERT INTO posts (user_id, media_url, local_date)
     VALUES ($1, 'https://example.com/p.jpg', (NOW() AT TIME ZONE 'UTC')::date)
     RETURNING post_id`, [author])).at(0).post_id;
  const collab = await post(RUNNER);
  await db.query(`UPDATE posts SET coauthor_user_id = $2, coauthor_status = 'accepted' WHERE post_id = $1`, [collab, OWNER]);
  const buddy = await post(DONE);
  await db.query(`INSERT INTO post_coauthors (post_id, user_id, status) VALUES ($1, $2, 'accepted')`, [buddy, OWNER]);
  const untagged = await post(NUDGER);
  const gone = await post(RUNNER);
  await db.query(`UPDATE posts SET coauthor_user_id = $2, coauthor_status = 'accepted', deleted_at = NOW() WHERE post_id = $1`, [gone, OWNER]);
  const comment = (postId, who, content, agoMin, deleted = false) => db.query(
    `INSERT INTO post_comments (post_id, user_id, content, created_at, deleted_at)
     VALUES ($1, $2, $3, NOW() - ($4 || ' minutes')::interval, CASE WHEN $5 THEN NOW() END)`,
    [postId, who, content, String(agoMin), deleted],
  );
  await comment(collab, NUDGER, "Nice run \u{1F525} @owner", 5);      // shown
  await comment(buddy, OTHER, "Great walk!", 3);                        // shown
  await comment(collab, OWNER, "thanks", 2);                            // my own: no
  await comment(collab, BLOCKED, "blocked words", 1);                   // blocked: no
  await comment(collab, STRANGER, "old news", 60 * 30);                 // > 24 h: no
  await comment(collab, NUDGER, "deleted words", 1, true);              // deleted: no
  await comment(untagged, OTHER, "not my post", 1);                     // not tagged: no
  await comment(gone, OTHER, "deleted post", 1);                        // post deleted: no
  // A streak token covered the owner's day 3 days ago (heatmap shows -1).
  await db.query(
    `INSERT INTO streak_coverage (user_id, local_date, kind)
     VALUES ($1, ((NOW() AT TIME ZONE 'UTC') - INTERVAL '3 days')::date, 'freeze')`,
    [OWNER],
  );
  // ...and 1.5 miles on this date last year (the "1 year ago today" moment).
  await db.query(
    `INSERT INTO workouts (workout_id, user_id, distance, local_date, date, timezone_offset,
                           workout_type, device_end_date, calories, total_duration)
     VALUES ($1, $2, 1.5, ((NOW() AT TIME ZONE 'UTC') - INTERVAL '1 year')::date,
             ((NOW() AT TIME ZONE 'UTC') - INTERVAL '1 year')::date, 0,
             'running', NOW() - INTERVAL '1 year', 100, 600)`,
    [P + "w0", OWNER],
  );
}

function server() {
  const app = express();
  app.use("/display", displayRoutes);
  // Stand-in for authenticateToken: the header says who the caller is.
  app.use((req, _res, next) => { req.userId = req.headers["x-test-user"]; next(); });
  app.use(express.json());
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
  check("top-level fields", Object.keys(body).sort(), ["alerts", "commands", "comments", "community", "desk", "friends_at_risk", "friends_finished", "friends_miles", "friends_running", "me", "messages", "reviews", "v"]);
  check("community fields", Object.keys(body.community).sort(), [
    "active_7d", "badges_today", "hypes_today", "longest_streak", "miles_today",
    "miles_yesterday_same_time", "new_friends_today", "nudges_today", "out_running_now",
    "photos_shared", "run_miles_today", "run_miles_total", "tokens_spent_today", "total_hypes", "total_miles",
    "total_users", "walk_miles_today", "walk_miles_total"]);
  check("community values are all numbers", Object.values(body.community).every((v) => typeof v === "number"), true);
  check("me fields", Object.keys(body.me).sort(), [
    "days", "fastest_mile_month", "flamey", "live_kind", "live_miles", "local_date", "local_time", "longest_run", "medals",
    "mile_done", "miles_today", "minutes_to_midnight", "running_now", "streak", "username", "year_ago_miles"]);
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
  check("friends running", body.friends_running, [{ name: "runner", miles: 0.8, kind: "run" }]);
  check("friend item fields", Object.keys(body.friends_running[0] ?? {}).sort(), ["kind", "miles", "name"]);

  // ── friends finished: only the friend who shares and finished recently ──
  check("friends finished (a walk)", body.friends_finished.map((f) => [f.name, f.miles, f.kind]), [["done", 1.2, "walk"]]);
  check("finished item fields", Object.keys(body.friends_finished[0] ?? {}).sort(), ["id", "kind", "miles", "name"]);
  check("runs vs walks are miles", ["run_miles_today", "walk_miles_today", "run_miles_total", "walk_miles_total"]
    .every((k) => typeof body.community[k] === "number" && body.community[k] >= 0), true);
  check("all-time runs include ours", body.community.run_miles_total >= 2.1, true);
  check("finished ids are opaque", body.friends_finished.every((f) => /^[0-9a-f]{16}$/.test(f.id)), true);
  check("my miles a year ago", body.me.year_ago_miles, 1.5);
  check("local date shape", /^\d{4}-\d{2}-\d{2}$/.test(body.me.local_date), true);
  check("not running → no live miles", body.me.live_miles, null);
  check("my longest run", body.me.longest_run, 1.5);
  check("my fastest mile this month (full splits only)", body.me.fastest_mile_month, 480);
  check("closet: only owned items, only desk slots", body.me.flamey, { color: "sapphire", head: "ball_cap" });
  check("my new medals", body.me.medals.length, 3);
  check("medal fields", Object.keys(body.me.medals[0] ?? {}).sort(), ["age_s", "id", "name"]);
  check("medal names cleaned", body.me.medals.some((m) => m.name === "TEST BMEDAL/B [FIRE]"), true);
  check("medal ids are opaque", body.me.medals.every((m) => /^[0-9a-f]{16}$/.test(m.id)), true);
  check("no reviews on a non-admin's desk", body.reviews, []);
  check("heatmap: 64 days", body.me.days.length, 64);
  check("heatmap: today is last", body.me.days[63], 1);
  check("heatmap: token-covered day", body.me.days[60], -1);
  check("heatmap: plain numbers only", body.me.days.every((d) => typeof d === "number"), true);
  check("no messages yet", body.messages, []);
  // ── friends who got their mile in: my own announcements, last hour, not blocked ──
  check("friends' miles", body.friends_miles.map((f) => [f.name, f.miles, f.seconds, f.best_pace]),
        [["done", 1.1, 600, 545]]);
  check("friend mile is a run (their latest workout)", body.friends_miles[0]?.kind, "run");
  check("friend mile fields", Object.keys(body.friends_miles[0] ?? {}).sort(), ["age_s", "best_pace", "id", "kind", "miles", "name", "seconds"]);
  check("friend mile ids are opaque", body.friends_miles.every((f) => /^[0-9a-f]{16}$/.test(f.id)), true);
  // ── comments on posts I'm tagged in: newest first, nobody's own/blocked/old/deleted ──
  check("tagged-post comments", body.comments.map((c) => [c.from, c.text]),
        [["other", "GREAT WALK!"], ["nudger", "NICE RUN [FIRE] OWNER"]]);
  check("comment fields", Object.keys(body.comments[0] ?? {}).sort(), ["age_s", "from", "id", "text"]);
  check("comment ids are opaque", body.comments.every((c) => /^[0-9a-f]{16}$/.test(c.id)), true);
  // ── friends at risk: my friends only, streak >= 3, nothing logged today, not blocked ──
  check("friends at risk", body.friends_at_risk, { count: 2, top: [{ name: "runner", streak: 40 }, { name: "nudger", streak: 9 }] });

  // ── alerts: mine, last 24h, nudge/hype only, not from blocked ──
  check("alerts", body.alerts.map((a) => [a.kind, a.from]), [["hype", "nudger"], ["nudge", "nudger"]]);
  check("alert fields", Object.keys(body.alerts[0] ?? {}).sort(), ["at", "from", "id", "kind"]);
  check("alert ids are opaque", body.alerts.every((a) => /^[0-9a-f]{16}$/.test(a.id)), true);

  // ── my own live run ──
  await db.query(
    `INSERT INTO live_tracking_sessions (user_id, workout_type, distance_miles, last_seen_at)
     VALUES ($1, 'running', 0.73, NOW() - INTERVAL '5 seconds')`,
    [OWNER],
  );
  const live = await (await feed({ authorization: `Display ${key}` })).json();
  check("running now → live miles", [live.me.running_now, live.me.live_miles, live.me.live_kind], [true, 0.73, "run"]);
  check("I'm not in my own friends running list", live.friends_running.some((f) => f.name === "owner"), false);

  // ── admin endpoints ──
  const admin = (path, method = "GET", user = ADMIN) =>
    fetch(`${base}/admin/${path}`, { method, headers: { "x-test-user": user } });
  check("non-admin cannot list keys", (await admin("display-keys", "GET", OWNER)).status, 403);
  check("non-admin cannot create keys", (await admin("display-keys?username=owner", "POST", OWNER)).status, 403);
  // Admin -> Displays is split by owner: you make, list and revoke only your own keys.
  check("can't make a key for someone else", (await admin("display-keys?username=nudger", "POST")).status, 403);
  check("…or for a made-up name", (await admin("display-keys?username=nobody-here", "POST")).status, 403);
  const created = await admin("display-keys?label=founder%20desk", "POST");
  check("an admin makes a key for their own account", created.status, 201);
  const mine = await created.json();
  check("…and it shows THEIR data", (await (await feed({ authorization: `Display ${mine.key}` })).json()).me.username, "admin");
  const self = await admin("display-keys?username=ADMIN&label=spare", "POST");
  check("naming yourself is fine", self.status, 201);
  check("…and you can revoke your own", (await admin(`display-keys/${(await self.json()).display_key.id}/revoke`, "POST")).status, 200);
  const list = await (await admin("display-keys")).json();
  check("admin list has no hash", JSON.stringify(list).includes(stored[0].key_hash), false);
  check("admin list fields", Object.keys(list.keys[0]).sort(),
    ["created_at", "id", "key_prefix", "label", "last_used_at", "revoked_at", "username"]);
  check("the key list holds only my own keys", [...new Set(list.keys.map((k) => k.username))], ["admin"]);
  const made = await createDisplayKey(NUDGER, "Dave's desk", NUDGER);
  const nudgerFeed = await feed({ authorization: `Display ${made.key}` });
  check("their key shows THEIR data", (await nudgerFeed.json()).me.username, "nudger");

  // ── App Store reviews: founders' (admins') desks only ──
  setReviewSourceForTests(async () => ({
    feed: {
      entry: [
        { "im:name": { label: "Mile A Day" }, id: { label: "app" } },          // app metadata entry
        { id: { label: "r1" }, "im:rating": { label: "5" }, title: { label: "Love it! <3 \u{1F525}" },
          author: { name: { label: "Jane Q Public" } }, content: { label: "secret body" } },
        { id: { label: "r2" }, "im:rating": { label: "4" }, title: { label: "great app" } },
        { id: { label: "r3" }, "im:rating": { label: "9" }, title: { label: "bogus rating" } },
      ],
    },
  }));
  const adminKey = mine.key;
  const adminFeed = await (await feed({ authorization: `Display ${adminKey}` })).json();
  check("admin desk gets reviews", adminFeed.reviews.map((r) => [r.stars, r.title]),
    [[5, "LOVE IT! 3 [FIRE]"], [4, "GREAT APP"]]);
  check("review fields (no author, no body)", Object.keys(adminFeed.reviews[0] ?? {}).sort(), ["id", "stars", "title"]);
  check("no reviewer names anywhere", JSON.stringify(adminFeed).includes("Jane"), false);
  const ownerAgain = await (await feed({ authorization: `Display ${key}` })).json();
  check("still no reviews for a non-admin", ownerAgain.reviews, []);

  // ── desk messages ──
  const sendMsg = (body, user = ADMIN) => fetch(`${base}/admin/display-messages`, {
    method: "POST",
    headers: { "x-test-user": user, "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  check("non-admin cannot send a desk message", (await sendMsg({ username: "owner", text: "hi" }, OWNER)).status, 403);
  check("non-admin cannot list desk messages", (await admin("display-messages", "GET", OWNER)).status, 403);
  check("empty message → 400", (await sendMsg({ username: "owner", text: "<<>> \u{1F600}" })).status, 400);
  check("unknown recipient → 404", (await sendMsg({ username: "nobody-here", text: "hi" })).status, 404);
  const sent = await sendMsg({ username: "owner", text: "nice mile \u{1F525} <script>alert(1)</script> \u2764\uFE0F" });
  check("admin can send a desk message", sent.status, 201);
  check("message is cleaned for the panel", (await sent.json()).message.body, "NICE MILE [FIRE] SCRIPTALERT1/SCRIPT [HEART]");
  await sendMsg({ username: "other", text: "not for you" });
  await db.query(
    `INSERT INTO display_messages (to_user_id, body, expires_at) VALUES ($1, 'OLD', NOW() - INTERVAL '1 minute')`,
    [OWNER],
  );
  const withMsg = await (await feed({ authorization: `Display ${key}` })).json();
  check("my desk gets only my unexpired message", withMsg.messages.map((m) => [m.from, m.text]),
    [["admin", "NICE MILE [FIRE] SCRIPTALERT1/SCRIPT [HEART]"]]);
  check("message fields", Object.keys(withMsg.messages[0] ?? {}).sort(), ["age_s", "from", "id", "text"]);
  check("message ids are opaque", withMsg.messages.every((m) => /^[0-9a-f]{16}$/.test(m.id)), true);
  const msgList = await (await admin("display-messages")).json();
  check("admin can list desk messages", msgList.messages.length >= 2, true);
  check("…only ones to or from me", msgList.messages.every((m) => m.from_username === "admin" || m.to_username === "admin"), true);
  check("message recipients: other desk owners, by name", msgList.recipients.includes("owner") && !msgList.recipients.includes("admin"), true);

  // ── the desk remote: per box ──
  check("no remote settings yet", withMsg.desk, null);
  check("no remote taps yet", withMsg.commands, []);
  const post = (path, body, user = ADMIN) => fetch(`${base}/admin/${path}`, {
    method: "POST",
    headers: { "x-test-user": user, "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  check("non-admin cannot list boxes", (await admin("desk/boxes", "GET", OWNER)).status, 403);
  const allBoxes = (await listDeskBoxes()).map((b) => [b.username, b.id]);
  const ownerBox = allBoxes.find(([u]) => u === "owner")[1];
  const adminBox = allBoxes.find(([u]) => u === "admin")[1];
  check("non-admin cannot read a box", (await admin(`desk/box/${ownerBox}`, "GET", OWNER)).status, 403);
  check("non-admin cannot set a style", (await post(`desk/box/${ownerBox}/settings`, { style: 1 }, OWNER)).status, 403);
  // Two founders, each signed in with their own account: each sees and
  // controls only their own box.
  await db.query(`UPDATE users SET role = 'admin' WHERE user_id = $1`, [OWNER]);
  const boxes = (await (await admin("desk/boxes")).json()).boxes;
  check("box fields", Object.keys(boxes[0] ?? {}).sort(), ["id", "label", "last_seen", "online", "state", "username"]);
  check("an admin lists only their own box", boxes.map((b) => b.username), ["admin"]);
  check("the other admin lists only theirs", (await (await admin("desk/boxes", "GET", OWNER)).json()).boxes.map((b) => b.username), ["owner"]);
  check("no key hashes in the box list", JSON.stringify(boxes).includes(stored[0].key_hash), false);
  check("can't read someone else's box", (await admin(`desk/box/${ownerBox}`)).status, 404);
  check("can't change someone else's box", (await post(`desk/box/${ownerBox}/settings`, { style: 1 })).status, 404);
  check("can't send junk to someone else's box either", (await post(`desk/box/${ownerBox}/settings`, { style: 99 })).status, 404);
  check("can't show on someone else's box", (await post(`desk/box/${ownerBox}/show`, {})).status, 404);
  check("can't wake someone else's box", (await post(`desk/box/${ownerBox}/wake`, {})).status, 404);
  check("can't message as someone else's box", (await post(`desk/box/${ownerBox}/message`, { to: adminBox, text: "hi" })).status, 404);
  check("…and the owner can't touch the admin's", (await post(`desk/box/${adminBox}/settings`, { style: 1 }, OWNER)).status, 404);
  check("unknown box → 404", (await admin("desk/box/00000000-0000-0000-0000-000000000000")).status, 404);
  check("garbage box id → 404", (await admin("desk/box/x';drop")).status, 404);
  check("bad style → 400", (await post(`desk/box/${ownerBox}/settings`, { style: 9 }, OWNER)).status, 400);
  check("nothing to set → 400", (await post(`desk/box/${ownerBox}/settings`, {}, OWNER)).status, 400);
  check("style string → 400", (await post(`desk/box/${ownerBox}/settings`, { style: "2" }, OWNER)).status, 400);
  check("set owner's box", (await (await post(`desk/box/${ownerBox}/settings`, { style: 2, mascot: 0 }, OWNER)).json()).settings,
        { style: 2, mascot: 0, rev: 1, sleep_start: null, sleep_end: null, never_sleep: false });
  check("set mascot keeps style", (await (await post(`desk/box/${ownerBox}/settings`, { mascot: 1 }, OWNER)).json()).settings,
        { style: 2, mascot: 1, rev: 2, sleep_start: null, sleep_end: null, never_sleep: false });
  check("bad sleep → 400", (await post(`desk/box/${ownerBox}/settings`, { sleep: { start: 1500, end: 420 } }, OWNER)).status, 400);
  check("same start/end → 400", (await post(`desk/box/${ownerBox}/settings`, { sleep: { start: 60, end: 60 } }, OWNER)).status, 400);
  check("sleep string → 400", (await post(`desk/box/${ownerBox}/settings`, { sleep: "nap" }, OWNER)).status, 400);
  check("set sleep hours (no rev bump)", (await (await post(`desk/box/${ownerBox}/settings`, { sleep: { start: 1350, end: 390 } }, OWNER)).json()).settings,
        { style: 2, mascot: 1, rev: 2, sleep_start: 1350, sleep_end: 390, never_sleep: false });
  check("never sleep", (await (await post(`desk/box/${ownerBox}/settings`, { sleep: "never" }, OWNER)).json()).settings.never_sleep, true);
  check("back to the box's own hours", (await (await post(`desk/box/${ownerBox}/settings`, { sleep: "default" }, OWNER)).json()).settings,
        { style: 2, mascot: 1, rev: 2, sleep_start: null, sleep_end: null, never_sleep: false });
  await post(`desk/box/${ownerBox}/settings`, { sleep: { start: 1350, end: 390 } }, OWNER);
  check("stat show on owner's box", (await post(`desk/box/${ownerBox}/show`, {}, OWNER)).status, 201);
  check("wake owner's box", (await post(`desk/box/${ownerBox}/wake`, {}, OWNER)).status, 201);
  check("unknown tap → 404", (await post(`desk/box/${ownerBox}/party`, {}, OWNER)).status, 404);
  // The box reports its screen with each poll; junk is ignored.
  await feed({ authorization: `Display ${key}`, "x-desk-state": "2,1,0,1350,390" });
  await feed({ authorization: `Display ${adminKey}`, "x-desk-state": "9,9,9,'; drop" });
  const reported = (await (await admin("desk/boxes")).json()).boxes;
  check("box state reported", (await (await admin("desk/boxes", "GET", OWNER)).json()).boxes[0].state,
        { style: 2, mascot: 1, awake: false, sleep_start: 1350, sleep_end: 390 });
  check("junk state ignored", reported.find((b) => b.username === "admin").state, null);
  check("old play endpoint is gone", (await post("desk/play", { kind: "nudge" })).status, 404);
  const ownerFeedBox = await (await feed({ authorization: `Display ${key}` })).json();
  check("that box gets its settings", ownerFeedBox.desk,
        { style: 2, mascot: 1, rev: 2, sleep_start: 1350, sleep_end: 390, never_sleep: false });
  check("that box gets the taps", ownerFeedBox.commands.map((c) => c.kind).sort(), ["show", "wake"]);
  check("tap ids are opaque", ownerFeedBox.commands.every((c) => /^[0-9a-f]{16}$/.test(c.id)), true);
  const adminFeed3 = await (await feed({ authorization: `Display ${adminKey}` })).json();
  check("another box gets none of it", [adminFeed3.desk, adminFeed3.commands], [null, []]);
  const sentBox = await post(`desk/box/${adminBox}/message`, { to: ownerBox, text: "go run \u{1F3C3}" });
  check("box-to-box message", sentBox.status, 201);
  check("message to unknown box → 404", (await post(`desk/box/${adminBox}/message`, { to: "nope", text: "hi" })).status, 404);
  const detail = await (await admin(`desk/box/${ownerBox}`, "GET", OWNER)).json();
  check("box detail: the box", [detail.box.username, detail.box.online], ["owner", true]);
  check("box detail: settings", detail.settings, { style: 2, mascot: 1, rev: 2, sleep_start: 1350, sleep_end: 390, never_sleep: false });
  check("box detail: state", detail.box.state.awake, false);
  check("box detail: recipients are other people's boxes", detail.recipients.map((b) => b.username).sort(), ["admin", "nudger"]);
  check("recipients carry a name only", Object.keys(detail.recipients[0] ?? {}).sort(), ["id", "label", "username"]);
  check("box detail: messages in", detail.messages.filter((m) => m.direction === "in" && m.who === "admin").map((m) => [m.who, m.text]),
        [["admin", "GO RUN [RUN]"], ["admin", "NICE MILE [FIRE] SCRIPTALERT1/SCRIPT [HEART]"]]);
  check("box detail: live is the owner's own feed", detail.live.me.username, "owner");
  const kinds = new Set(detail.activity.map((x) => x.kind));
  check("activity: nudges, hypes, messages, medals, runs, friend runs, remote", 
        ["nudge", "hype", "message_in", "medal", "run", "friend_run", "friend_mile", "remote"].every((k) => kinds.has(k)), true);
  check("activity: no blocked sender", detail.activity.some((x) => x.text.includes("blocked")), false);
  check("activity: remote changes logged", detail.activity.filter((x) => x.kind === "remote").map((x) => x.text).sort(),
        ["Changed from the remote: ARCADE / FLAMEY", "Changed from the remote: ARCADE / RUNNER",
         "Changed from the remote: never sleeps", "Changed from the remote: sleep hours back to the box's own",
         "Changed from the remote: sleeps 22:30–06:30", "Changed from the remote: sleeps 22:30–06:30",
         "Stat show started from the remote", "Woken up from the remote"]);
  check("activity: no emails or real names", /@example\.com|Secret|Surname/.test(JSON.stringify(detail.activity)), false);
  check("box detail: no key hashes", JSON.stringify(detail).includes(stored[0].key_hash), false);
  for (let i = 0; i < 30; i++) await post(`desk/box/${ownerBox}/show`, {}, OWNER);
  check("taps are rate-limited", (await post(`desk/box/${ownerBox}/show`, {}, OWNER)).status, 429);

  // ── revoke ──
  const id = (await (await admin("display-keys", "GET", OWNER)).json()).keys.find((k) => k.username === "owner").id;
  check("can't revoke someone else's key", (await admin(`display-keys/${id}/revoke`, "POST")).status, 404);
  check("still working after that", (await feed({ authorization: `Display ${key}` })).status, 200);
  check("revoke my own", (await admin(`display-keys/${id}/revoke`, "POST", OWNER)).status, 200);
  check("revoked key → 401", (await feed({ authorization: `Display ${key}` })).status, 401);
  check("revoking twice → 404", (await admin(`display-keys/${id}/revoke`, "POST", OWNER)).status, 404);

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
