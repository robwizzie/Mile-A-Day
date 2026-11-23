/**
 * Nearby friends over Bluetooth (`buddyNearbyService`).
 *
 *   1. A token is 8 hex chars, reused while it has time left.
 *   2. Resolving returns only the caller's FRIENDS; a stranger's token, an
 *      expired one and junk input resolve to nothing.
 *   3. A block either way hides them.
 *   4. `share_live_presence` is symmetric: off = no token issued, and an
 *      off caller sees nobody.
 *   5. Clearing stops the token resolving.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/buddy-nearby-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import {
  clearNearbyTokens,
  issueNearbyToken,
  resolveNearbyTokens,
} from "../dist/services/buddyNearbyService.js";

const db = PostgresService.getInstance();

const ME = "near-me";
const PAL = "near-pal";
const STRANGER = "near-stranger";
const SHY = "near-shy"; // friend, doesn't share presence
const ALL = [ME, PAL, STRANGER, SHY];

let failures = 0;
function check(label, actual, expected) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${actual} (expected ${expected})`,
  );
}

async function cleanup() {
  await db.query(
    `DELETE FROM buddy_nearby_tokens WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM user_blocks WHERE blocker_id = ANY($1::text[])`, [
    ALL,
  ]);
  await db.query(
    `DELETE FROM notification_settings WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM friendships WHERE user_id = ANY($1::text[])`, [
    ALL,
  ]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1::text[])`, [ALL]);
}

async function seed() {
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, apple_sub, email, username, first_name, last_name, buddy_enrolled_at)
       VALUES ($1, $2, $3, $4, $5, 'Near', NOW()) ON CONFLICT (user_id) DO NOTHING`,
      [id, `sub-${id}`, `${id}@example.com`, id, id],
    );
  }
  for (const [a, b] of [
    [ME, PAL],
    [PAL, ME],
    [ME, SHY],
    [SHY, ME],
  ]) {
    await db.query(
      `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, 'accepted')
       ON CONFLICT (user_id, friend_id) DO NOTHING`,
      [a, b],
    );
  }
}

const ids = (rows) =>
  rows
    .map((r) => r.user_id)
    .sort()
    .join(",");

async function main() {
  await cleanup();
  await seed();

  // ─── 1. Tokens ───
  const mine = await issueNearbyToken(ME);
  check(
    "a token is 8 hex characters",
    /^[0-9a-f]{8}$/.test(mine?.token ?? ""),
    true,
  );
  check(
    "asking again reuses it",
    (await issueNearbyToken(ME))?.token,
    mine?.token,
  );
  const pal = await issueNearbyToken(PAL);
  const stranger = await issueNearbyToken(STRANGER);

  // ─── 2. Resolve ───
  check(
    "a friend's token resolves to them",
    ids(await resolveNearbyTokens(ME, [pal.token])),
    PAL,
  );
  check(
    "...echoing the token they were heard by",
    (await resolveNearbyTokens(ME, [pal.token]))[0]?.token,
    pal.token,
  );
  check(
    "a stranger's token resolves to nothing",
    ids(await resolveNearbyTokens(ME, [stranger.token])),
    "",
  );
  check(
    "my own token isn't me",
    ids(await resolveNearbyTokens(ME, [mine.token])),
    "",
  );
  check(
    "junk is ignored",
    ids(
      await resolveNearbyTokens(ME, ["zz", 7, null, pal.token.toUpperCase()]),
    ),
    PAL,
  );
  await db.query(
    `UPDATE buddy_nearby_tokens SET expires_at = NOW() - INTERVAL '1 minute' WHERE user_id = $1`,
    [PAL],
  );
  check(
    "an expired token resolves to nothing",
    ids(await resolveNearbyTokens(ME, [pal.token])),
    "",
  );
  const pal2 = await issueNearbyToken(PAL);
  check("an expired token is replaced", pal2.token !== pal.token, true);

  // ─── 3. Blocks ───
  await db.query(
    `INSERT INTO user_blocks (blocker_id, blocked_id) VALUES ($1, $2)`,
    [PAL, ME],
  );
  check(
    "a block hides them",
    ids(await resolveNearbyTokens(ME, [pal2.token])),
    "",
  );
  await db.query(`DELETE FROM user_blocks WHERE blocker_id = $1`, [PAL]);

  // ─── 4. Presence is symmetric ───
  await db.query(
    `INSERT INTO notification_settings (user_id, share_live_presence) VALUES ($1, false)
     ON CONFLICT (user_id) DO UPDATE SET share_live_presence = false`,
    [SHY],
  );
  check(
    "no token for someone not sharing presence",
    await issueNearbyToken(SHY),
    null,
  );
  await db.query(
    `INSERT INTO notification_settings (user_id, share_live_presence) VALUES ($1, false)
     ON CONFLICT (user_id) DO UPDATE SET share_live_presence = false`,
    [ME],
  );
  check(
    "a caller not sharing sees nobody",
    ids(await resolveNearbyTokens(ME, [pal2.token])),
    "",
  );
  await db.query(
    `UPDATE notification_settings SET share_live_presence = true WHERE user_id = $1`,
    [ME],
  );

  // ─── 5. Clear ───
  await clearNearbyTokens(PAL);
  check(
    "a cleared token stops resolving",
    ids(await resolveNearbyTokens(ME, [pal2.token])),
    "",
  );

  await cleanup();
  console.log(
    failures === 0
      ? "buddy-nearby-check: all assertions passed"
      : `buddy-nearby-check: ${failures} FAILED`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch(async (err) => {
  console.error(err);
  await cleanup().catch(() => {});
  process.exit(1);
});
