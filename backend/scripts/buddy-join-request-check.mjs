/**
 * Buddy Walks — inviting from inside a walk, and asking to join one.
 *
 * Two doors that didn't exist, and every way either can go wrong is silent:
 *
 *   1. **Inviting mid-walk, by anyone in it.** The lobby PATCH is host-only and
 *      lobby-only. A MEMBER (not just the host) must be able to pull a friend
 *      in from a running walk, the friend must land through the ordinary join
 *      door (they hold an 'invited' row, so host-friendship is not required),
 *      and someone who is NOT in the walk must be refused.
 *   2. **Asking to join.** A friend of a MEMBER — not of the host — is shown
 *      the room only on a build that can ask, is refused at the direct door,
 *      is parked as 'requested' (holding no slot, on no roster, decodable by
 *      every shipped client), is listed under `join_requests` with the members
 *      who can vouch for them, and is let in by the host OR by that member.
 *      A refused ask stays refused and cannot walk in through the invitee
 *      door on the strength of its 'declined' row.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/buddy-join-request-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import { registerDevice } from "../dist/controllers/deviceController.js";
import {
  createSession,
  getJoinableFriendSessions,
  getMySessions,
  getSessionState,
  inviteToSession,
  joinSession,
  requestToJoin,
  respondToJoinRequest,
  startSession,
  updateSession,
} from "../dist/services/buddySessionService.js";
import { friendsOutNow } from "../dist/services/liveTrackingService.js";

const db = PostgresService.getInstance();

const HOST = "buddy-req-host";
const PAL = "buddy-req-pal"; // host's friend, in the walk
const ASKER = "buddy-req-asker"; // PAL's friend, NOT the host's
const ASKER2 = "buddy-req-asker2"; // same, for the decline path
const OLD = "buddy-req-old"; // PAL's friend on a build that can't ask
const STRANGER = "buddy-req-stranger"; // friends with nobody in the walk
const LATE = "buddy-req-late"; // PAL's friend, invited by PAL mid-walk
const ALL = [HOST, PAL, ASKER, ASKER2, OLD, STRANGER, LATE];

let failures = 0;
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${JSON.stringify(actual)} (expected ${JSON.stringify(expected)})`,
  );
}

async function errorCode(fn) {
  try {
    await fn();
    return null;
  } catch (error) {
    return error?.message ?? String(error);
  }
}

function fakeRes() {
  const res = {
    statusCode: 200,
    body: null,
    status(code) {
      res.statusCode = code;
      return res;
    },
    json(payload) {
      res.body = payload;
      return res;
    },
  };
  return res;
}

async function befriend(a, b) {
  for (const [x, y] of [
    [a, b],
    [b, a],
  ]) {
    await db.query(
      `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, 'accepted')
       ON CONFLICT (user_id, friend_id) DO NOTHING`,
      [x, y],
    );
  }
}

async function seed() {
  await cleanup();
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, apple_sub, email, username, first_name, last_name)
       VALUES ($1, $2, $3, $4, $5, 'Req')
       ON CONFLICT (user_id) DO NOTHING`,
      [id, `sub-${id}`, `${id}@example.com`, id, id],
    );
  }
  await befriend(HOST, PAL);
  await befriend(PAL, ASKER);
  await befriend(PAL, ASKER2);
  await befriend(PAL, OLD);
  await befriend(PAL, LATE);
  await db.query(
    `UPDATE users SET buddy_enrolled_at = NOW() WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  // Builds that can ask vs. one that can't. Registration is what stamps
  // client_features, and that column is what every gate reads.
  for (const [id, features] of [
    [HOST, ["buddy_walks_v1", "buddy_join_request_v1"]],
    [PAL, ["buddy_walks_v1", "buddy_join_request_v1"]],
    [ASKER, ["buddy_walks_v1", "buddy_join_request_v1"]],
    [ASKER2, ["buddy_walks_v1", "buddy_join_request_v1"]],
    [STRANGER, ["buddy_walks_v1", "buddy_join_request_v1"]],
    [LATE, ["buddy_walks_v1", "buddy_join_request_v1"]],
    [OLD, ["buddy_walks_v1"]],
  ]) {
    await registerDevice(
      {
        userId: id,
        body: {
          device_token: `buddy-req-token-${id}`,
          environment: "sandbox",
          client_features: features,
        },
      },
      fakeRes(),
    );
  }
}

async function cleanup() {
  // Pushes are fire-and-forget (`void sendPush(...)`) and each writes an
  // inbox row that holds a FK on users. Let the ones this run kicked off
  // land, then clear them — deleting users under a push still in flight
  // 23503s the teardown after every assertion has passed (it did, in CI).
  await new Promise((resolve) => setTimeout(resolve, 1500));
  await db.query(`DELETE FROM in_app_notifications WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM device_tokens WHERE user_id = ANY($1::text[])`, [
    ALL,
  ]);
  await db.query(
    `DELETE FROM live_tracking_sessions WHERE user_id = ANY($1::text[])`,
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

/** PAL is out walking (live presence) so the Friends tab has a row for them. */
async function palIsOut() {
  await db.query(
    `INSERT INTO live_tracking_sessions (user_id, workout_type, started_at, last_seen_at, distance_miles)
     VALUES ($1, 'walking', NOW() - INTERVAL '4 minutes', NOW(), 0.3)`,
    [PAL],
  );
}

