/**
 * Team competition scoring check — the TEAM is the competitor.
 *
 * A team is scored over its members' COMBINED per-interval quantity, using the
 * exact same rules an individual is scored by. It used to be scored as the SUM
 * OF ITS MEMBERS' SCORES, which asks a different question for every
 * per-interval type:
 *
 *   Clash    the day's point went to whichever team owned the single furthest
 *            runner, so a team totalling 3.1 miles beat one totalling 5.7
 *   Targets  each member had to clear the goal alone, so two people covering
 *            1.4 + 1.2 against a 2-mile goal banked nothing
 *   Streaks  each member held their own streak and spent their own lives, so a
 *            roster of casual walkers bled out while the team walked plenty
 *
 * Every one of these fails SILENTLY: nothing 500s, the standings are just
 * wrong in a way only someone adding up their own team's miles would catch.
 * So each seed below is built so the two rules give OPPOSITE answers — a check
 * that passes under both proves nothing.
 *
 * Apex and Race are in here as regression guards: their score already IS
 * distance, so the sum of member scores and the team's combined quantity are
 * the same number, and this refactor must not move them.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/competition-team-scoring-check.mjs
 */

import { PostgresService } from "../dist/services/DbService.js";
import {
  getCompetition,
  getUserScores,
  resolveExpiredCompetitions,
} from "../dist/services/competitionService.js";
import { checkLeadChanges } from "../dist/services/notificationService.js";

const db = PostgresService.getInstance();

// Red = Alice + Bob, Blue = Carl + Dana.
const ALICE = "ts-alice";
const BOB = "ts-bob";
const CARL = "ts-carl";
const DANA = "ts-dana";
const ALL = [ALICE, BOB, CARL, DANA];
const RED = "team-red";
const BLUE = "team-blue";

const CLASH = "ts-clash";
const CLASH_LEGACY = "ts-clash-legacy";
const TARGETS = "ts-targets";
const STREAKS = "ts-streaks";
const APEX = "ts-apex";
const RESOLVE = "ts-resolve";
const COMPS = [CLASH, CLASH_LEGACY, TARGETS, STREAKS, APEX, RESOLVE];

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
const round2 = (n) => Math.round(n * 100) / 100;

async function cleanup() {
  await db.query(
    `DELETE FROM competition_users WHERE competition_id = ANY($1::text[])`,
    [COMPS],
  );
  await db.query(`DELETE FROM competitions WHERE id = ANY($1::text[])`, [COMPS]);
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(
    `DELETE FROM milestone_notifications WHERE competition_id = ANY($1::text[])`,
    [COMPS],
  );
  // Resolution pushes a "competition finished" row per participant, which FKs
  // to users — so the teardown has to outlive the feature it exercises.
  await db.query(
    `DELETE FROM in_app_notifications WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM users WHERE user_id = ANY($1::text[])`, [ALL]);
}

let w = 0;
async function addWorkout(userId, daysAgo, distance) {
  await db.query(
    `INSERT INTO workouts (workout_id, user_id, distance, local_date, date,
                           timezone_offset, workout_type, device_end_date,
                           calories, total_duration, source)
     VALUES ($1, $2, $3, $4::date, $4::date, -300, 'walking',
             $4::date + INTERVAL '18 hours', 100, 900, 'healthkit')`,
    [`ts-w-${++w}`, userId, distance, dayOffset(daysAgo)],
  );
}

/**
 * One competition, teams Red/Blue, over an explicit window of COMPLETE days.
 *
 * Each competition type gets its OWN window because workouts belong to a user,
 * not to a competition: three types sharing one window means every seed lands
 * in all three, which is how the first run of this file reported a Streaks team
 * that never missed a day and an Apex total 3.6 miles over.
 */
