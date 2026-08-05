/**
 * Buddy Walks gate + lobby-edit check.
 *
 * The feature shipped fully built and then sat dead in production for weeks
 * because `BUDDY_SESSIONS` was never set, and nothing anywhere failed loudly —
 * every endpoint just 404'd, which the client renders as "We couldn't find that
 * buddy walk". These assertions exist so that class of silence can't come back.
 *
 * Covers, against a real migrated database:
 *   1. the kill switch's DIRECTION (on unless explicitly "false")
 *   2. enrollment riding POST /devices/register, so it can't be missed
 *   3. the opt-out actually removing you from pickers — including the
 *      no-settings-row case, which must read as opted IN
 *   4. the new host-only lobby PATCH and its three guards
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/buddy-gate-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import { buddySessionsEnabled } from "../dist/services/buddyFeatures.js";
import { registerDevice } from "../dist/controllers/deviceController.js";
import {
  createRecurringWalk,
  listRecurringWalks,
  spawnDueRecurringWalks,
  updateRecurringWalk,
} from "../dist/services/buddyRecurringService.js";
import {
  createSession,
  getBuddyPartners,
  getInviteCandidates,
  startSession,
  updateSession,
} from "../dist/services/buddySessionService.js";

const db = PostgresService.getInstance();

const HOST = "buddy-check-host";
const PAL = "buddy-check-pal";
const OPTED_OUT = "buddy-check-optout";
const NO_ROW = "buddy-check-norow";
const ALL = [HOST, PAL, OPTED_OUT, NO_ROW];

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

/** Minimal Express double — registerDevice only touches these. */
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

async function seed() {
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, apple_sub, email, username, first_name, last_name)
       VALUES ($1, $2, $3, $4, $5, 'Buddy')
       ON CONFLICT (user_id) DO NOTHING`,
      [id, `sub-${id}`, `${id}@example.com`, id, id],
    );
  }
  // Everyone is HOST's friend. Friendship rows are directional here.
  for (const id of [PAL, OPTED_OUT, NO_ROW]) {
    for (const [a, b] of [
      [HOST, id],
      [id, HOST],
    ]) {
      await db.query(
        `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, 'accepted')
         ON CONFLICT (user_id, friend_id) DO NOTHING`,
        [a, b],
      );
    }
  }
  // Enrol everyone EXCEPT the one we use to prove registration does the work.
  await db.query(
    `UPDATE users SET buddy_enrolled_at = NOW() WHERE user_id = ANY($1::text[])`,
    [[HOST, OPTED_OUT, NO_ROW]],
  );

  // OPTED_OUT has a settings row saying no. NO_ROW deliberately has NO row at
  // all — the case a plain join would silently hide.
  await db.query(
    `INSERT INTO notification_settings (user_id, buddy_invites_enabled)
     VALUES ($1, FALSE)
     ON CONFLICT (user_id) DO UPDATE SET buddy_invites_enabled = FALSE`,
    [OPTED_OUT],
  );
  await db.query(`DELETE FROM notification_settings WHERE user_id = $1`, [
    NO_ROW,
  ]);
}

async function cleanup() {
  await db.query(
    `DELETE FROM buddy_session_participants WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(
    `DELETE FROM buddy_sessions WHERE host_user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM device_tokens WHERE user_id = ANY($1::text[])`, [
    ALL,
  ]);
  // The invite path writes an inbox row even with no device token registered,
  // and that row holds a FK on users — so it has to go before the users do.
  await db.query(
    `DELETE FROM in_app_notifications WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(
    `DELETE FROM notification_settings WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(
    `DELETE FROM friendships WHERE user_id = ANY($1::text[]) OR friend_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM users WHERE user_id = ANY($1::text[])`, [ALL]);
}

