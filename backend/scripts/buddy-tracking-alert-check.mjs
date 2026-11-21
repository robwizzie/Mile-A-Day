/**
 * Buddy Walks "your phone isn't recording" check (`alertSilentWalkers`).
 *
 * A guest's tracker starts only when their lobby is on screen at the moment
 * the countdown ends, so a phone locked in a pocket was `active` on the
 * roster and recorded nothing — and nobody, least of all its owner, was told.
 * This pins who gets the push and that it goes once per silence:
 *
 *   1. A walker who never reported after the grace → alerted, once.
 *   2. A walker who IS reporting → never alerted.
 *   3. Inside the grace (walk just started) → nobody alerted.
 *   4. A mid-walk joiner is timed from THEIR join, not the walk's start.
 *   5. A walker who reported and then went quiet → alerted; reporting again
 *      re-arms it, so a second silence alerts again.
 *   6. Finished walkers and walks that aren't running are never alerted.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/buddy-tracking-alert-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import {
  alertSilentWalkers,
  createSession,
  finishParticipation,
  joinSession,
  recordProgress,
  startSession,
} from "../dist/services/buddySessionService.js";

const db = PostgresService.getInstance();

const HOST = "buddy-alert-host";
const QUIET = "buddy-alert-quiet"; // never opens the app
const LATE = "buddy-alert-late"; // joins mid-walk
const ALL = [HOST, QUIET, LATE];

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
       VALUES ($1, $2, $3, $4, $5, 'Alert')
       ON CONFLICT (user_id) DO NOTHING`,
      [id, `sub-${id}`, `${id}@example.com`, id, id],
    );
  }
  for (const a of ALL) {
    for (const b of ALL) {
      if (a === b) continue;
      await db.query(
        `INSERT INTO friendships (user_id, friend_id, status)
         VALUES ($1, $2, 'accepted')
         ON CONFLICT (user_id, friend_id) DO NOTHING`,
        [a, b],
      );
    }
  }
  await db.query(
    `UPDATE users SET buddy_enrolled_at = NOW() WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
}

async function cleanup() {
  await db.query(
    `DELETE FROM in_app_notifications WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(
    `DELETE FROM buddy_session_participants WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(
    `DELETE FROM buddy_sessions WHERE host_user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM friendships WHERE user_id = ANY($1::text[])`, [
    ALL,
  ]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1::text[])`, [ALL]);
}

async function alertedAt(sessionId, userId) {
  const rows = await db.query(
    `SELECT tracking_alert_sent_at FROM buddy_session_participants
      WHERE session_id = $1 AND user_id = $2`,
    [sessionId, userId],
  );
  return rows[0]?.tracking_alert_sent_at ?? null;
}

async function inboxCount(userId) {
  const rows = await db.query(
    `SELECT COUNT(*)::int AS n FROM in_app_notifications
      WHERE user_id = $1 AND type = 'buddy_started'
        AND data->>'kind' IN ('not_recording', 'went_quiet')`,
    [userId],
  );
  return Number(rows[0]?.n ?? 0);
}

/**
 * `recordProgress` fires the alert WITHOUT awaiting it (the reporter's roster
 * shouldn't wait on a push), so a claim can land before its inbox row does.
 * Wait for the row rather than reading the count the instant after.
 */
async function settledInboxCount(userId, expected, timeoutMs = 3000) {
  const deadline = Date.now() + timeoutMs;
  let n = await inboxCount(userId);
  while (n < expected && Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, 50));
    n = await inboxCount(userId);
  }
  return n;
}

async function startedWalkWithQuietGuest() {
  const created = await createSession(HOST, {
    mode: "together",
    activityType: "walking",
    inviteUserIds: [QUIET],
  });
  await joinSession(QUIET, { sessionId: created.id });
  await startSession(created.id, HOST);
  return created.id;
}

