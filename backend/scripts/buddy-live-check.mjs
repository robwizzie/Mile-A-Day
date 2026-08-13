/**
 * Buddy Walks live-membership check.
 *
 * Four behaviours that all fail SILENTLY — no throw, no 500, nothing in a log,
 * just a walk that quietly does the wrong thing while every screen looks fine:
 *
 *   1. **Joining a running walk.** A join has to land 'active', not 'joined'.
 *      Every roster surface draws `status IN ('active','finished')`, the pooled
 *      co-op total counts the same set, and `recordProgress` rejects anything
 *      else — so one wrong enum made a late arrival invisible to the group,
 *      worth nothing toward the goal, and unable to report a single metre of
 *      their own walk. That is the bug this file exists for.
 *   2. **Leaving.** Must work in every phase, must free the slot for a
 *      re-join, and must not close a session other people are still walking.
 *   3. **Cancel.** Host-only, and only before anybody is moving — a cancel
 *      that reached a live walk would destroy other people's recorded miles.
 *      A cancelled walk must never enter anyone's history.
 *   4. **The per-viewer history hide.** It has to remove the walk from the
 *      caller's archive and totals while leaving the other participant's
 *      completely untouched, because a walk belongs to everybody on it.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/buddy-live-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import {
  cancelSession,
  createSession,
  finishParticipation,
  getBuddyHistory,
  getBuddyHistoryTotals,
  getJoinableFriendSessions,
  getSessionState,
  joinSession,
  leaveSession,
  recordProgress,
  setParticipantLocationType,
  setBuddyWalkHidden,
  startSession,
} from "../dist/services/buddySessionService.js";

const db = PostgresService.getInstance();

const HOST = "buddy-live-host";
const LATE = "buddy-live-late"; // joins after the walk has started
const PAL = "buddy-live-pal";
const ALL = [HOST, LATE, PAL];

let failures = 0;
function check(label, actual, expected) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${actual} (expected ${expected})`,
  );
}

/** Run `fn` and return the error CODE it threw, or null if it succeeded. */
async function errorCode(fn) {
  try {
    await fn();
    return null;
  } catch (error) {
    return error?.message ?? String(error);
  }
}

function participant(state, userId) {
  return state.participants.find((p) => p.user_id === userId) ?? null;
}

