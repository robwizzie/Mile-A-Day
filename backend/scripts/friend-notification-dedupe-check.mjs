/**
 * Friend workout notifications — ONE walk is ONE announcement.
 *
 * Both friend-facing workout pushes are BUILT at sync time and DELIVERED ten
 * minutes later (`pending_friend_notifications.send_after_at`, the photo-merge
 * window). Which of the two is right depends on whether the day's mile is
 * complete, and the sync path decides that with an if/else — so it can only be
 * right about a single request. Anything that completes the day while a
 * pre-goal 'workout' row is still queued (a recap distance correction, a
 * re-sync that revises the distance up, a duplicate resolution restoring
 * excluded miles) raises the mile announcement beside it, and the cron drains
 * BOTH: a friend gets "X completed a walk" and "X got their mile in!" for one
 * walk, carrying identical stat lines because the edit path restates pending
 * bodies from the database.
 *
 * Method: queue the pre-goal announcement for a short walk, then correct the
 * walk up over the goal exactly as EditWorkoutView does, and assert the runner's
 * friends are told once.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/friend-notification-dedupe-check.mjs
 */

import { PostgresService } from "../dist/services/DbService.js";
import {
  notifyFriendsOfMileCompletion,
  notifyFriendsOfWorkout,
  refreshWorkoutEditNotifications,
} from "../dist/services/notificationService.js";
import { setAudienceSetting } from "../dist/services/audienceSettingsService.js";
import { updateWorkout } from "../dist/services/workoutService.js";

const db = PostgresService.getInstance();

const RUNNER = "fnd-runner";
const FRIEND = "fnd-friend";
const ALL = [RUNNER, FRIEND];
const WORKOUT = "fnd-w-1";
const LATER = "fnd-w-2";