async function backdate(sessionId, seconds) {
  await db.query(
    `UPDATE buddy_sessions SET started_at = NOW() - ($2 || ' seconds')::interval
      WHERE id = $1`,
    [sessionId, String(seconds)],
  );
  // Lobby members joined BEFORE the start, as they do for real.
  await db.query(
    `UPDATE buddy_session_participants
        SET joined_at = NOW() - ($2 || ' seconds')::interval - INTERVAL '1 minute'
      WHERE session_id = $1`,
    [sessionId, String(seconds)],
  );
}

async function main() {
  await cleanup();
  await seed();

  // ─── 3. Inside the grace: nobody yet ───
  const walk = await startedWalkWithQuietGuest();
  await backdate(walk, 20);
  await recordProgress(walk, HOST, 0.02, 20, false);
  check(
    "inside the grace nobody is alerted",
    await alertSilentWalkers(walk),
    0,
  );

  // ─── 1 + 2. Past the grace: the silent guest, not the reporting host ───
  await backdate(walk, 120);
  await recordProgress(walk, HOST, 0.1, 120, false);
  // recordProgress fires the alert without awaiting it; settle it here.
  await alertSilentWalkers(walk);
  check(
    "the never-reported guest is claimed",
    (await alertedAt(walk, QUIET)) !== null,
    true,
  );
  check(
    "the reporting host is not",
    (await alertedAt(walk, HOST)) === null,
    true,
  );
  check("the guest got exactly one push", await settledInboxCount(QUIET, 1), 1);
  check("a second pass sends nothing", await alertSilentWalkers(walk), 0);
  check("still exactly one push", await settledInboxCount(QUIET, 1), 1);

  // ─── 4. Mid-walk joiner: timed from their join ───
  await joinSession(LATE, { sessionId: walk });
  check(
    "a fresh mid-walk joiner is not alerted",
    await alertSilentWalkers(walk),
    0,
  );
  await db.query(
    `UPDATE buddy_session_participants SET joined_at = NOW() - INTERVAL '2 minutes'
      WHERE session_id = $1 AND user_id = $2`,
    [walk, LATE],
  );
  check(
    "a joiner silent past the grace is alerted",
    await alertSilentWalkers(walk),
    1,
  );

  // ─── 5. Went quiet, recovered, went quiet again ───
  await db.query(
    `UPDATE buddy_session_participants
        SET last_progress_at = NOW() - INTERVAL '4 minutes'
      WHERE session_id = $1 AND user_id = $2`,
    [walk, HOST],
  );
  check(
    "a walker silent 4 minutes is alerted",
    await alertSilentWalkers(walk),
    1,
  );
  check("their push says it stopped", await inboxCount(HOST), 1);
  check("not twice for one silence", await alertSilentWalkers(walk), 0);
  // They came back (a report after the alert), then went quiet again: the
  // alert was 10 minutes ago, the last report 4.
  await recordProgress(walk, HOST, 0.3, 400, false);
  await db.query(
    `UPDATE buddy_session_participants
        SET tracking_alert_sent_at = NOW() - INTERVAL '10 minutes',
            last_progress_at = NOW() - INTERVAL '4 minutes'
      WHERE session_id = $1 AND user_id = $2`,
    [walk, HOST],
  );
  check(
    "reporting again re-arms the next silence",
    await alertSilentWalkers(walk),
    1,
  );

  // ─── 6. Finished walkers / closed walks ───
  const other = await startedWalkWithQuietGuest();
  // Finished first, THEN the walk runs long: a finished walker is done
  // recording, however long their friends keep going.
  await finishParticipation(other, QUIET);
  await backdate(other, 300);
  await recordProgress(other, HOST, 0.2, 300, false);
  await alertSilentWalkers(other);
  check(
    "a finished walker is never alerted",
    (await alertedAt(other, QUIET)) === null,
    true,
  );

  await cleanup();
  console.log(
    failures === 0
      ? "buddy-tracking-alert-check: all assertions passed"
      : `buddy-tracking-alert-check: ${failures} FAILED`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch(async (err) => {
  console.error(err);
  await cleanup().catch(() => {});
  process.exit(1);
});