async function main() {
  await cleanup();
  await seed();

  // ── 1. The kill switch's direction ──────────────────────────────────
  //
  // This is THE regression. Unset must mean ON: the old default (`=== "true"`)
  // meant an unconfigured environment served 404s from every buddy endpoint
  // with nothing in the logs.
  const savedFlag = process.env.BUDDY_SESSIONS;
  delete process.env.BUDDY_SESSIONS;
  check("unset → feature is ON", buddySessionsEnabled(), true);
  process.env.BUDDY_SESSIONS = "false";
  check('"false" → feature is OFF', buddySessionsEnabled(), false);
  process.env.BUDDY_SESSIONS = "true";
  check('"true" → feature is ON', buddySessionsEnabled(), true);
  if (savedFlag === undefined) delete process.env.BUDDY_SESSIONS;
  else process.env.BUDDY_SESSIONS = savedFlag;

  // ── 2. Enrollment rides device registration ─────────────────────────
  //
  // PAL was left unenrolled by seed(). Registering a device that DECLARES the
  // capability must enroll them; one that doesn't must leave them alone.
  await registerDevice(
    {
      userId: PAL,
      body: {
        device_token: "buddy-check-token-pal",
        environment: "sandbox",
        client_features: ["buddy_walks_v1"],
      },
    },
    fakeRes(),
  );
  const [palRow] = await db.query(
    `SELECT (buddy_enrolled_at IS NOT NULL) AS enrolled FROM users WHERE user_id = $1`,
    [PAL],
  );
  check("declaring buddy_walks_v1 enrolls", palRow?.enrolled, true);

  await db.query(
    `UPDATE users SET buddy_enrolled_at = NULL WHERE user_id = $1`,
    [PAL],
  );
  await registerDevice(
    {
      userId: PAL,
      body: {
        device_token: "buddy-check-token-old",
        environment: "sandbox",
        client_features: ["friend_request_v2"],
      },
    },
    fakeRes(),
  );
  const [oldBuild] = await db.query(
    `SELECT (buddy_enrolled_at IS NOT NULL) AS enrolled FROM users WHERE user_id = $1`,
    [PAL],
  );
  check(
    "a build without the string stays unenrolled",
    oldBuild?.enrolled,
    false,
  );

  // Put PAL back for the rest of the run.
  await db.query(
    `UPDATE users SET buddy_enrolled_at = NOW() WHERE user_id = $1`,
    [PAL],
  );

  // ── 3. The opt-out, and the no-settings-row default ─────────────────
  const candidates = await getInviteCandidates(HOST);
  const ids = new Set(candidates.map((c) => c.user_id));
  check("an enrolled friend is offered", ids.has(PAL), true);
  check("an opted-out friend is NOT offered", ids.has(OPTED_OUT), false);
  // The COALESCE case: notification_settings is created lazily on first write,
  // so most users have no row. A plain join would hide every one of them.
  check("a friend with no settings row IS offered", ids.has(NO_ROW), true);

  // The picker isn't the only door — an id can be posted directly.
  const session = await createSession(HOST, {
    mode: "together",
    activityType: "walking",
    inviteUserIds: [PAL, OPTED_OUT],
    origin: "invite",
  });
  const invited = await db.query(
    `SELECT user_id FROM buddy_session_participants
      WHERE session_id = $1 AND status = 'invited'`,
    [session.id],
  );
  const invitedIds = new Set(invited.map((r) => r.user_id));
  check(
    "a posted invite reaches an opted-in friend",
    invitedIds.has(PAL),
    true,
  );
  check(
    "a posted invite is dropped for an opted-out friend",
    invitedIds.has(OPTED_OUT),
    false,
  );

  // ── 4. The lobby PATCH ──────────────────────────────────────────────
  const edited = await updateSession(session.id, HOST, {
    mode: "coop_goal",
    goalValue: 3,
    activityType: "running",
  });
  check("host can change the mode", edited.mode, "coop_goal");
  // Snake_case: `toState` emits the wire shape the iOS client decodes, not the
  // camelCase the PATCH input uses.
  check("host can change the goal", Number(edited.goal_value), 3);
  check("host can change walk→run", edited.activity_type, "running");

  // Switching to a scored mode with no goal is a 400, not a silent NULL that
  // would leave a coop session nobody can complete.
  check(
    "a scored mode with no goal is rejected",
    await errorCode(() =>
      updateSession(session.id, HOST, { mode: "race_goal", goalValue: null }),
    ),
    "goal_required",
  );

  // Absent leaves the schedule alone; explicit null clears it.
  await updateSession(session.id, HOST, {
    scheduledStartAt: new Date(Date.now() + 3600_000).toISOString(),
  });
  await updateSession(session.id, HOST, { goalValue: 4 });
  const [stillBooked] = await db.query(
    `SELECT (scheduled_start_at IS NOT NULL) AS booked FROM buddy_sessions WHERE id = $1`,
    [session.id],
  );
  check("an absent schedule is left untouched", stillBooked?.booked, true);

  await updateSession(session.id, HOST, { scheduledStartAt: null });
  const [cleared] = await db.query(
    `SELECT (scheduled_start_at IS NULL) AS cleared FROM buddy_sessions WHERE id = $1`,
    [session.id],
  );
  check("an explicit null clears the schedule", cleared?.cleared, true);

  // A participant is not a host.
  check(
    "a non-host cannot edit",
    await errorCode(() => updateSession(session.id, PAL, { goalValue: 9 })),
    "not_host",
  );

  // Adding people from the lobby goes through the same eligibility rules.
  await updateSession(session.id, HOST, { inviteUserIds: [NO_ROW, OPTED_OUT] });
  const after = await db.query(
    `SELECT user_id FROM buddy_session_participants WHERE session_id = $1`,
    [session.id],
  );
  const afterIds = new Set(after.map((r) => r.user_id));
  check("lobby invite adds an eligible friend", afterIds.has(NO_ROW), true);
  check(
    "lobby invite still drops an opted-out friend",
    afterIds.has(OPTED_OUT),
    false,
  );

  // Once it starts, the plan is frozen — changing the mode mid-walk would
  // rescore distance people have already covered.
  await startSession(session.id, HOST);
  check(
    "an active session can no longer be edited",
    await errorCode(() => updateSession(session.id, HOST, { goalValue: 5 })),
    "session_not_editable",
  );

  // ── 5. Recurring walks ──────────────────────────────────────────────
  //
  // The timezone arithmetic is the risk here: "6pm on weekdays" is a LOCAL
  // wall-clock rule, and a stored instant would drift an hour twice a year.
  // So every assertion drives the spawn through the host's own zone.
  const TZ = "America/New_York";
  const nowLocal = new Date(
    new Date().toLocaleString("en-US", { timeZone: TZ }),
  );
  const localMinutes = nowLocal.getHours() * 60 + nowLocal.getMinutes();
  const localDow = nowLocal.getDay();

  // Due RIGHT NOW: inside the [start-15, start+10) spawn window.
  const routine = await createRecurringWalk(HOST, {
    mode: "together",
    activityType: "walking",
    inviteUserIds: [PAL, OPTED_OUT],
    daysOfWeek: [localDow],
    minutesOfDay: localMinutes,
    timezone: TZ,
  });
  check("a routine is stored", routine.days_of_week?.length, 1);

  const spawned = await spawnDueRecurringWalks();
  check("a due routine spawns exactly one walk", spawned, 1);

  const spawnedRows = await db.query(
    `SELECT id, scheduled_start_at FROM buddy_sessions
      WHERE host_user_id = $1 AND scheduled_start_at IS NOT NULL`,
    [HOST],
  );
  check("the spawned walk is scheduled", spawnedRows.length, 1);

  // The claim is what stops overlapping containers double-spawning on deploy.
  check("a second sweep does not re-spawn", await spawnDueRecurringWalks(), 0);

  // Invitees are re-validated at spawn, not trusted from when the routine was
  // set up — a routine outlives the friendships that created it.
  const spawnedInvites = await db.query(
    `SELECT user_id FROM buddy_session_participants WHERE session_id = $1`,
    [spawnedRows[0].id],
  );
  const spawnedIds = new Set(spawnedInvites.map((r) => r.user_id));
  check("a spawned walk invites an eligible friend", spawnedIds.has(PAL), true);
  check(
    "a spawned walk drops an opted-out friend",
    spawnedIds.has(OPTED_OUT),
    false,
  );

  // Turning it off must actually stop it.
  await db.query(
    `UPDATE buddy_recurring_walks SET last_spawned_date = NULL WHERE id = $1`,
    [routine.id],
  );
  await updateRecurringWalk(HOST, routine.id, { isActive: false });
  check("a paused routine never spawns", await spawnDueRecurringWalks(), 0);

  // A routine for a DIFFERENT weekday must not fire today.
  await updateRecurringWalk(HOST, routine.id, {
    isActive: true,
    daysOfWeek: [(localDow + 3) % 7],
  });
  check("a routine for another day never spawns", await spawnDueRecurringWalks(), 0);

  // ...and one whose time has long passed is skipped rather than fired stale.
  await updateRecurringWalk(HOST, routine.id, {
    daysOfWeek: [localDow],
    // 3 hours ago, well outside the 10-minute grace.
    minutesOfDay: (localMinutes + 1440 - 180) % 1440,
  });
  check(
    "a routine hours past its time is skipped",
    await spawnDueRecurringWalks(),
    0,
  );

  // A zone Postgres can't resolve would raise inside the cron and abort the
  // sweep for every OTHER user, so it's refused at write time.
  check(
    "an invalid timezone is rejected",
    await errorCode(() =>
      createRecurringWalk(HOST, {
        mode: "together",
        activityType: "walking",
        daysOfWeek: [1],
        minutesOfDay: 600,
        timezone: "Mars/Olympus_Mons",
      }),
    ),
    "invalid_timezone",
  );
  check(
    "an empty day list is rejected",
    await errorCode(() =>
      createRecurringWalk(HOST, {
        mode: "together",
        activityType: "walking",
        daysOfWeek: [],
        minutesOfDay: 600,
        timezone: TZ,
      }),
    ),
    "invalid_days",
  );

  check("routines list for their owner", (await listRecurringWalks(HOST)).length, 1);
  check("routines are per-user", (await listRecurringWalks(PAL)).length, 0);

  // ── 6. Miles walked together ────────────────────────────────────────
  //
  // Derived, never stored, so the risk is the JOIN shape rather than drift.
  const together = await db.query(
    `INSERT INTO buddy_sessions
       (join_code, host_user_id, mode, activity_type, status, origin, local_date)
     VALUES ('TGTHR1', $1, 'together', 'walking', 'completed', 'invite', CURRENT_DATE)
     RETURNING id`,
    [HOST],
  );
  const togetherId = together[0].id;
  await db.query(
    `INSERT INTO buddy_session_participants
       (session_id, user_id, status, final_distance_miles)
     VALUES ($1, $2, 'finished', 1.5), ($1, $3, 'finished', 1.4)`,
    [togetherId, HOST, PAL],
  );

  const partners = await getBuddyPartners(HOST);
  check("a finished walk shows up as a partner", partners.length, 1);
  check("the partner is the right person", partners[0]?.user_id, PAL);
  // YOUR miles, not the pooled 2.9 — a pooled figure double-counts the same
  // walk from each side, so the two of you would see different numbers.
  check("miles are the viewer's own", Number(partners[0]?.miles_together), 1.5);
  check("walks are counted", partners[0]?.walks, 1);

  // A walk the other person abandoned isn't a walk you took together.
  await db.query(
    `UPDATE buddy_session_participants SET status = 'left'
      WHERE session_id = $1 AND user_id = $2`,
    [togetherId, PAL],
  );
  check(
    "an abandoned walk does not count",
    (await getBuddyPartners(HOST)).length,
    0,
  );
  await db.query(
    `UPDATE buddy_session_participants SET status = 'finished'
      WHERE session_id = $1 AND user_id = $2`,
    [togetherId, PAL],
  );

  // Un-friend them and the history stops being readable — you walked with
  // them, but that doesn't entitle you to their profile forever.
  await db.query(
    `DELETE FROM friendships WHERE user_id = $1 AND friend_id = $2`,
    [HOST, PAL],
  );
  check(
    "history is withheld once the friendship ends",
    (await getBuddyPartners(HOST)).length,
    0,
  );

  await cleanup();

  console.log(
    failures === 0
      ? "buddy-gate-check: all assertions passed"
      : `buddy-gate-check: ${failures} FAILED`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch(async (err) => {
  console.error(err);
  await cleanup().catch(() => {});
  process.exit(1);
});
