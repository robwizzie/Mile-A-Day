/**
 * Buddy "looking for a buddy right now" check.
 *
 * The heartbeat behind the buddy setup's first screen: two friends who both
 * open it see each other ("Alex is looking too"). Every person it returns is
 * one tap from an invite, so it must hold the invite picker's gates and the
 * live-presence opt-out. A leak here tells someone who is out looking for
 * company right now, which is exactly the fact the gates exist to protect.
 *
 * Covers, against a real migrated database:
 *   1. friends looking within the window are returned; you never see yourself
 *   2. a stale heartbeat (past BUDDY_LOOKING_WINDOW_SECONDS) stops counting
 *   3. non-friends, blocks (either way), unenrolled and opted-out users never
 *      appear
 *   4. share_live_presence = false is symmetric: not recorded, sees nobody
 *   5. clearLooking takes you out immediately
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/buddy-looking-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import {
  BUDDY_LOOKING_WINDOW_SECONDS,
  clearLooking,
  markLookingAndList,
} from "../dist/services/buddyLookingService.js";

const db = PostgresService.getInstance();

const ME = "looking-check-me";
const PAL = "looking-check-pal";
const STRANGER = "looking-check-stranger";
const BLOCKED = "looking-check-blocked";
const BLOCKER = "looking-check-blocker";
const UNENROLLED = "looking-check-unenrolled";
const OPTED_OUT = "looking-check-optout";
const HIDDEN = "looking-check-hidden";
const STALE = "looking-check-stale";
const ALL = [ME, PAL, STRANGER, BLOCKED, BLOCKER, UNENROLLED, OPTED_OUT, HIDDEN, STALE];
const FRIENDS = ALL.filter((id) => id !== ME && id !== STRANGER);

let failures = 0;
function check(label, actual, expected) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(`${ok ? "ok  " : "FAIL"}  ${label} → ${actual} (expected ${expected})`);
}

async function cleanup() {
  await db.query(`DELETE FROM buddy_looking WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM user_blocks WHERE blocker_id = ANY($1::text[]) OR blocked_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM friendships WHERE user_id = ANY($1::text[]) OR friend_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM notification_settings WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1::text[])`, [ALL]);
}

async function seed() {
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, apple_sub, email, username, first_name, last_name)
       VALUES ($1, $2, $3, $4, $5, 'Looking')
       ON CONFLICT (user_id) DO NOTHING`,
      [id, `sub-${id}`, `${id}@example.com`, id, id],
    );
  }
  await db.query(
    `UPDATE users SET buddy_enrolled_at = NOW()
      WHERE user_id = ANY($1::text[]) AND user_id <> $2`,
    [ALL, UNENROLLED],
  );
  for (const id of FRIENDS) {
    for (const [a, b] of [[ME, id], [id, ME]]) {
      await db.query(
        `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, 'accepted')
         ON CONFLICT (user_id, friend_id) DO NOTHING`,
        [a, b],
      );
    }
  }
  await db.query(`INSERT INTO user_blocks (blocker_id, blocked_id) VALUES ($1, $2)`, [ME, BLOCKED]);
  await db.query(`INSERT INTO user_blocks (blocker_id, blocked_id) VALUES ($1, $2)`, [BLOCKER, ME]);
  await db.query(
    `INSERT INTO notification_settings (user_id, buddy_invites_enabled) VALUES ($1, FALSE)`,
    [OPTED_OUT],
  );
  await db.query(
    `INSERT INTO notification_settings (user_id, share_live_presence) VALUES ($1, FALSE)`,
    [HIDDEN],
  );
}

async function main() {
  await cleanup();
  await seed();

  // Everyone else is looking (HIDDEN tries too, and must not be recorded).
  for (const id of ALL.filter((x) => x !== ME)) {
    await markLookingAndList(id, "walking");
  }
  await db.query(
    `UPDATE buddy_looking SET looking_at = NOW() - make_interval(secs => $2)
      WHERE user_id = $1`,
    [STALE, BUDDY_LOOKING_WINDOW_SECONDS + 30],
  );

  const seen = new Set((await markLookingAndList(ME, "running")).map((f) => f.user_id));
  check("a friend looking now is returned", seen.has(PAL), true);
  check("you never see yourself", seen.has(ME), false);
  check("a stale heartbeat no longer counts", seen.has(STALE), false);
  check("a non-friend never appears", seen.has(STRANGER), false);
  check("someone you blocked never appears", seen.has(BLOCKED), false);
  check("someone who blocked you never appears", seen.has(BLOCKER), false);
  check("a build without buddy walks never appears", seen.has(UNENROLLED), false);
  check("a buddy-invites opt-out never appears", seen.has(OPTED_OUT), false);
  check("a live-presence opt-out never appears", seen.has(HIDDEN), false);

  const hiddenRow = await db.query(`SELECT 1 FROM buddy_looking WHERE user_id = $1`, [HIDDEN]);
  check("a live-presence opt-out is not even recorded", hiddenRow.length, 0);
  check("…and sees nobody", (await markLookingAndList(HIDDEN, "walking")).length, 0);

  const palSees = new Set((await markLookingAndList(PAL, "walking")).map((f) => f.user_id));
  check("it is mutual: the friend sees you back", palSees.has(ME), true);
  const meRow = (await markLookingAndList(PAL, "walking")).find((f) => f.user_id === ME);
  check("activity type rides along", meRow?.activity_type, "running");

  await clearLooking(ME);
  const after = new Set((await markLookingAndList(PAL, "walking")).map((f) => f.user_id));
  check("clearLooking takes you out at once", after.has(ME), false);

  await cleanup();
  console.log(
    failures === 0
      ? "buddy-looking-check: all assertions passed"
      : `buddy-looking-check: ${failures} FAILED`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch(async (err) => {
  console.error(err);
  await cleanup().catch(() => {});
  process.exit(1);
});