async function seed() {
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, apple_sub, email, username, first_name, last_name)
       VALUES ($1, $2, $3, $4, $5, 'Live')
       ON CONFLICT (user_id) DO NOTHING`,
      [id, `sub-${id}`, `${id}@example.com`, id, id],
    );
  }
  // Everyone friends with everyone, both directions (friendship rows are
  // directional). Joining requires friendship with the HOST specifically.
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
  // Push writes an inbox row even with APNs unconfigured, and that row holds a
  // FK on users — so this has to come before the user delete or teardown 23503s
  // after every assertion has already passed.
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

/** The countdown puts started_at a few seconds out; tests need it in the past. */
async function backdateStart(sessionId) {
  await db.query(
    `UPDATE buddy_sessions SET started_at = NOW() - INTERVAL '5 minutes'
      WHERE id = $1`,
    [sessionId],
  );
}

// ─── 1. Joining a walk that has already started ─────────────────────────

async function testLateJoin() {
  const created = await createSession(HOST, {
    mode: "coop_goal",
    goalValue: 3,
    activityType: "walking",
    inviteUserIds: [],
  });
  await startSession(created.id, HOST);
  await backdateStart(created.id);

  const joined = await joinSession(LATE, {
    sessionId: created.id,
    locationType: "indoor",
  });

  check(
    "joining a running walk lands ACTIVE, not joined",
    participant(joined, LATE)?.status,
    "active",
  );
  check(
    "...so the late arrival is on the roster the group draws",
    joined.participants.filter(
      (p) => p.status === "active" || p.status === "finished",
    ).length,
    2,
  );
  check(
    "...and their own indoor/outdoor answer stuck",
    participant(joined, LATE)?.location_type,
    "indoor",
  );

  // The half nothing else catches: an inactive participant's progress is
  // rejected outright, so a wrong status silently zeroes their whole walk.
  const progressError = await errorCode(() =>
    recordProgress(created.id, LATE, 0.6, 300),
  );
  check("...and their progress is accepted", progressError, null);

  const afterProgress = await getSessionState(created.id, HOST);
  check(
    "...and it reaches the pooled co-op total",
    afterProgress.group_distance_miles,
    0.6,
  );

  // Indoor vs outdoor is one person's answer about where they are: the host
  // changing their own must not disturb anybody else's.
  const afterHostChoice = await setParticipantLocationType(
    created.id,
    HOST,
    "outdoor",
  );
  check(
    "location type is per participant, not per session",
    `${participant(afterHostChoice, HOST)?.location_type}/${participant(afterHostChoice, LATE)?.location_type}`,
    "outdoor/indoor",
  );

  return created.id;
}

// ─── 2. Leaving, and coming back ────────────────────────────────────────

async function testLeaveAndRejoin(sessionId) {
  await leaveSession(sessionId, LATE);
  const afterLeave = await getSessionState(sessionId, HOST);
  check(
    "leaving a running walk works mid-walk",
    participant(afterLeave, LATE)?.status,
    "left",
  );
  check(
    "...and does not end a walk somebody is still on",
    afterLeave.status,
    "active",
  );

  const rejoined = await joinSession(LATE, { sessionId });
  check(
    "...and the walk can be re-joined afterwards",
    participant(rejoined, LATE)?.status,
    "active",
  );
  check(
    "...keeping the miles already banked",
    participant(rejoined, LATE)?.distance_miles,
    0.6,
  );

  // Finished is terminal, deliberately: re-entering would hand somebody a
  // second mile for a walk they already ended.
  await finishParticipation(sessionId, LATE);
  const afterFinish = await joinSession(LATE, { sessionId });
  check(
    "a finished participant is NOT resurrected by a re-join",
    participant(afterFinish, LATE)?.status,
    "finished",
  );
}

// ─── 3. Joinability while anybody is still in it ────────────────────────

async function testJoinableWindow() {
  const created = await createSession(HOST, {
    mode: "together",
    activityType: "walking",
    inviteUserIds: [],
  });
  await startSession(created.id, HOST);
  // An hour deep. The old 20-minute bound hid exactly this walk, which is the
  // common case: you see a friend is out, put your shoes on, and by the time
  // you open the app the offer has expired.
  await db.query(
    `UPDATE buddy_sessions
        SET started_at = NOW() - INTERVAL '1 hour',
            created_at = NOW() - INTERVAL '1 hour'
      WHERE id = $1`,
    [created.id],
  );

  const offers = await getJoinableFriendSessions(PAL);
  check(
    "an hour-deep walk is still joinable while someone is in it",
    offers.some((o) => o.session_id === created.id),
    true,
  );

  // Everybody done = over, in every sense the user can see, even though the
  // row is only closed lazily on the next read.
  await db.query(
    `UPDATE buddy_session_participants SET status = 'finished'
      WHERE session_id = $1`,
    [created.id],
  );
  const afterEveryoneDone = await getJoinableFriendSessions(PAL);
  check(
    "...but not once everybody has finished",
    afterEveryoneDone.some((o) => o.session_id === created.id),
    false,
  );
}

// ─── 4. Cancel ──────────────────────────────────────────────────────────

async function testCancel() {
  const lobby = await createSession(HOST, {
    mode: "together",
    activityType: "walking",
    inviteUserIds: [PAL],
  });
  await joinSession(PAL, { sessionId: lobby.id });

  check(
    "a guest cannot cancel the host's walk",
    await errorCode(() => cancelSession(lobby.id, PAL)),
    "not_host",
  );

  const cancelled = await cancelSession(lobby.id, HOST);
  check("the host can cancel a lobby", cancelled.status, "cancelled");
  check(
    "...and everybody in the room is released",
    cancelled.participants.every((p) => p.status === "left"),
    true,
  );

  // The countdown is the exact moment "wait, no" happens, and until now it was
  // an eight-second commitment with no brakes.
  const counting = await createSession(HOST, {
    mode: "together",
    activityType: "walking",
    inviteUserIds: [],
  });
  await startSession(counting.id, HOST);
  check(
    "the shared countdown can still be cancelled",
    (await cancelSession(counting.id, HOST)).status,
    "cancelled",
  );

  // Past the countdown it must not be: one person's cancel would wipe miles
  // other people are recording right now.
  const running = await createSession(HOST, {
    mode: "together",
    activityType: "walking",
    inviteUserIds: [],
  });
  await startSession(running.id, HOST);
  await backdateStart(running.id);
  check(
    "a walk that is genuinely underway cannot be cancelled",
    await errorCode(() => cancelSession(running.id, HOST)),
    "session_not_cancellable",
  );

  return lobby.id;
}

// ─── 5. The per-viewer history hide ─────────────────────────────────────

async function testHistoryHide() {
  const walk = await createSession(HOST, {
    mode: "together",
    activityType: "walking",
    inviteUserIds: [PAL],
  });
  await joinSession(PAL, { sessionId: walk.id });
  await startSession(walk.id, HOST);
  await backdateStart(walk.id);
  await recordProgress(walk.id, HOST, 1.2, 900);
  await recordProgress(walk.id, PAL, 1.1, 900);
  await finishParticipation(walk.id, HOST);
  // The second finish closes the session and stamps placements.
  await finishParticipation(walk.id, PAL);

  check(
    "a finished shared walk enters the archive",
    (await getBuddyHistory(HOST, {})).sessions.some((s) => s.id === walk.id),
    true,
  );

  const stillRunning = await liveWalk();
  check(
    "a walk still running cannot be hidden",
    await errorCode(() => setBuddyWalkHidden(HOST, stillRunning.id, true)),
    "walk_not_hideable",
  );

  await setBuddyWalkHidden(HOST, walk.id, true);
  check(
    "hiding removes it from the caller's archive",
    (await getBuddyHistory(HOST, {})).sessions.some((s) => s.id === walk.id),
    false,
  );
  check(
    "...and from the caller's totals",
    (await getBuddyHistoryTotals(HOST)).walks,
    0,
  );
  check(
    "...while the other walker keeps it",
    (await getBuddyHistory(PAL, {})).sessions.some((s) => s.id === walk.id),
    true,
  );
  check("...totals included", (await getBuddyHistoryTotals(PAL)).walks, 1);

  // A hide, never a delete — so it undoes.
  await setBuddyWalkHidden(HOST, walk.id, false);
  check(
    "un-hiding puts it back",
    (await getBuddyHistory(HOST, {})).sessions.some((s) => s.id === walk.id),
    true,
  );
}

/** A session that is still live, for the "can't hide a running walk" case. */
async function liveWalk() {
  const created = await createSession(HOST, {
    mode: "together",
    activityType: "walking",
    inviteUserIds: [],
  });
  await startSession(created.id, HOST);
  await backdateStart(created.id);
  return created;
}

async function main() {
  await cleanup();
  await seed();

  const sessionId = await testLateJoin();
  await testLeaveAndRejoin(sessionId);
  await testJoinableWindow();
  const cancelledId = await testCancel();

  // A cancelled walk is not a walk anybody took, so it must never reach an
  // archive — the reason cancel releases participants as 'left' and not
  // 'finished'.
  check(
    "a cancelled walk never enters the archive",
    (await getBuddyHistory(PAL, {})).sessions.some((s) => s.id === cancelledId),
    false,
  );

  await testHistoryHide();

  await cleanup();

  console.log(
    failures === 0
      ? "buddy-live-check: all assertions passed"
      : `buddy-live-check: ${failures} FAILED`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch(async (err) => {
  console.error(err);
  await cleanup().catch(() => {});
  process.exit(1);
});
