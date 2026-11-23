/**
 * Buddy walk lock-screen countdown (Live Activity) + Watch reporting device.
 *
 *   1. The APNs request shape is the liveactivity contract (topic suffix,
 *      push type, aps keys) — a wrong one is accepted silently or rejected.
 *   2. Only someone on the walk can register a token.
 *   3. Start pushes an ALERTING countdown to everyone registered and not yet
 *      recording — never to the person who tapped Start.
 *   4. The first progress report ends that walker's card and deletes it.
 *   5. Leaving ends it; a dead token is deleted.
 *   6. A progress report's `device` is served as `reporting_device`, and a
 *      report without one leaves it alone.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/buddy-live-activity-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import {
  buildLiveActivityPushRequest,
  setLiveActivityTransportForTesting,
} from "../dist/services/pushNotificationService.js";
import { registerLiveActivity } from "../dist/services/buddyLiveActivityService.js";
import {
  createSession,
  getSessionState,
  joinSession,
  leaveSession,
  recordProgress,
  startSession,
} from "../dist/services/buddySessionService.js";

const db = PostgresService.getInstance();

const HOST = "buddy-la-host";
const GUEST = "buddy-la-guest";
const PAL = "buddy-la-pal";
const STRANGER = "buddy-la-stranger";
const ALL = [HOST, GUEST, PAL, STRANGER];
const FRIENDS = [HOST, GUEST, PAL];

let failures = 0;
function check(label, actual, expected) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${actual} (expected ${expected})`,
  );
}

/** Every Live Activity push the code tried to send, by token. */
const sent = [];
let deadTokens = new Set();
setLiveActivityTransportForTesting(async (token, push) => {
  sent.push({ token, push });
  return deadTokens.has(token) ? "dead" : "ok";
});

const tokenFor = (user) =>
  `${Buffer.from(user).toString("hex")}`.padEnd(64, "a").slice(0, 64);

async function settle() {
  // The service's pushes are fired without awaiting; give them a beat.
  await new Promise((r) => setTimeout(r, 150));
}

async function cleanup() {
  await db.query(
    `DELETE FROM in_app_notifications WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(
    `DELETE FROM buddy_live_activities WHERE user_id = ANY($1::text[])`,
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

async function seed() {
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, apple_sub, email, username, first_name, last_name, buddy_enrolled_at)
       VALUES ($1, $2, $3, $4, $5, 'LA', NOW()) ON CONFLICT (user_id) DO NOTHING`,
      [id, `sub-${id}`, `${id}@example.com`, id, id],
    );
  }
  for (const a of FRIENDS) {
    for (const b of FRIENDS) {
      if (a === b) continue;
      await db.query(
        `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, 'accepted')
         ON CONFLICT (user_id, friend_id) DO NOTHING`,
        [a, b],
      );
    }
  }
}

async function rowCount(sessionId, userId) {
  const rows = await db.query(
    `SELECT COUNT(*)::int AS n FROM buddy_live_activities WHERE session_id = $1 AND user_id = $2`,
    [sessionId, userId],
  );
  return Number(rows[0]?.n ?? 0);
}

async function errorCode(fn) {
  try {
    await fn();
    return null;
  } catch (e) {
    return e?.message ?? String(e);
  }
}