async function comp(
  id,
  type,
  options,
  { from = 3, to = null, legacy = false } = {},
) {
  await db.query(
    `INSERT INTO competitions (id, competition_name, start_date, end_date, workouts,
                               type, options, teams, ended, owner, legacy_team_scoring)
     VALUES ($1, $1, $2::date, $8::date, '["walking"]'::jsonb, $3, $4::jsonb, $5::jsonb,
             false, $6, $7)`,
    [
      id,
      dayOffset(from),
      type,
      JSON.stringify(options),
      JSON.stringify({
        member_pick: false,
        teams: [
          { id: RED, name: "Red" },
          { id: BLUE, name: "Blue" },
        ],
      }),
      ALICE,
      legacy,
      to === null ? null : dayOffset(to),
    ],
  );
  for (const [user, team] of [
    [ALICE, RED],
    [BOB, RED],
    [CARL, BLUE],
    [DANA, BLUE],
  ]) {
    await db.query(
      `INSERT INTO competition_users (competition_id, user_id, invite_status, team_id)
       VALUES ($1, $2, 'accepted', $3)`,
      [id, user, team],
    );
  }
}

const teamScore = (competition, teamId) =>
  round2(competition.teams.teams.find((t) => t.id === teamId)?.score ?? -1);
const teamLives = (competition, teamId) =>
  competition.teams.teams.find((t) => t.id === teamId)?.remaining_lives ?? -1;
const contribution = (competition, userId) =>
  round2(
    competition.users.find((u) => u.user_id === userId)?.team_contribution ?? -1,
  );

