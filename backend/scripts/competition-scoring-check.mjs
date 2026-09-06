/**
 * Competition scoring check — device-measured miles only.
 *
 * Competitions score what a DEVICE recorded. A hand-entered workout
 * (`source = 'manual'`) is dropped outright; a workout a user edited
 * (`source = 'edited'`) counts the figure the device recorded
 * (`original_distance`), not the number typed over it. Editing stays a
 * legitimate treadmill correction everywhere else in the app — it just can't
 * be the thing that wins a competition, because nothing verifies it.
 *
 * Every way this breaks breaks SILENTLY: a missed call site doesn't 500, it
 * just reports a standing that includes miles nobody ran, and the calendar
 * breakdown under the score is a SECOND query that has to agree with it.
 * There is also a cutoff — competitions that were already over when the rule
 * shipped keep the numbers they ended with, since standings are recomputed
 * live on every read — and a cutoff is exactly the kind of thing that reads
 * correct and is off by one lifecycle state.
 *
 * Method: seed one live competition and one that ended before the cutoff over
 * the same three participants, and assert the scores each rule implies.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/competition-scoring-check.mjs
 */

import { PostgresService } from "../dist/services/DbService.js";
import {
  getCompetition,
  getUserScores,
} from "../dist/services/competitionService.js";
import { updateWorkout } from "../dist/services/workoutService.js";

const db = PostgresService.getInstance();

const ALICE = "cs-alice";
const BOB = "cs-bob";
const CAROL = "cs-carol";
const DAVE = "cs-dave";
const ALL = [ALICE, BOB, CAROL, DAVE];
const LIVE = "cs-comp-live";
const OLD = "cs-comp-old";
const COMPS = [LIVE, OLD];

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
const dayOffset = (n) => ET_DAY.format(new Date(Date.now() - n * 86_400_000));

async function cleanup() {
  await db.query(
    `DELETE FROM competition_users WHERE competition_id = ANY($1::text[])`,
    [COMPS],
  );
  await db.query(`DELETE FROM competitions WHERE id = ANY($1::text[])`, [
    COMPS,
  ]);
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1::text[])`, [ALL]);
}

let w = 0;
/** Returns the workout_id, so an edit below can name it without counting. */
async function addWorkout(userId, daysAgo, distance, extra = {}) {
  const id = `cs-w-${++w}`;
  await db.query(
    `INSERT INTO workouts (workout_id, user_id, distance, original_distance, local_date, date,
                           timezone_offset, workout_type, device_end_date, calories,
                           total_duration, created_at, source)
     VALUES ($1, $2, $3, $4, $5::date, $5::date, -300, 'walking',
             $5::date + INTERVAL '18 hours', 100, 900,
             NOW() - ($6::int || ' days')::interval, $7)`,
    [
      id,
      userId,
      distance,
      extra.original ?? null,
      dayOffset(daysAgo),
      daysAgo,
      extra.source ?? "healthkit",
    ],
  );
  return id;
}

/** The workout Alice quietly nudged up — asserted on below. */
let aliceNudged;
/** The workout Dave typed in and then edited. */
let daveTyped;

async function seed() {
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, username, apple_sub, email, created_at, goal_miles)
       VALUES ($1, $2, $3, $4, NOW() - INTERVAL '60 days', 1.0)`,
      [id, id, id, `${id}@example.com`],
    );
  }

  // --- The live competition's window (last 5 days) ---------------------
  // Alice walks it honestly. Bob types in a 5-mile workout he did not
  // record. Carol edits a 1.5-mile walk up to 9, and a 3.0-mile one down to
  // 1. Dave types in a workout
  // and then edits THAT — the laundering path: without sticky provenance
  // it stops being 'manual' and starts counting at its typed distance.
  await addWorkout(ALICE, 1, 1.0);
  await addWorkout(ALICE, 2, 2.0);
  await addWorkout(BOB, 1, 1.0);
  await addWorkout(BOB, 2, 5.0, { source: "manual" });
  await addWorkout(CAROL, 1, 9.0, { source: "edited", original: 1.5 });
  // Carol also corrects a treadmill walk DOWN, 3.0 to 1.0 — owning up must
  // not be paid at the device's number.
  const carolCorrected = await addWorkout(CAROL, 2, 3.0);
  await updateWorkout(CAROL, carolCorrected, {
    distance: 1.0,
    source: "edited",
  });
  daveTyped = await addWorkout(DAVE, 1, 4.0, { source: "manual" });
  await updateWorkout(DAVE, daveTyped, { distance: 4.5 });
  // Alice also nudges a 2.0-mile walk to 2.4 — under the edit sheet's 25%
  // line, so it is never flagged and `source` stays 'healthkit'. Only
  // `original_distance` records that a person moved the number.
  aliceNudged = await addWorkout(ALICE, 3, 2.0);
  await updateWorkout(ALICE, aliceNudged, {
    distance: 2.4,
    // What EditWorkoutView sends for a distance-only change under 25%: the
    // workout is never marked as touched at all.
    source: "healthkit",
  });

  // --- The old competition's window (days 20..15 ago) ------------------
  // The same three shapes, so the cutoff is the only difference.
  await addWorkout(ALICE, 17, 2.0);
  await addWorkout(BOB, 17, 5.0, { source: "manual" });
  await addWorkout(CAROL, 17, 9.0, { source: "edited", original: 1.5 });

  const comp = (id, start, end, ended) =>
    db.query(
      `INSERT INTO competitions (id, competition_name, start_date, end_date, workouts, type,
                                 options, ended, owner)
       VALUES ($1, $1, $2::date, $3::date, '["walking"]'::jsonb, 'apex',
               '{"interval":"day","goal":1}'::jsonb, $4, $5)`,
      [id, start, end, ended, ALICE],
    );
  await comp(LIVE, dayOffset(5), null, false);
  await comp(OLD, dayOffset(20), dayOffset(15), true);

  for (const id of COMPS) {
    for (const user of ALL) {
      await db.query(
        `INSERT INTO competition_users (competition_id, user_id, invite_status)
         VALUES ($1, $2, 'accepted')`,
        [id, user],
      );
    }
  }
}

