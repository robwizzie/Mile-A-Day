/**
 * Buddy session LIFECYCLE check — the stages no other buddy script touches:
 * the abandoned-session sweep, reconciliation with the real workout, the
 * session's local day, the Friends-tab join offer vs. the join endpoint, and
 * the join/promotion race. Every one of these used to fail SILENTLY for a
 * real user (a booked walk vanishing, "not synced" forever, a Join that
 * 400s, a 0-mile walk in everyone's history, a Pacific walk filed under
 * tomorrow), so each is asserted by behaviour through the real service
 * functions against the CI database.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/buddy-lifecycle-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import {
  createSession,
  updateSession,
  startSession,
  joinSession,
  finishParticipation,
  recordProgress,
  reconcileBuddySessions,
  sweepAbandonedSessions,
  promoteDueScheduledSessions,
  getJoinableFriendSessions,
  getSessionState,
  getMySessions,
  inviteWhenText,
} from "../dist/services/buddySessionService.js";
import { friendsOutNow } from "../dist/services/liveTrackingService.js";

const db = PostgresService.getInstance();

const H = "blc-host";
const A = "blc-a";
const B = "blc-b";
const S = "blc-stranger"; // A's friend, NOT the host's
const ALL = [H, A, B, S];

let failures = 0;
function check(label, actual, expected) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${JSON.stringify(actual)}${ok ? "" : ` (expected ${JSON.stringify(expected)})`}`,
  );
}
const sessionRow = async (id) =>
  (await db.query(`SELECT * FROM buddy_sessions WHERE id = $1`, [id]))[0];
const participant = async (id, user) =>
  (
    await db.query(
      `SELECT * FROM buddy_session_participants WHERE session_id = $1 AND user_id = $2`,
      [id, user],
    )
  )[0];

async function cleanup() {
  await db.query(`DELETE FROM in_app_notifications WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM buddy_sessions WHERE host_user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM live_tracking_sessions WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM notification_settings WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM friendships WHERE user_id = ANY($1) OR friend_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1)`, [ALL]);
}

async function seed() {
  for (const u of ALL) {
    await db.query(
      `INSERT INTO users (user_id, username, email, apple_sub, buddy_enrolled_at)
       VALUES ($1, $2, $3, $4, NOW())`,
      [u, u, `${u}@example.com`, `${u}-sub`],
    );
  }
  for (const [x, y] of [[H, A], [H, B], [A, B], [A, S]]) {
    await db.query(
      `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1,$2,'accepted'),($2,$1,'accepted')`,
      [x, y],
    );
  }
  // The host lives at UTC-7 (Pacific summer); nobody else has a timezone yet.
  await db.query(
    `INSERT INTO notification_settings (user_id, timezone_offset_minutes) VALUES ($1, -420)`,
    [H],
  );
}

const hours = (n) => new Date(Date.now() + n * 3600e3).toISOString();

try {
  await cleanup();
  await seed();

  // ── 1. A scheduled walk survives the abandoned-lobby sweep ───────────
  {
    const s = await createSession(H, {
      mode: "together", activityType: "walking", inviteUserIds: [A],
      scheduledStartAt: hours(5),
    });
    await db.query(`UPDATE buddy_sessions SET created_at = NOW() - INTERVAL '4 hours' WHERE id = $1`, [s.id]);
    await sweepAbandonedSessions();
    check("a walk booked 5h out survives the 3h lobby sweep", (await sessionRow(s.id)).status, "lobby");

    // …but one whose start passed 40 minutes ago (promotion refuses >30) is
    // retired, and its people are released — not finished, not notified.
    await db.query(`UPDATE buddy_sessions SET scheduled_start_at = NOW() - INTERVAL '40 minutes' WHERE id = $1`, [s.id]);
    await sweepAbandonedSessions();
    check("a scheduled walk nobody started is cancelled once its window passed", (await sessionRow(s.id)).status, "cancelled");
    check("…and the host is released", (await participant(s.id, H)).status, "left");
    check("…and the invitee too", (await participant(s.id, A)).status, "left");
    check("…with no walk in anyone's live sessions", (await getMySessions(H)).active, null);
  }

  // ── 7. local_date is the HOST's day of the SCHEDULED instant ─────────
  {
    // An instant that is 23:30 in UTC-7 on some day: pick tomorrow 06:30 UTC.
    const when = new Date(); when.setUTCDate(when.getUTCDate() + 1); when.setUTCHours(6, 30, 0, 0);
    const s = await createSession(H, { mode: "together", activityType: "walking", scheduledStartAt: when.toISOString() });
    const expected = new Date(when.getTime() - 420 * 60_000).toISOString().slice(0, 10);
    const row = await db.query(`SELECT to_char(local_date, 'YYYY-MM-DD') AS d FROM buddy_sessions WHERE id = $1`, [s.id]);
    check("local_date is the scheduled day in the host's timezone (UTC-7)", row[0].d, expected);
    const utcDay = when.toISOString().slice(0, 10);
    check("…which is NOT the UTC day of that instant", row[0].d === utcDay, false);

    // Moving the walk two days restamps the day and re-arms the reminder.
    await db.query(`UPDATE buddy_sessions SET scheduled_reminder_sent_at = NOW() WHERE id = $1`, [s.id]);
    const moved = new Date(when.getTime() + 2 * 86_400_000);
    await updateSession(s.id, H, { scheduledStartAt: moved.toISOString() });
    const after = await db.query(
      `SELECT to_char(local_date, 'YYYY-MM-DD') AS d, scheduled_reminder_sent_at AS r FROM buddy_sessions WHERE id = $1`,
      [s.id],
    );
    check("a moved walk restamps local_date", after[0].d, new Date(moved.getTime() - 420 * 60_000).toISOString().slice(0, 10));
    check("…and re-arms the 15-minute reminder", after[0].r, null);

    // Unscheduled: today in the host's timezone.
    const now = await createSession(H, { mode: "together", activityType: "walking" });
    const todayHost = new Date(Date.now() - 420 * 60_000).toISOString().slice(0, 10);
    check("an unscheduled walk is today in the host's timezone", (await db.query(`SELECT to_char(local_date,'YYYY-MM-DD') AS d FROM buddy_sessions WHERE id = $1`, [now.id]))[0].d, todayHost);
  }

  // ── 11. Invite copy says WHEN ─────────────────────────────────────────
  check("invite copy: unscheduled", inviteWhenText(null), "starting now");
  check("invite copy: 20 minutes", inviteWhenText(new Date(Date.now() + 20 * 60_000).toISOString()), "in 20 minutes");
  check("invite copy: 3 hours", inviteWhenText(hours(3)), "in 3 hours");
  check("invite copy: 2 days", inviteWhenText(hours(49)), "in 2 days");

  // ── 2. The first finisher's workout links while a friend is still out ─
  {
    const s = await createSession(H, { mode: "race_goal", goalValue: 5, activityType: "walking", inviteUserIds: [A] });
    await joinSession(A, { sessionId: s.id });
    await startSession(s.id, H);
    await db.query(`UPDATE buddy_sessions SET started_at = NOW() - INTERVAL '30 minutes' WHERE id = $1`, [s.id]);
    await recordProgress(s.id, H, 1.0, 1500);
    await recordProgress(s.id, A, 0.8, 1500);
    await finishParticipation(s.id, H); // host done, A still walking
    check("host finished, session still active", (await sessionRow(s.id)).status, "active");

    await db.query(
      `INSERT INTO workouts (workout_id, user_id, distance, total_duration, date, device_end_date, local_date, workout_type, source_bundle_id, timezone_offset, calories)
       VALUES ('blc-w-host', $1, 1.02, 1500, NOW(), NOW(), CURRENT_DATE, 'walking', 'run.mileaday', 0, 0)`,
      [H],
    );
    await reconcileBuddySessions(H, ["blc-w-host"]);
    const host = await participant(s.id, H);
    check("the first finisher's synced workout links while the walk is still on", host.workout_id, "blc-w-host");
    check("…with the real distance", Number(host.final_distance_miles), 1.02);

    // A's workout syncs BEFORE A taps Finish (Watch finished it). Close-time
    // linking picks it up without a re-upload.
    await db.query(
      `INSERT INTO workouts (workout_id, user_id, distance, total_duration, date, device_end_date, local_date, workout_type, source_bundle_id, timezone_offset, calories)
       VALUES ('blc-w-a', $1, 0.91, 1400, NOW(), NOW(), CURRENT_DATE, 'walking', 'run.mileaday', 0, 0)`,
      [A],
    );
    await reconcileBuddySessions(A, ["blc-w-a"]); // A is still 'active': nothing links yet
    check("a still-walking participant is not linked early", (await participant(s.id, A)).workout_id, null);
    await finishParticipation(s.id, A);
    check("everyone finished → completed", (await sessionRow(s.id)).status, "completed");
    check("…and the pre-synced workout is linked at close", (await participant(s.id, A)).workout_id, "blc-w-a");
    check("…ranked on the real numbers: host first", (await participant(s.id, H)).place, 1);
    check("…A second", (await participant(s.id, A)).place, 2);

    // Nobody is told about their own Finish; the other finisher is.
    await new Promise((r) => setTimeout(r, 300));
    const finishedPushes = async (u) =>
      (await db.query(`SELECT COUNT(*)::int AS n FROM in_app_notifications WHERE user_id = $1 AND type = 'buddy_finished'`, [u]))[0].n;
    check("the person whose Finish closed the walk is not pushed about it", await finishedPushes(A), 0);
    check("…the other finisher is", await finishedPushes(H), 1);
  }

  // ── 5. The Friends-tab offer is exactly what the join endpoint accepts ─
  {
    const s = await createSession(H, { mode: "together", activityType: "walking", inviteUserIds: [A] });
    // A is out solo (live presence) but never answered the invite.
    await db.query(
      `INSERT INTO live_tracking_sessions (user_id, session_id, workout_type, started_at, last_seen_at)
       VALUES ($1, gen_random_uuid(), 'walking', NOW(), NOW())`,
      [A],
    );
    const forStranger = (await friendsOutNow(S)).find((r) => r.user_id === A);
    check("Friends tab: a merely-invited friend carries no room", forStranger?.buddy_session_id ?? null, null);
    await joinSession(A, { sessionId: s.id });
    const forStranger2 = (await friendsOutNow(S)).find((r) => r.user_id === A);
    check("Friends tab: a room the viewer can't join (not the host's friend) is not offered", forStranger2?.buddy_session_id ?? null, null);
    check("…and the join endpoint agrees", (await getJoinableFriendSessions(S)).length, 0);
    const forB = (await friendsOutNow(B)).find((r) => r.user_id === A);
    check("Friends tab: the host's friend IS offered the room", forB?.buddy_session_id ?? null, s.id);
    check("…and the join endpoint agrees", (await getJoinableFriendSessions(B)).some((r) => r.session_id === s.id), true);
    let err = null;
    try { await joinSession(B, { sessionId: s.id }); } catch (e) { err = e.message; }
    check("…and the join succeeds", err, null);
  }

  // ── 6. A promoted walk nobody took never enters history ───────────────
  {
    const s = await createSession(H, { mode: "together", activityType: "walking", inviteUserIds: [A], scheduledStartAt: hours(1) });
    await joinSession(A, { sessionId: s.id });
    await db.query(`UPDATE buddy_sessions SET scheduled_start_at = NOW() - INTERVAL '1 minute' WHERE id = $1`, [s.id]);
    await promoteDueScheduledSessions();
    check("promotion starts the walk", (await sessionRow(s.id)).status, "active");
    await db.query(`UPDATE buddy_sessions SET started_at = NOW() - INTERVAL '7 hours' WHERE id = $1`, [s.id]);
    await sweepAbandonedSessions();
    check("nobody moved → cancelled, not completed", (await sessionRow(s.id)).status, "cancelled");
    check("…host released", (await participant(s.id, H)).status, "left");
    check("…A released", (await participant(s.id, A)).status, "left");

    // …whereas one where ONE person walked is finalized for that person.
    const t = await createSession(H, { mode: "together", activityType: "walking", inviteUserIds: [A] });
    await joinSession(A, { sessionId: t.id });
    await startSession(t.id, H);
    await db.query(`UPDATE buddy_sessions SET started_at = NOW() - INTERVAL '7 hours' WHERE id = $1`, [t.id]);
    await recordProgress(t.id, H, 1.3, 1200);
    await sweepAbandonedSessions();
    check("one walker moved → completed", (await sessionRow(t.id)).status, "completed");
    check("…the walker is finished", (await participant(t.id, H)).status, "finished");
    check("…the no-show is left, not finished", (await participant(t.id, A)).status, "left");
  }

  // ── 8. A 'joined' row in a running walk is lifted on its first report ─
  {
    const s = await createSession(H, { mode: "together", activityType: "walking", inviteUserIds: [A] });
    await joinSession(A, { sessionId: s.id });
    await startSession(s.id, H);
    // Simulate the lost race: A's row was written 'joined' after the flip.
    await db.query(`UPDATE buddy_session_participants SET status = 'joined' WHERE session_id = $1 AND user_id = $2`, [s.id, A]);
    let err = null;
    try { await recordProgress(s.id, A, 0.1, 60); } catch (e) { err = e.message; }
    check("a stranded joiner's first progress report is accepted", err, null);
    check("…and lifts them to active", (await participant(s.id, A)).status, "active");
  }

  // ── 13. getMySessions prefers the walk I'm in over a lobby I booked ───
  {
    const lobby = await createSession(H, { mode: "together", activityType: "walking", scheduledStartAt: hours(2) });
    const walk = await createSession(A, { mode: "together", activityType: "walking", inviteUserIds: [H] });
    await startSession(walk.id, A);
    await joinSession(H, { sessionId: walk.id }); // joined mid-run → active
    // The lobby is NEWER than the walk in created_at terms? Make it so.
    await db.query(`UPDATE buddy_sessions SET created_at = NOW() + INTERVAL '1 minute' WHERE id = $1`, [lobby.id]);
    const mine = await getMySessions(H);
    check("the walk I'm active in wins over the newer lobby I booked", mine.active?.id, walk.id);
  }
} finally {
  await cleanup();
  await db.close();
}

if (failures) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log("\nbuddy-lifecycle check passed");
process.exit(0);
