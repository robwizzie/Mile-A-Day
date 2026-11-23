/**
 * "Tell me when they're out" (`buddyOutAlertService`).
 *
 *   1. Only a friend can be followed; turning it off always works.
 *   2. A walk start pings followers once per friend per day.
 *   3. Nobody who didn't ask is pinged (friends-out stays pull-only).
 *   4. A walker who doesn't share live presence pings nobody.
 *   5. A block either way stops it.
 *   6. The recipient's buddy switch off stops it.
 *   7. The push only rings devices that declare `buddy_out_alert_v1`.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/buddy-out-alert-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import {
  listOutAlerts,
  notifyOutAlertSubscribers,
  setOutAlert,
} from "../dist/services/buddyOutAlertService.js";

const db = PostgresService.getInstance();

const WALKER = "out-walker";
const FAN = "out-fan"; // follows the walker
const OTHER = "out-other"; // a friend who didn't ask
const MUTED = "out-muted"; // follows, buddy pushes off
const STRANGER = "out-stranger";
const ALL = [WALKER, FAN, OTHER, MUTED, STRANGER];
const FRIENDS = [WALKER, FAN, OTHER, MUTED];

let failures = 0;
function check(label, actual, expected) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${actual} (expected ${expected})`,
  );
}

async function errorCode(fn) {
  try {
    await fn();
    return null;
  } catch (e) {
    return e?.message ?? String(e);
  }
}

async function cleanup() {
  await db.query(
    `DELETE FROM in_app_notifications WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(
    `DELETE FROM buddy_out_alert_log WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(
    `DELETE FROM buddy_out_alerts WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM user_blocks WHERE blocker_id = ANY($1::text[])`, [
    ALL,
  ]);
  await db.query(
    `DELETE FROM notification_settings WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM device_tokens WHERE user_id = ANY($1::text[])`, [
    ALL,
  ]);
  await db.query(`DELETE FROM friendships WHERE user_id = ANY($1::text[])`, [
    ALL,
  ]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1::text[])`, [ALL]);
}

async function seed() {
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, apple_sub, email, username, first_name, last_name, buddy_enrolled_at)
       VALUES ($1, $2, $3, $4, $5, 'Out', NOW()) ON CONFLICT (user_id) DO NOTHING`,
      [id, `sub-${id}`, `${id}@example.com`, id, id],
    );
  }
  for (const a of FRIENDS) {
    for (const b of FRIENDS) {
      if (a === b) continue;
      await db.query(
        `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, 'accepted')
         ON CONFLICT (user_id, friend_id) DO NOTHING`,
        [a, b],
      );
    }
  }
}

async function inbox(userId) {
  const rows = await db.query(
    `SELECT COUNT(*)::int AS n FROM in_app_notifications
      WHERE user_id = $1 AND type = 'buddy_friend_out'`,
    [userId],
  );
  return Number(rows[0]?.n ?? 0);
}

async function main() {
  await cleanup();
  await seed();

  // ─── 1. Follow rules ───
  check("following a friend works", await setOutAlert(FAN, WALKER, true), true);
  check("following twice is fine", await setOutAlert(FAN, WALKER, true), true);
  check(
    "a stranger can't be followed",
    await errorCode(() => setOutAlert(STRANGER, WALKER, true)),
    "not_friends",
  );
  check("the list has them", (await listOutAlerts(FAN)).join(","), WALKER);
  await setOutAlert(MUTED, WALKER, true);
  await db.query(
    `INSERT INTO notification_settings (user_id, buddy_invites_enabled) VALUES ($1, false)
     ON CONFLICT (user_id) DO UPDATE SET buddy_invites_enabled = false`,
    [MUTED],
  );

  // ─── 2 + 3 + 6. A start ───
  check(
    "a start pings the follower (muted one skipped)",
    await notifyOutAlertSubscribers(WALKER, "walking"),
    1,
  );
  check("the follower has it", await inbox(FAN), 1);
  check("a friend who didn't ask has nothing", await inbox(OTHER), 0);
  check("a follower with buddy pushes off has nothing", await inbox(MUTED), 0);
  check(
    "a second start the same day sends nothing",
    await notifyOutAlertSubscribers(WALKER, "walking"),
    0,
  );
  check("still one", await inbox(FAN), 1);

  // ─── 4. Presence off ───
  await db.query(`DELETE FROM buddy_out_alert_log WHERE friend_id = $1`, [
    WALKER,
  ]);
  await db.query(
    `INSERT INTO notification_settings (user_id, share_live_presence) VALUES ($1, false)
     ON CONFLICT (user_id) DO UPDATE SET share_live_presence = false`,
    [WALKER],
  );
  check(
    "a walker not sharing presence pings nobody",
    await notifyOutAlertSubscribers(WALKER, "walking"),
    0,
  );
  await db.query(
    `UPDATE notification_settings SET share_live_presence = true WHERE user_id = $1`,
    [WALKER],
  );

  // ─── 5. Block ───
  await db.query(
    `INSERT INTO user_blocks (blocker_id, blocked_id) VALUES ($1, $2)`,
    [WALKER, FAN],
  );
  check(
    "a block stops it",
    await notifyOutAlertSubscribers(WALKER, "walking"),
    0,
  );
  await db.query(`DELETE FROM user_blocks WHERE blocker_id = $1`, [WALKER]);

  // ─── 1b. Off ───
  check("turning it off works", await setOutAlert(FAN, WALKER, false), false);
  check("...and the list is empty", (await listOutAlerts(FAN)).length, 0);

  await cleanup();
  console.log(
    failures === 0
      ? "buddy-out-alert-check: all assertions passed"
      : `buddy-out-alert-check: ${failures} FAILED`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch(async (err) => {
  console.error(err);
  await cleanup().catch(() => {});
  process.exit(1);
});