const round2 = (n) => Math.round(n * 100) / 100;

async function run() {
  await cleanup();
  await seed();

  // --- Live competition: device-measured -------------------------------
  const live = await getCompetition(LIVE, { includeActivityBreakdown: true });
  const scores = await getUserScores(live);
  check(
    "live: an unflagged sub-25% correction still counts the recorded distance",
    round2(scores[ALICE].score),
    5,
  );
  check("live: hand-entered workout is dropped", round2(scores[BOB].score), 1);
  check(
    "live: an edit up counts what the device measured, an edit down the correction",
    round2(scores[CAROL].score),
    2.5,
  );
  check(
    "live: an edited hand-entry is still a hand-entry",
    round2(scores[DAVE].score),
    0,
  );

  const [dave] = await db.query(
    `SELECT source FROM workouts WHERE workout_id = $1`,
    [daveTyped],
  );
  check("editing a manual workout keeps source='manual'", dave.source, "manual");

  const [aliceEdit] = await db.query(
    `SELECT source, original_distance FROM workouts WHERE workout_id = $1`,
    [aliceNudged],
  );
  check("sub-25% correction stays unflagged", aliceEdit.source, "healthkit");
  check(
    "...but records what the device measured",
    Number(aliceEdit.original_distance),
    2,
  );

  const flag = (id) =>
    live.users.find((u) => u.user_id === id)?.has_manual_workouts;
  check("live: an unflagged correction raises no badge", flag(ALICE), false);
  check("live: hand-entry is flagged", flag(BOB), true);
  check("live: edit is flagged", flag(CAROL), true);

  // The calendar breakdown is a second query and has to agree with the score.
  const activity = (id) =>
    live.users.find((u) => u.user_id === id)?.daily_activity ?? {};
  check(
    "live: breakdown drops the hand-entered day",
    Object.keys(activity(BOB)).length,
    1,
  );
  check(
    "live: breakdown restates the edited distance",
    round2(activity(CAROL)[dayOffset(1)]?.walking?.distance),
    1.5,
  );

  // --- Competition that ended before the cutoff: unchanged -------------
  const old = await getCompetition(OLD);
  const oldScores = await getUserScores(old);
  check("ended-before-cutoff: honest walker", round2(oldScores[ALICE].score), 2);
  check(
    "ended-before-cutoff: hand-entry still counts",
    round2(oldScores[BOB].score),
    5,
  );
  check(
    "ended-before-cutoff: edited distance still counts",
    round2(oldScores[CAROL].score),
    9,
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
