/**
 * Buddy Walks history check.
 *
 * `GET /buddy/history` is a browsable archive of walks you took with other
 * people, and almost everything that can go wrong with it goes wrong SILENTLY:
 * a walk quietly missing from the list, someone's name still rendering after
 * they un-friended you, a photo reachable from the history that the feed would
 * refuse, or a keyset cursor that repeats a row on page 2. None of those throw.
 *
 * Covers, against a real migrated database:
 *   1. what enters the archive (both finished, session completed, someone else
 *      was actually there) and what must not
 *   2. per-viewer roster gating — blocked participants dropped, un-friended
 *      ones anonymised, group total unchanged either way
 *   3. photos resolved through postService's shared post-access guard, so a
 *      post that leaves the feed leaves the history with it
 *   4. keyset pagination: no repeats, no gaps, and no cursor at the end
 *   5. the friend filter narrowing the list AND the totals together
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/buddy-history-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import {
  getBuddyHistory,
  getBuddyHistoryTotals,
} from "../dist/services/buddySessionService.js";

const db = PostgresService.getInstance();

const ME = "buddy-hist-me";
const PAL = "buddy-hist-pal";
const EX = "buddy-hist-ex"; // walked with, later un-friended
const FOE = "buddy-hist-foe"; // walked with, later blocked
const ALL = [ME, PAL, EX, FOE];

let failures = 0;
function check(label, actual, expected) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${actual} (expected ${expected})`,
  );
}

async function seed() {
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, apple_sub, email, username, first_name, last_name)
       VALUES ($1, $2, $3, $4, $5, 'Walker')
       ON CONFLICT (user_id) DO NOTHING`,
      [id, `sub-${id}`, `${id}@example.com`, id, id],
    );
  }
  for (const id of [PAL, EX, FOE]) {
    for (const [a, b] of [
      [ME, id],
      [id, ME],
    ]) {
      await db.query(
        `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, 'accepted')
         ON CONFLICT (user_id, friend_id) DO NOTHING`,
        [a, b],
      );
    }
  }
}

async function cleanup() {
  await db.query(`DELETE FROM post_coauthors WHERE user_id = ANY($1::text[])`, [
    ALL,
  ]);
  await db.query(`DELETE FROM posts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(
    `DELETE FROM buddy_session_participants WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(
    `DELETE FROM buddy_sessions WHERE host_user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(
    `DELETE FROM user_blocks WHERE blocker_id = ANY($1::text[]) OR blocked_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(
    `DELETE FROM friendships WHERE user_id = ANY($1::text[]) OR friend_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM users WHERE user_id = ANY($1::text[])`, [ALL]);
}

/**
 * A finished walk `daysAgo` days back. Ended times are spread so the keyset
 * order is deterministic — two rows sharing an `ended_at` would make "page 2
 * repeats a row" a coin flip rather than a test.
 */
async function seedWalk({ code, daysAgo, others, status = "completed" }) {
  const rows = await db.query(
    `INSERT INTO buddy_sessions
       (join_code, host_user_id, mode, activity_type, status, origin,
        local_date, started_at, ended_at)
     VALUES ($1, $2, 'together', 'walking', $3, 'invite',
             (CURRENT_DATE - ($4 || ' days')::interval)::date,
             NOW() - ($4 || ' days')::interval,
             NOW() - ($4 || ' days')::interval + INTERVAL '40 minutes')
     RETURNING id`,
    [code, ME, status, String(daysAgo)],
  );
  const sessionId = rows[0].id;
  await db.query(
    `INSERT INTO buddy_session_participants
       (session_id, user_id, status, final_distance_miles, duration_seconds)
     VALUES ($1, $2, 'finished', 1.5, 2400)`,
    [sessionId, ME],
  );
  for (const {
    userId,
    status: theirStatus = "finished",
    miles = 1.4,
  } of others) {
    await db.query(
      `INSERT INTO buddy_session_participants
         (session_id, user_id, status, final_distance_miles, duration_seconds)
       VALUES ($1, $2, $3, $4, 2400)`,
      [sessionId, userId, theirStatus, miles],
    );
  }
  return sessionId;
}

/** A feed post credited to the whole walk, exactly as the post wizard writes it. */
async function seedWalkPhoto(sessionId, authorId, coauthorIds, overrides = {}) {
  const rows = await db.query(
    `INSERT INTO posts (user_id, media_url, caption, workout_id, local_date,
                        share_to_feed, is_auto)
     VALUES ($1, $2, 'us, out there', NULL, CURRENT_DATE - INTERVAL '2 days',
             $3, FALSE)
     RETURNING post_id`,
    [
      authorId,
      `/uploads/posts/${sessionId}.jpg`,
      overrides.shareToFeed ?? true,
    ],
  );
  const postId = rows[0].post_id;
  for (const userId of coauthorIds) {
    await db.query(
      `INSERT INTO post_coauthors (post_id, user_id, status, buddy_session_id)
       VALUES ($1, $2, 'accepted', $3)`,
      [postId, userId, sessionId],
    );
  }
  return postId;
}

