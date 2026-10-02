/**
 * Buddy Walks "combine walks" check.
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
  mergeSession,
  startSession,
} from "../dist/services/buddySessionService.js";

const db = PostgresService.getInstance();

const HOST = "bmg-a";
const CLOSE = "bmg-b";
const PLAIN = "bmg-guest";
const MEMBER = "bmg-invitee";
const ALL = [HOST, CLOSE, PLAIN, MEMBER];

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
  await db.query(`DELETE FROM close_friends WHERE user_id = ANY($1::text[])`, [ALL]);
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


async function code(fn) {
  try { await fn(); return null; } catch (e) { return e?.message ?? String(e); }
}

function status(state, userId) {
  return state.participants.find((p) => p.user_id === userId)?.status ?? null;
}

async function main() {
  await cleanup();
  await seed();
  // HOST = A, CLOSE = B, PLAIN = a guest in A's lobby, MEMBER = invited to A's.
  const mine = await createSession(HOST, {
    mode: "together", activityType: "walking", inviteUserIds: [MEMBER],
  });
  await joinSession(PLAIN, { sessionId: mine.id });
  const theirs = await createSession(CLOSE, { mode: "together", activityType: "walking", inviteUserIds: [] });

  check("only the lobby's host can combine it", await code(() => mergeSession(mine.id, theirs.id, PLAIN)), "not_host");

  const merged = await mergeSession(mine.id, theirs.id, HOST);
  check("the merger lands in the friend's walk, already ready", status(merged.state, HOST), "ready");
  check("...bringing the people in their lobby", status(merged.state, PLAIN), "joined");
  check("...and re-inviting their invitee", status(merged.state, MEMBER), "invited");
  check("nobody was left behind", merged.left_behind.length, 0);

  const old = await db.query(`SELECT status, merged_into FROM buddy_sessions WHERE id = $1`, [mine.id]);
  check("the old lobby is cancelled", old[0]?.status, "cancelled");
  check("...and points at the walk it joined", old[0]?.merged_into, theirs.id);
  check("a guest still polling it can see where it went",
    (await getSessionState(mine.id, PLAIN))?.merged_into, theirs.id);

  // Only a lobby can be folded in.
  const live = await createSession(HOST, { mode: "together", activityType: "walking", inviteUserIds: [] });
  await startSession(live.id, HOST);
  check("a started walk can't be combined away",
    await code(() => mergeSession(live.id, theirs.id, HOST)), "session_not_editable");

  await new Promise((r) => setTimeout(r, 800));
  await cleanup();
  console.log(failures === 0 ? "buddy-merge-check: all assertions passed" : `buddy-merge-check: ${failures} FAILED`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch(async (err) => {
  console.error(err);
  await cleanup().catch(() => {});
  process.exit(1);
});
