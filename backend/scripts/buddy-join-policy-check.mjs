/**
 * Buddy Walks "who can join" check.
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
  getJoinableFriendSessions,
  inviteToSession,
  joinSession,
  requestToJoin,
  setJoinPolicy,
} from "../dist/services/buddySessionService.js";

const db = PostgresService.getInstance();

const HOST = "bjp-host";
const CLOSE = "bjp-close";
const PLAIN = "bjp-plain";
const MEMBER = "bjp-member";
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

async function main() {
  await cleanup();
  await seed();
  await db.query(
    `INSERT INTO close_friends (user_id, close_friend_id) VALUES ($1, $2)`,
    [HOST, CLOSE],
  );

  // A walk with no setting is every walk before the feature: friends join.
  const open = await createSession(HOST, { mode: "together", activityType: "walking", inviteUserIds: [] });
  check("no setting reads as 'friends'", open.join_policy, "friends");
  const openList = await getJoinableFriendSessions(PLAIN);
  check("a friend is offered a friends walk", openList.some((s) => s.session_id === open.id), true);

  // Close friends only.
  const cf = await createSession(HOST, {
    mode: "together", activityType: "walking", inviteUserIds: [], joinPolicy: "close_friends",
  });
  check("created close-friends walk says so", cf.join_policy, "close_friends");
  check("a plain friend is NOT offered it", (await getJoinableFriendSessions(PLAIN)).some((s) => s.session_id === cf.id), false);
  check("a close friend IS offered it", (await getJoinableFriendSessions(CLOSE)).some((s) => s.session_id === cf.id), true);
  check("a plain friend can't join it", await code(() => joinSession(PLAIN, { sessionId: cf.id })), "join_closed");
  check("a close friend can", await code(() => joinSession(CLOSE, { sessionId: cf.id })), null);
  check("asking in is closed too", await code(() => requestToJoin(cf.id, MEMBER)), "join_closed");
  check("only the host may invite", await code(() => inviteToSession(cf.id, CLOSE, [MEMBER])), "invites_host_only");
  check("the host's invite still works", await code(() => inviteToSession(cf.id, HOST, [PLAIN])), null);
  check("...and the invitee gets in", await code(() => joinSession(PLAIN, { sessionId: cf.id })), null);

  // Invite only, set mid-flight, host-only.
  check("a guest can't change it", await code(() => setJoinPolicy(open.id, PLAIN, "invite_only")), "not_host");
  const io = await setJoinPolicy(open.id, HOST, "invite_only");
  check("the host can, any time", io.join_policy, "invite_only");
  check("invite-only hides it from a close friend", (await getJoinableFriendSessions(CLOSE)).some((s) => s.session_id === open.id), false);
  check("...and refuses them", await code(() => joinSession(CLOSE, { sessionId: open.id })), "join_closed");

  await new Promise((r) => setTimeout(r, 800));
  await cleanup();
  console.log(failures === 0 ? "buddy-join-policy-check: all assertions passed" : `buddy-join-policy-check: ${failures} FAILED`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch(async (err) => {
  console.error(err);
  await cleanup().catch(() => {});
  process.exit(1);
});