async function main() {
  await cleanup();
  await seed();

  // ── 1. What enters the archive ──────────────────────────────────────
  const withPal = await seedWalk({
    code: "HIST01",
    daysAgo: 2,
    others: [{ userId: PAL }],
  });
  // Nobody else finished it: a room you opened and then walked alone is a solo
  // walk that happened to have a lobby, and counting it would make the
  // "miles together" headline mean two different things at once.
  await seedWalk({
    code: "HIST02",
    daysAgo: 3,
    others: [{ userId: PAL, status: "left" }],
  });
  // Still running — an archive is for walks that are over.
  await seedWalk({
    code: "HIST03",
    daysAgo: 0,
    others: [{ userId: PAL }],
    status: "active",
  });

  let page = await getBuddyHistory(ME, {});
  check("only the shared, completed walk is listed", page.sessions.length, 1);
  check("it's the right walk", page.sessions[0]?.id, withPal);
  check(
    "the roster carries both walkers",
    page.sessions[0]?.participants.length,
    2,
  );
  check(
    "the group total pools both distances",
    page.sessions[0]?.group_distance_miles,
    2.9,
  );
  check(
    "my own miles are mine alone",
    page.sessions[0]?.my_distance_miles,
    1.5,
  );

  let totals = await getBuddyHistoryTotals(ME);
  check("totals count the walk", totals.walks, 1);
  check("totals carry the viewer's own miles", totals.miles, 1.5);
  check("totals count distinct partners", totals.partners, 1);

  // ── 2. Roster gating is per-viewer ──────────────────────────────────
  const withEx = await seedWalk({
    code: "HIST04",
    daysAgo: 4,
    others: [{ userId: EX }],
  });
  await db.query(
    `DELETE FROM friendships WHERE user_id = $1 AND friend_id = $2`,
    [ME, EX],
  );
  page = await getBuddyHistory(ME, {});
  const exWalk = page.sessions.find((s) => s.id === withEx);
  const exRow = exWalk?.participants.find((p) => p.user_id === EX);
  check("an un-friended walk is still in your history", !!exWalk, true);
  check("...but their name is withheld", exRow?.username, null);
  check("...and their photo with it", exRow?.profile_image_url, null);
  // The walk happened. An archive that quietly restates a past walk's numbers
  // because a friendship ended is worse than one that doesn't.
  check(
    "...while the group total is unchanged",
    exWalk?.group_distance_miles,
    2.9,
  );

  const withFoe = await seedWalk({
    code: "HIST05",
    daysAgo: 5,
    others: [{ userId: FOE }],
  });
  await db.query(
    `INSERT INTO user_blocks (blocker_id, blocked_id) VALUES ($1, $2)`,
    [FOE, ME],
  );
  page = await getBuddyHistory(ME, {});
  check(
    "a walk whose only companion blocked you drops out",
    page.sessions.some((s) => s.id === withFoe),
    false,
  );

  // ── 3. Photos follow the feed's rules, not the walk's ───────────────
  await seedWalkPhoto(withPal, PAL, [ME, PAL]);
  page = await getBuddyHistory(ME, {});
  check(
    "a walk's photo reaches its participants",
    page.sessions.find((s) => s.id === withPal)?.photos.length,
    1,
  );
  // Having walked with someone is not standing permission to see a photo they
  // later pulled off the feed.
  await db.query(`UPDATE posts SET share_to_feed = FALSE WHERE user_id = $1`, [
    PAL,
  ]);
  page = await getBuddyHistory(ME, {});
  check(
    "a photo pulled from the feed leaves the history",
    page.sessions.find((s) => s.id === withPal)?.photos.length,
    0,
  );
  await db.query(`UPDATE posts SET share_to_feed = TRUE WHERE user_id = $1`, [
    PAL,
  ]);

  // ── 4. Keyset pagination ────────────────────────────────────────────
  //
  // Read the archive one row at a time and it must reconstruct itself exactly:
  // a cursor comparison off by an inclusive/exclusive bound repeats a row, and
  // the wrong sort key skips one.
  const all = (await getBuddyHistory(ME, { limit: 40 })).sessions.map(
    (s) => s.id,
  );
  const walked = [];
  let before = null;
  for (let i = 0; i < 10; i++) {
    const step = await getBuddyHistory(ME, { limit: 1, before });
    if (step.sessions.length === 0) break;
    walked.push(step.sessions[0].id);
    before = step.next_before;
    if (!before) break;
  }
  check(
    "paging one row at a time sees every walk",
    walked.join(","),
    all.join(","),
  );
  check(
    "the last page hands back no cursor",
    (await getBuddyHistory(ME, { limit: 40 })).next_before,
    null,
  );

  // ── 5. The friend filter ────────────────────────────────────────────
  const filtered = await getBuddyHistory(ME, { friendId: PAL });
  check(
    "filtering narrows to that friend's walks",
    filtered.sessions.length,
    1,
  );
  check("...to the right walk", filtered.sessions[0]?.id, withPal);
  const palTotals = await getBuddyHistoryTotals(ME, PAL);
  check("filtered totals agree with the filtered list", palTotals.walks, 1);
  check("filtered totals count one partner", palTotals.partners, 1);

  await cleanup();

  console.log(
    failures === 0
      ? "buddy-history-check: all assertions passed"
      : `buddy-history-check: ${failures} FAILED`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch(async (err) => {
  console.error(err);
  await cleanup().catch(() => {});
  process.exit(1);
});
