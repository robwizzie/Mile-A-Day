/**
 * Buddy Walks lobby-readiness check.
 *
 * A guest is not READY until they have said how they're going (walk or run)
 * and where (indoor or outdoor). Every failure here is silent — the lobby just
 * draws the wrong word under somebody's face, or the host is never told:
 *
 *   1. `updateParticipantSettings` stores both choices and flips joined → ready
 *      in one write, and serves `activity_type` on the roster.
 *   2. Un-readying goes back to 'joined' and clears `ready_at`.
 *   3. The host is told ONCE, on the transition — re-sending ready (a retry, a
 *      second tap) must not push again.
 *   4. A walk that is already running never has its 'active' row rewritten by
 *      `ready` — a latecomer answering the questions is how they get in.
 *   5. A join may carry the activity (the mid-walk strip sends the tracker's
 *      own), and a bad value is refused at the controller, never dropped.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/buddy-ready-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import { registerDevice } from "../dist/controllers/deviceController.js";
import {
  createSession,
  getSessionState,
  joinSession,
  startSession,
  updateParticipantSettings,
} from "../dist/services/buddySessionService.js";

const db = PostgresService.getInstance();

const HOST = "buddy-ready-host";
const GUEST = "buddy-ready-guest";
const LATE = "buddy-ready-late";
const ALL = [HOST, GUEST, LATE];

let failures = 0;
function check(label, actual, expected) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${actual} (expected ${expected})`,
  );
}

function participant(state, userId) {
  return state.participants.find((p) => p.user_id === userId) ?? null;
}

async function seed() {
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, apple_sub, email, username, first_name, last_name)
       VALUES ($1, $2, $3, $4, $5, 'Ready')
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
  // The ready push is gated on the host's device declaring the buddy screens;
  // registration is what stamps that.
  await registerDevice(
    {
      userId: HOST,
      body: {
        device_token: `buddy-ready-token-${HOST}`,
        environment: "sandbox",
        client_features: ["buddy_walks_v1"],
      },
    },
    {
      statusCode: 200,
      status(code) {
        this.statusCode = code;
        return this;
      },
      json() {
        return this;
      },
    },
  );
}

async function cleanup() {
  // The ready push writes an inbox row holding a FK on users.
  await db.query(
    `DELETE FROM in_app_notifications WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM device_tokens WHERE user_id = ANY($1::text[])`, [
    ALL,
  ]);
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

/** The ready push is fire-and-forget; give it a beat to land its inbox row. */
async function readyPushesTo(userId) {
  await new Promise((r) => setTimeout(r, 300));
  const rows = await db.query(
    `SELECT COUNT(*)::int AS n FROM in_app_notifications
      WHERE user_id = $1 AND data->>'event' = 'ready'`,
    [userId],
  );
  return rows[0]?.n ?? 0;
}

async function main() {
  await cleanup();
  await seed();

  const created = await createSession(HOST, {
    mode: "coop_goal",
    goalValue: 1,
    activityType: "walking",
    inviteUserIds: [],
  });
  const joined = await joinSession(GUEST, { sessionId: created.id });
  check(
    "a fresh join waits as 'joined'",
    participant(joined, GUEST)?.status,
    "joined",
  );
  check(
    "...with no activity chosen yet",
    participant(joined, GUEST)?.activity_type,
    null,
  );

  // 1. Choices + ready in one write.
  const ready = await updateParticipantSettings(created.id, GUEST, {
    activityType: "running",
    locationType: "indoor",
    ready: true,
  });
  check(
    "ready flips the row to 'ready'",
    participant(ready, GUEST)?.status,
    "ready",
  );
  check(
    "...stores the activity",
    participant(ready, GUEST)?.activity_type,
    "running",
  );
  check(
    "...and the location",
    participant(ready, GUEST)?.location_type,
    "indoor",
  );
  check("the host is told once", await readyPushesTo(HOST), 1);

  // 3. Re-sending ready is not news.
  await updateParticipantSettings(created.id, GUEST, { ready: true });
  check("...and never twice", await readyPushesTo(HOST), 1);

  // 2. Un-ready.
  const unready = await updateParticipantSettings(created.id, GUEST, {
    ready: false,
  });
  check(
    "un-ready goes back to 'joined'",
    participant(unready, GUEST)?.status,
    "joined",
  );
  const readyAt = await db.query(
    `SELECT ready_at FROM buddy_session_participants
      WHERE session_id = $1 AND user_id = $2`,
    [created.id, GUEST],
  );
  check("...and clears ready_at", readyAt[0]?.ready_at, null);
  check(
    "...keeping the choices it already made",
    participant(unready, GUEST)?.activity_type,
    "running",
  );

  // 4. A running walk never has an active row rewritten by `ready`.
  await updateParticipantSettings(created.id, GUEST, { ready: true });
  check(
    "readying again after an un-ready IS news",
    await readyPushesTo(HOST),
    2,
  );
  await startSession(created.id, HOST);
  await db.query(
    `UPDATE buddy_sessions SET started_at = NOW() - INTERVAL '1 minute' WHERE id = $1`,
    [created.id],
  );
  const live = await getSessionState(created.id, HOST);
  check(
    "start promotes the ready guest to 'active'",
    participant(live, GUEST)?.status,
    "active",
  );
  const lateAnswer = await updateParticipantSettings(created.id, GUEST, {
    activityType: "walking",
    ready: false,
  });
  check(
    "answering late keeps an active row active",
    participant(lateAnswer, GUEST)?.status,
    "active",
  );
  check(
    "...while still recording the new choice",
    participant(lateAnswer, GUEST)?.activity_type,
    "walking",
  );

  // 5. A mid-walk join carries the tracker's own activity.
  const lateJoin = await joinSession(LATE, {
    sessionId: created.id,
    locationType: "outdoor",
    activityType: "running",
  });
  check(
    "a mid-walk join lands active",
    participant(lateJoin, LATE)?.status,
    "active",
  );
  check(
    "...with the activity it was recording",
    participant(lateJoin, LATE)?.activity_type,
    "running",
  );

  // Not a participant at all.
  let code = null;
  try {
    await updateParticipantSettings(created.id, "buddy-ready-nobody", {
      ready: true,
    });
  } catch (error) {
    code = error?.message ?? String(error);
  }
  check("a stranger can't set anything", code, "not_a_participant");

  // start / late-join pushes are fire-and-forget too; let their inbox rows
  // land before teardown deletes the users they point at.
  await new Promise((r) => setTimeout(r, 800));
  await cleanup();
  console.log(
    failures === 0
      ? "buddy-ready-check: all assertions passed"
      : `buddy-ready-check: ${failures} FAILED`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch(async (err) => {
  console.error(err);
  await cleanup().catch(() => {});
  process.exit(1);
});