async function seed() {
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, username, apple_sub, email, created_at, goal_miles)
       VALUES ($1, $2, $3, $4, NOW() - INTERVAL '60 days', 1.0)`,
      [id, id, id, `${id}@example.com`],
    );
  }

  // The seed the whole feature turns on. Every completed day:
  //   Red  = Alice 3.0 + Bob 0.1 = 3.1
  //   Blue = Carl  2.9 + Dana 2.8 = 5.7
  // Alice is the furthest INDIVIDUAL every single day, so summing member
  // scores gives Red a clean sweep while Blue outwalks them by 2.6 mi a day.
  for (const daysAgo of [1, 2, 3]) {
    await addWorkout(ALICE, daysAgo, 3.0);
    await addWorkout(BOB, daysAgo, 0.1);
    await addWorkout(CARL, daysAgo, 2.9);
    await addWorkout(DANA, daysAgo, 2.8);
  }

  await comp(CLASH, "clash", { interval: "day", goal: 1, first_to: 99 });
  // Byte-identical, except it was already decided under the old rule.
  await comp(
    CLASH_LEGACY,
    "clash",
    { interval: "day", goal: 1, first_to: 99 },
    { legacy: true },
  );
  await comp(APEX, "apex", { interval: "day", goal: 1, first_to: 99 });
  // Resolution: first team to 2 daily wins. Blue takes every day.
  await comp(RESOLVE, "clash", { interval: "day", goal: 1, first_to: 2 });

  // --- Targets, days 12..10: a 2-mile daily goal --------------------------
  // Red clears it TOGETHER (1.4 + 1.2 = 2.6) and neither member ever alone,
  // so the old rule banked Red nothing at all. Blue clears it together at 2.5
  // and also has Carl clearing it by himself, so Blue scores under both rules
  // — which is what makes Red the assertion that can tell them apart.
  await comp(TARGETS, "targets", { interval: "day", goal: 2, first_to: 99 }, {
    from: 12,
    to: 10,
  });
  for (const daysAgo of [10, 11, 12]) {
    await addWorkout(ALICE, daysAgo, 1.4);
    await addWorkout(BOB, daysAgo, 1.2);
    await addWorkout(CARL, daysAgo, 2.5);
  }

  // --- Streaks, days 8..6: a 1-mile daily goal, 2 shared lives ------------
  // Neither Red member clears a mile alone on any day; together they clear it
  // every day. Under the old rule both would have burned through their lives
  // and been eliminated with zero. Blue carries it on Carl and drops day 8.
  await comp(STREAKS, "streaks", { interval: "day", goal: 1, lives: 2 }, {
    from: 8,
    to: 6,
  });
  for (const [user, byDay] of [
    [ALICE, { 6: 0.6, 7: 0.6, 8: 0.6 }],
    [BOB, { 6: 0.6, 7: 0.6, 8: 0.6 }],
    [CARL, { 6: 1.5, 7: 1.5, 8: 0.5 }],
  ]) {
    for (const [daysAgo, distance] of Object.entries(byDay)) {
      await addWorkout(user, Number(daysAgo), distance);
    }
  }
}

async function run() {
  await cleanup();
  await seed();

  // --- Clash: the day's point goes to the team that went furthest ---------
  const clash = await getCompetition(CLASH);
  check("clash: the team with the most miles takes every day", teamScore(clash, BLUE), 3);
  check("clash: owning the furthest runner wins nothing", teamScore(clash, RED), 0);

  // The individual leaderboard is a separate view and must not move — team
  // play is a layer on top, not a replacement.
  const clashScores = await getUserScores(clash);
  check(
    "clash: individual standings still credit the furthest runner",
    clashScores[ALICE].score,
    3,
  );
  check("clash: ...and nobody else", clashScores[CARL].score, 0);

  // A member's own score no longer explains their team's, so the contribution
  // is the only number on a member row that adds up to anything.
  check("clash: contribution is the member's own miles", contribution(clash, ALICE), 9);
  check("clash: ...including the one who barely walked", contribution(clash, BOB), 0.3);
  check(
    "clash: and the two contributions make the team's total",
    round2(contribution(clash, CARL) + contribution(clash, DANA)),
    17.1,
  );

  // --- The stamp: a competition already decided keeps the rule that decided it
  const legacy = await getCompetition(CLASH_LEGACY);
  check(
    "legacy stamp: the superseded rule still sums member scores",
    teamScore(legacy, RED),
    3,
  );
  check("legacy stamp: ...and Blue still gets nothing", teamScore(legacy, BLUE), 0);

  // --- Targets: the goal is the TEAM's ------------------------------------
  const targets = await getCompetition(TARGETS);
  check(
    "targets: a team clears the goal together — 1.4 + 1.2 against a 2-mile day, nobody alone",
    teamScore(targets, RED),
    3,
  );
  check(
    "targets: and the team that also had a solo clear is unchanged",
    teamScore(targets, BLUE),
    3,
  );
  const targetScores = await getUserScores(targets);
  check(
    "targets: individually, neither Red member ever cleared it",
    targetScores[ALICE].score + targetScores[BOB].score,
    0,
  );

  // --- Streaks: one shared pool of lives ----------------------------------
  const streaks = await getCompetition(STREAKS);
  check(
    "streaks: 0.6 + 0.6 keeps a 1-mile day alive (alone, both would be out)",
    teamScore(streaks, RED),
    3,
  );
  check("streaks: ...spending no lives", teamLives(streaks, RED), 2);
  check("streaks: a team that misses a day banks the other two", teamScore(streaks, BLUE), 2);
  check("streaks: ...and spends one shared life for it", teamLives(streaks, BLUE), 1);

  // --- Apex: unchanged, because its score already IS distance -------------
  const apex = await getCompetition(APEX);
  check("apex: the team's miles are still just its miles", teamScore(apex, RED), 9.3);
  check("apex: ...for both teams", teamScore(apex, BLUE), 17.1);

  // --- Lead-change pushes name TEAMS on a team competition -----------------
  // Alice is the furthest individual every day and her team is LOSING. The
  // old push ranked people, so her upload told everyone "Alice just took the
  // lead". Now the leader is Team Blue: an upload from Alice announces
  // nothing, an upload from Carl (Blue) tells Red that Team Blue leads and
  // tells Blue their team is first.
  await db.query(
    `DELETE FROM in_app_notifications WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await checkLeadChanges(ALICE);
  const afterAlice = await db.query(
    `SELECT user_id, body FROM in_app_notifications
      WHERE user_id = ANY($1::text[]) AND type = 'competition_milestone'
        AND data->>'competition_id' = $2`,
    [ALL, APEX],
  );
  check(
    "lead push: the furthest INDIVIDUAL on the losing team announces no lead",
    afterAlice.length,
    0,
  );
  // Alice's run indexed everyone's rank (Blue = 1), and "took the lead" only
  // fires for a NEW leader — so un-index before the Blue upload.
  await db.query(
    `UPDATE competition_users SET last_known_rank = NULL WHERE competition_id = $1`,
    [APEX],
  );
  await checkLeadChanges(CARL);
  const afterCarl = await db.query(
    `SELECT user_id, title, body FROM in_app_notifications
      WHERE user_id = ANY($1::text[]) AND type = 'competition_milestone'
        AND data->>'competition_id' = $2
      ORDER BY user_id`,
    [ALL, APEX],
  );
  const bodyFor = (uid) => afterCarl.find((r) => r.user_id === uid)?.body ?? "";
  check(
    "lead push: the losing team is told which TEAM leads",
    bodyFor(ALICE).startsWith("Team Blue just took the lead"),
    true,
  );
  check("lead push: ...every member of it", bodyFor(BOB).startsWith("Team Blue"), true);
  check(
    "lead push: the uploader hears it as their team's lead",
    afterCarl.find((r) => r.user_id === CARL)?.title,
    "Your team's in first!",
  );
  check(
    "lead push: ...and so does their teammate",
    afterCarl.find((r) => r.user_id === DANA)?.title,
    "Your team's in first!",
  );
  // Red overtakes: the dethroned TEAM is told which team passed it.
  await db.query(
    `DELETE FROM in_app_notifications WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await addWorkout(ALICE, 0, 20);
  await checkLeadChanges(ALICE);
  const afterOvertake = await db.query(
    `SELECT user_id, title, body FROM in_app_notifications
      WHERE user_id = ANY($1::text[]) AND type = 'competition_milestone'
        AND data->>'competition_id' = $2`,
    [ALL, APEX],
  );
  const overtakeRow = (uid) => afterOvertake.find((r) => r.user_id === uid);
  check(
    "lead push: the dethroned team hears it as a TEAM loss",
    overtakeRow(CARL)?.title,
    "Your team lost 1st!",
  );
  check(
    "lead push: ...naming both teams",
    overtakeRow(DANA)?.body?.startsWith("Team Red passed Team Blue"),
    true,
  );
  check(
    "lead push: ...and ONLY that — not a generic lead change on top of it",
    afterOvertake.filter((r) => r.user_id === CARL).length,
    1,
  );
  check(
    "lead push: the uploader's teammate hears their team is first",
    overtakeRow(BOB)?.title,
    "Your team's in first!",
  );
  await db.query(`DELETE FROM workouts WHERE workout_id = $1`, [`ts-w-${w}`]);

  // --- A team nobody joined is not a competitor ---------------------------
  // Streaks is where this bites: an empty team misses the goal every day, so
  // left in the scoring set it is an entity that eliminates itself, and a
  // two-team competition with one empty team ends on the first cron tick as a
  // "sole survivor" nobody was playing against.
  await db.query(
    `UPDATE competitions SET teams = $1::jsonb WHERE id = $2`,
    [
      JSON.stringify({
        member_pick: false,
        teams: [
          { id: RED, name: "Red" },
          { id: BLUE, name: "Blue" },
          { id: "team-ghost", name: "Ghost" },
        ],
      }),
      STREAKS,
    ],
  );
  const withGhost = await getCompetition(STREAKS);
  check(
    "empty team: scores nothing rather than being eliminated",
    teamScore(withGhost, "team-ghost"),
    0,
  );
  check(
    "empty team: and holds no lives to lose",
    withGhost.teams.teams.find((t) => t.id === "team-ghost")?.remaining_lives ??
      "absent",
    "absent",
  );
  check(
    "empty team: the real teams are unchanged by it",
    teamScore(withGhost, RED),
    3,
  );

  // --- Resolution: the team that wins is the one that gets the medals -----
  await resolveExpiredCompetitions();
  const [resolved] = await db.query(
    `SELECT winner, ended FROM competitions WHERE id = $1`,
    [RESOLVE],
  );
  check("first_to: the competition resolved", resolved?.ended, true);
  check(
    "first_to: the winner is the winning TEAM's biggest contributor, not the furthest runner",
    resolved?.winner,
    CARL,
  );
  const places = Object.fromEntries(
    (
      await db.query(
        `SELECT user_id, placement FROM competition_users WHERE competition_id = $1`,
        [RESOLVE],
      )
    ).map((r) => [r.user_id, r.placement]),
  );
  check("first_to: the winning team shares 1st", places[CARL], 1);
  check("first_to: ...both of them", places[DANA], 1);
  check("first_to: the losing team shares 2nd", places[ALICE], 2);
  check("first_to: ...including its top individual scorer", places[BOB], 2);

  await cleanup();
  console.log(failures === 0 ? "\nall ok" : `\n${failures} FAILED`);
  process.exit(failures === 0 ? 0 : 1);
}

run().catch(async (err) => {
  console.error(err);
  await cleanup().catch(() => {});
  process.exit(1);
});