let failures = 0;
function check(label, actual, expected) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${actual}${ok ? "" : ` (expected ${expected})`}`,
  );
}

const ET_DAY = new Intl.DateTimeFormat("en-CA", {
  timeZone: "America/New_York",
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});
const today = () => ET_DAY.format(new Date());

async function cleanup() {
  await db.query(
    `DELETE FROM pending_friend_notifications WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(
    `DELETE FROM milestone_notifications WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  // The mile announcement's once-per-day claim. Nothing in the product ever
  // deletes from this table, so a leftover row makes a re-run of this script
  // silently skip the whole mile path and assert nothing.
  await db.query(
    `DELETE FROM workout_completion_notifications WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(
    `DELETE FROM in_app_notifications WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(
    `DELETE FROM notification_audience_settings WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(
    `DELETE FROM friendships WHERE user_id = ANY($1::text[]) OR friend_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1::text[])`, [ALL]);
}

async function seed() {
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, username, apple_sub, email, created_at, goal_miles)
       VALUES ($1, $2, $3, $4, NOW() - INTERVAL '30 days', 1.0)`,
      [id, id, id, `${id}@example.com`],
    );
  }
  // friendships is per-direction.
  await db.query(
    `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, 'accepted'), ($2, $1, 'accepted')`,
    [RUNNER, FRIEND],
  );

  // The pre-goal 'workout' trigger is opt-in (default audience 'none'), so the
  // reported case is a runner who turned it ON — without this the double can't
  // happen at all and the check would pass vacuously.
  const set = await setAudienceSetting(RUNNER, "outgoing", "workout", "", "all");
  if (set?.validationError) throw new Error(set.validationError);

  // A walk that lands SHORT of the mile: 0.62, the treadmill-recap shape.
  await db.query(
    `INSERT INTO workouts (workout_id, user_id, distance, local_date, date, timezone_offset,
                           workout_type, device_end_date, calories, total_duration, created_at, source)
     VALUES ($1, $2, 0.62, $3::date, $3::date, -300, 'walking',
             NOW() - INTERVAL '5 minutes', 90, 819, NOW() - INTERVAL '5 minutes', 'healthkit')`,
    [WORKOUT, RUNNER, today()],
  );
}

const pending = async (eventType) =>
  (
    await db.query(
      `SELECT status FROM pending_friend_notifications
       WHERE user_id = $1 AND event_type = $2 AND local_date = $3::date`,
      [RUNNER, eventType, today()],
    )
  ).map((r) => r.status);

async function run() {
  await cleanup();
  await seed();

  // 1. Sync-time: the day is short, so the walk announces as itself.
  await notifyFriendsOfWorkout(RUNNER, WORKOUT);
  check(
    "a short walk queues the pre-goal announcement",
    (await pending("workout")).join(","),
    "pending",
  );
  check(
    "...and nothing claims the mile yet",
    (await pending("mile_completed")).length,
    0,
  );

  // 2. The runner corrects the distance on the recap — inside the ten-minute
  //    window, before either row has been delivered.
  await updateWorkout(RUNNER, WORKOUT, { distance: 1.03, source: "edited" });
  await refreshWorkoutEditNotifications(RUNNER, WORKOUT);

  check(
    "the edit raises the mile announcement",
    (await pending("mile_completed")).join(","),
    "pending",
  );
  check(
    "...and RETIRES the walk's own announcement, which it supersedes",
    (await pending("workout")).join(","),
    "expired",
  );

  // The assertion that matches what a friend actually receives.
  const [{ count }] = await db.query(
    `SELECT COUNT(*)::int AS count FROM pending_friend_notifications
     WHERE user_id = $1 AND status = 'pending' AND local_date = $2::date`,
    [RUNNER, today()],
  );
  check("one walk, one push to friends", count, 1);

  // --- A SECOND walk's announcement is not collateral ------------------
  //
  // The supersede has to name the walk the mile is being announced FOR. Keyed
  // on "today's most recent counted workout" instead, an earlier walk edited
  // over the goal expires the LATER walk's row — a true announcement about a
  // different walk — and leaves the edited walk's own row to send beside the
  // mile, which is the double it was supposed to collapse.
  await cleanup();
  await seed();

  // An early short walk, announced as itself.
  await notifyFriendsOfWorkout(RUNNER, WORKOUT);
  // ...then a LATER walk, also short, also announced as itself.
  await db.query(
    `INSERT INTO workouts (workout_id, user_id, distance, local_date, date, timezone_offset,
                           workout_type, device_end_date, calories, total_duration, created_at, source)
     VALUES ($1, $2, 0.30, $3::date, $3::date, -300, 'walking',
             NOW() - INTERVAL '1 minute', 40, 400, NOW() - INTERVAL '1 minute', 'healthkit')`,
    [LATER, RUNNER, today()],
  );
  await notifyFriendsOfWorkout(RUNNER, LATER);
  check(
    "two short walks, two announcements",
    (await pending("workout")).length,
    2,
  );

  // The EARLIER walk is corrected up and crosses the goal.
  await updateWorkout(RUNNER, WORKOUT, { distance: 1.03, source: "edited" });
  await refreshWorkoutEditNotifications(RUNNER, WORKOUT);

  const rows = Object.fromEntries(
    (
      await db.query(
        `SELECT workout_id, status FROM pending_friend_notifications
         WHERE user_id = $1 AND event_type = 'workout'`,
        [RUNNER],
      )
    ).map((r) => [r.workout_id, r.status]),
  );
  check("the edited walk's own announcement is retired", rows[WORKOUT], "expired");
  check("...and the OTHER walk's still stands", rows[LATER], "pending");

  // --- The mile was announced by someone ELSE's call --------------------
  //
  // The reported screenshot: "goose completed a walk · 2.33 mi · 54:46 · best
  // pace 20:13/mi · 2.33 mi today" directly above "goose got their mile in! ·
  // 2.33 mi · 54:46 · best pace 20:13/mi". One walk, two pushes, the same
  // numbers in both.
  //
  // Superseding the walk's own row used to be reachable only THROUGH the call
  // that announced the mile — so when the mile had already been announced
  // (an earlier upload, an earlier edit) every path that could have retired
  // the row skipped it: notifyFriendsOfMileCompletion returns early on its
  // per-day claim, and the edit path only calls it when nothing had announced
  // yet. The row then sat pending while the edit restated its body from the
  // now-complete day, which is what put the same stat line on both.
  await cleanup();
  await seed();

  await notifyFriendsOfWorkout(RUNNER, WORKOUT);
  check(
    "the short walk is announced as itself",
    (await pending("workout")).join(","),
    "pending",
  );

  // The day completes and the mile is announced WITHOUT naming this walk —
  // this is the sync that didn't carry it, or a duplicate resolution.
  await updateWorkout(RUNNER, WORKOUT, { distance: 2.33, source: "edited" });
  await notifyFriendsOfMileCompletion(RUNNER, []);
  check(
    "the mile is queued for friends",
    (await pending("mile_completed")).join(","),
    "pending",
  );

  // Now the walk is touched again — a re-sync, a recap correction. This is
  // where the restate happens, and where the duplicate used to be sealed in.
  await refreshWorkoutEditNotifications(RUNNER, WORKOUT);
  check(
    "the walk's own announcement is retired by a mile it didn't raise",
    (await pending("workout")).join(","),
    "expired",
  );
  const [{ count: afterEdit }] = await db.query(
    `SELECT COUNT(*)::int AS count FROM pending_friend_notifications
     WHERE user_id = $1 AND status = 'pending' AND local_date = $2::date`,
    [RUNNER, today()],
  );
  check("one walk, one push to friends", afterEdit, 1);

  // --- The pre-goal row that arrives AFTER the mile ---------------------
  //
  // The other order, and the one no supersede can fix: two syncs of the same
  // walk interleave, the first reading a short day and queueing its pre-goal
  // row after the second has already claimed the mile and swept. The sweep
  // cannot expire a row that does not exist yet, so the insert has to decline.
  await cleanup();
  await seed();

  await updateWorkout(RUNNER, WORKOUT, { distance: 2.33, source: "edited" });
  await notifyFriendsOfMileCompletion(RUNNER, []);
  await notifyFriendsOfWorkout(RUNNER, WORKOUT);
  check(
    "a pre-goal announcement is not queued once the mile is going out",
    (await pending("workout")).length,
    0,
  );

  // --- An 'ask' mile must not retire anything ---------------------------
  //
  // The confirm card sits in the sender's own inbox with a NULL send_after_at
  // and may never be tapped. Retiring the walk's announcement in favour of it
  // once left a runner telling their friends nothing at all, so the gate is
  // "is the mile REACHING friends", never "does a mile row exist".
  await cleanup();
  await seed();

  const askSet = await setAudienceSetting(
    RUNNER,
    "outgoing",
    "mile_completed",
    "",
    "ask",
  );
  if (askSet?.validationError) throw new Error(askSet.validationError);

  await notifyFriendsOfWorkout(RUNNER, WORKOUT);
  await updateWorkout(RUNNER, WORKOUT, { distance: 2.33, source: "edited" });
  await refreshWorkoutEditNotifications(RUNNER, WORKOUT);
  check(
    "an unconfirmed mile leaves the walk's announcement to send",
    (await pending("workout")).join(","),
    "pending",
  );

  await cleanup();
  console.log(failures === 0 ? "\nall ok" : `\n${failures} FAILED`);
  process.exit(failures === 0 ? 0 : 1);
}

run().catch(async (err) => {
  console.error(err);
  await cleanup().catch(() => {});
  process.exit(1);
});