async function main() {
  await cleanup();
  await seed();

  // ─── 1. Request shape ───
  const req = buildLiveActivityPushRequest(
    "abc123",
    {
      event: "update",
      contentState: { phase: "countdown", startsAtUnix: 100, crewCount: 2 },
      alert: { title: "t", body: "b" },
      staleDate: 500,
    },
    "com.example.app",
    "bearer-x",
    42,
  );
  const body = JSON.parse(req.body);
  check(
    "topic carries the liveactivity suffix",
    req.headers["apns-topic"],
    "com.example.app.push-type.liveactivity",
  );
  check(
    "push type is liveactivity",
    req.headers["apns-push-type"],
    "liveactivity",
  );
  check("aps.event", body.aps.event, "update");
  check("aps.timestamp", body.aps.timestamp, 42);
  check(
    "aps.content-state carries the phase",
    body.aps["content-state"].phase,
    "countdown",
  );
  check("an alert lights the screen", body.aps.alert.title, "t");
  check("stale-date passes through", body.aps["stale-date"], 500);
  check("nothing but aps at the top level", Object.keys(body).join(","), "aps");

  // ─── 2. Registration ───
  const walk = await createSession(HOST, {
    mode: "together",
    activityType: "walking",
    inviteUserIds: [GUEST, PAL],
  });
  await joinSession(GUEST, { sessionId: walk.id });
  await joinSession(PAL, { sessionId: walk.id });
  check(
    "a stranger can't attach a token",
    await errorCode(() =>
      registerLiveActivity(walk.id, STRANGER, tokenFor(STRANGER), "sandbox"),
    ),
    "not_a_participant",
  );
  check(
    "a malformed token is refused",
    await errorCode(() =>
      registerLiveActivity(walk.id, GUEST, "not hex!", "sandbox"),
    ),
    "invalid_push_token",
  );
  await registerLiveActivity(walk.id, GUEST, tokenFor(GUEST), "sandbox");
  await registerLiveActivity(walk.id, PAL, tokenFor(PAL), "production");
  await registerLiveActivity(walk.id, HOST, tokenFor(HOST), "sandbox");
  check("a guest's token is stored", await rowCount(walk.id, GUEST), 1);
  await registerLiveActivity(walk.id, GUEST, tokenFor(GUEST), "sandbox");
  check(
    "re-registering replaces, never duplicates",
    await rowCount(walk.id, GUEST),
    1,
  );

  // ─── 3. Start → countdown ───
  sent.length = 0;
  await startSession(walk.id, HOST);
  await settle();
  const toGuest = sent.find((s) => s.token === tokenFor(GUEST));
  check(
    "the guest's card gets the countdown",
    toGuest?.push.contentState.phase,
    "countdown",
  );
  check(
    "...with the shared start time",
    typeof toGuest?.push.contentState.startsAtUnix,
    "number",
  );
  check(
    "...alerting, so a pocketed phone lights up",
    typeof toGuest?.push.alert?.title,
    "string",
  );
  check(
    "the other guest's card too",
    sent.some((s) => s.token === tokenFor(PAL)),
    true,
  );
  check(
    "never the host who tapped Start",
    sent.some((s) => s.token === tokenFor(HOST)),
    false,
  );

  // ─── 4. First report ends that walker's card ───
  await db.query(
    `UPDATE buddy_sessions SET started_at = NOW() - INTERVAL '30 seconds' WHERE id = $1`,
    [walk.id],
  );
  sent.length = 0;
  await recordProgress(walk.id, GUEST, 0.05, 30, false, "phone");
  await settle();
  const ended = sent.find((s) => s.token === tokenFor(GUEST));
  check("the guest's first report ends their card", ended?.push.event, "end");
  check("...and dismisses it now", typeof ended?.push.dismissalDate, "number");
  check("...and deletes the row", await rowCount(walk.id, GUEST), 0);
  sent.length = 0;
  await recordProgress(walk.id, GUEST, 0.08, 40, false);
  await settle();
  check("later reports send nothing more", sent.length, 0);

  // ─── 6. Reporting device ───
  let state = await getSessionState(walk.id, HOST);
  const guestRow = () => state.participants.find((p) => p.user_id === GUEST);
  check(
    "a phone report is served as phone",
    guestRow()?.reporting_device,
    "phone",
  );
  await recordProgress(walk.id, GUEST, 0.1, 50, false, "watch");
  state = await getSessionState(walk.id, HOST);
  check(
    "a watch report is served as watch",
    guestRow()?.reporting_device,
    "watch",
  );
  await recordProgress(walk.id, GUEST, 0.12, 55, false);
  state = await getSessionState(walk.id, HOST);
  check(
    "a report that doesn't say leaves it alone",
    guestRow()?.reporting_device,
    "watch",
  );
  check(
    "the host never reported: null",
    state.participants.find((p) => p.user_id === HOST)?.reporting_device,
    null,
  );

  // ─── 5. Leave ends it; a dead token is dropped ───
  sent.length = 0;
  deadTokens = new Set([tokenFor(PAL)]);
  await leaveSession(walk.id, PAL);
  await settle();
  check(
    "leaving ends the card",
    sent.find((s) => s.token === tokenFor(PAL))?.push.event,
    "end",
  );
  check("...and the row is gone", await rowCount(walk.id, PAL), 0);

  setLiveActivityTransportForTesting(null);
  await cleanup();
  console.log(
    failures === 0
      ? "buddy-live-activity-check: all assertions passed"
      : `buddy-live-activity-check: ${failures} FAILED`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch(async (err) => {
  console.error(err);
  await cleanup().catch(() => {});
  process.exit(1);
});