async function main() {
  await seed();

  // ── A lobby the host opened, with PAL in it ────────────────────────────
  const created = await createSession(HOST, {
    mode: "together",
    activityType: "walking",
    inviteUserIds: [PAL],
  });
  await joinSession(PAL, { sessionId: created.id });
  await palIsOut();

  // ── Who is SHOWN the room ─────────────────────────────────────────────
  const askerSees = await getJoinableFriendSessions(ASKER);
  check(
    "a member's friend on an asking build is shown the room",
    askerSees.map((s) => s.session_id),
    [created.id],
  );
  check("...told it is an ASK, not a join", askerSees[0]?.host_is_friend, false);
  check("...with the friend inside named", askerSees[0]?.friend_first_names, [PAL]);
  check(
    "a member's friend on an OLDER build is not shown it (its Join would 400)",
    (await getJoinableFriendSessions(OLD)).length,
    0,
  );
  check(
    "someone friends with nobody in the walk is not shown it",
    (await getJoinableFriendSessions(STRANGER)).length,
    0,
  );
  const out = await friendsOutNow(ASKER);
  check(
    "the Friends-tab row for PAL carries the room for the asking build",
    out.find((f) => f.user_id === PAL)?.buddy_session_id ?? null,
    created.id,
  );
  check("...flagged as ask-only", out.find((f) => f.user_id === PAL)?.buddy_host_is_friend, false);
  check(
    "...and NOT for the older build",
    (await friendsOutNow(OLD)).find((f) => f.user_id === PAL)?.buddy_session_id ?? null,
    null,
  );

  // ── The doors ─────────────────────────────────────────────────────────
  check(
    "the direct door still refuses a non-friend of the host",
    await errorCode(() => joinSession(ASKER, { sessionId: created.id })),
    "not_friends_with_host",
  );
  check(
    "a stranger cannot ask",
    await errorCode(() => requestToJoin(created.id, STRANGER)),
    "no_friends_in_walk",
  );
  check(
    "the host's own friend is told to walk straight in",
    await errorCode(() => requestToJoin(created.id, PAL)),
    "already_in",
  );
  check("the ask lands", (await requestToJoin(created.id, ASKER)).status, "requested");
  check(
    "asking twice is idempotent",
    (await requestToJoin(created.id, ASKER)).status,
    "requested",
  );
  check(
    "...and the direct door now says the ask is pending",
    await errorCode(() => joinSession(ASKER, { sessionId: created.id })),
    "request_pending",
  );

  // ── What the room sees ────────────────────────────────────────────────
  const hostView = await getSessionState(created.id, HOST);
  check(
    "a requester is NOT in participants (shipped clients decode a closed enum)",
    hostView.participants.some((p) => p.user_id === ASKER),
    false,
  );
  check(
    "...but IS in join_requests, with the member who vouches",
    hostView.join_requests.map((r) => [r.user_id, r.friend_user_ids]),
    [[ASKER, [PAL]]],
  );
  check(
    "the requester still sees the room, marked requested",
    (await getJoinableFriendSessions(ASKER))[0]?.my_request_status ?? null,
    "requested",
  );
  const [slotRow] = await db.query(
    `SELECT COUNT(*)::int AS n FROM buddy_session_participants
      WHERE session_id = $1 AND status IN ('invited','joined','ready','active','finished')`,
    [created.id],
  );
  check("a request holds no slot", slotRow.n, 2);

  // ── Answering: the MEMBER who knows them, not only the host ───────────
  check(
    "a stranger cannot answer",
    await errorCode(() => respondToJoinRequest(created.id, STRANGER, ASKER, true)),
    "not_a_participant",
  );
  const approved = await respondToJoinRequest(created.id, PAL, ASKER, true);
  check(
    "the member lets them in → an ordinary invite",
    approved.participants.find((p) => p.user_id === ASKER)?.status,
    "invited",
  );
  check("...and the queue is empty", approved.join_requests.length, 0);
  check(
    "...which the requester sees as an invite",
    (await getMySessions(ASKER)).invites.map((s) => s.id),
    [created.id],
  );
  const joined = await joinSession(ASKER, { sessionId: created.id });
  check(
    "...so they walk in through the door every build already has",
    joined.participants.find((p) => p.user_id === ASKER)?.status,
    "joined",
  );

  // ── Refusal is final and grants nothing ───────────────────────────────
  await requestToJoin(created.id, ASKER2);
  const refused = await respondToJoinRequest(created.id, HOST, ASKER2, false);
  check("the host can refuse", refused.join_requests.length, 0);
  check(
    "a refused ask cannot be re-asked",
    await errorCode(() => requestToJoin(created.id, ASKER2)),
    "request_declined",
  );
  check(
    "...and its 'declined' row is not a ticket through the invitee door",
    await errorCode(() => joinSession(ASKER2, { sessionId: created.id })),
    "not_friends_with_host",
  );
  check(
    "...and the list says so",
    (await getJoinableFriendSessions(ASKER2))[0]?.my_request_status ?? null,
    "declined",
  );

  // ── Inviting from INSIDE a running walk, by a member ──────────────────
  await startSession(created.id, HOST);
  await db.query(
    `UPDATE buddy_sessions SET started_at = NOW() - INTERVAL '5 minutes' WHERE id = $1`,
    [created.id],
  );
  check(
    "the lobby PATCH is still host-only and lobby-only",
    await errorCode(() => updateSession(created.id, PAL, { inviteUserIds: [LATE] })),
    "not_host",
  );
  check(
    "someone outside the walk cannot invite into it",
    await errorCode(() => inviteToSession(created.id, STRANGER, [LATE])),
    "not_a_participant",
  );
  const invited = await inviteToSession(created.id, PAL, [LATE]);
  check(
    "a MEMBER invites their friend mid-walk",
    invited.participants.find((p) => p.user_id === LATE)?.status,
    "invited",
  );
  const [inviter] = await db.query(
    `SELECT invited_by FROM buddy_session_participants WHERE session_id = $1 AND user_id = $2`,
    [created.id, LATE],
  );
  check("...stamped with who asked them", inviter?.invited_by, PAL);
  const lateJoined = await joinSession(LATE, { sessionId: created.id });
  check(
    "...and the invitee, no friend of the host, lands ACTIVE on the running walk",
    lateJoined.participants.find((p) => p.user_id === LATE)?.status,
    "active",
  );
  check(
    "the host's friend cannot be invited by a member who isn't THEIR friend",
    (await inviteToSession(created.id, LATE, [STRANGER])).participants.some(
      (p) => p.user_id === STRANGER,
    ),
    false,
  );

  // ── The push the ask sends goes only to builds that route it ──────────
  const inbox = await db.query(
    `SELECT user_id, type FROM in_app_notifications
      WHERE type = 'buddy_join_request' AND user_id = ANY($1::text[])
      ORDER BY user_id`,
    [ALL],
  );
  check(
    "the ask reaches the host and the vouching member (both on asking builds)",
    [...new Set(inbox.map((r) => r.user_id))].sort(),
    [HOST, PAL].sort(),
  );

  await cleanup();
  console.log(
    failures === 0
      ? "buddy-join-request-check: all assertions passed"
      : `buddy-join-request-check: ${failures} FAILED`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch(async (err) => {
  console.error(err);
  await cleanup().catch(() => {});
  process.exit(1);
});
