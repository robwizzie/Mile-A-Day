/**
 * Admin analytics panel check.
 *
 * The admin dashboard's feature-usage panels are aggregate SQL over a dozen
 * tables nothing else reads together, and every way they break breaks
 * SILENTLY. A mistyped column 500s the tab and you notice; a wrong join, a
 * missed `deleted_at`, or an auto route card counted as a photo just reports
 * a plausible number that is WRONG, and nobody diffs a dashboard against the
 * database by hand. These numbers decide what gets built next, so a quietly
 * wrong one is worse than a blank panel.
 *
 * Method: snapshot the panels, seed a known world (users, competitions in
 * every lifecycle state, spent streak tokens, photos vs auto cards, a
 * referral chain, a buddy walk), snapshot again, and assert the DELTA is
 * exactly what that world implies. Deltas rather than absolutes because CI
 * runs this after other seeded checks and prod-shaped data is never empty.
 *
 * The baseline pass also asserts the shapes that only break on a quiet table
 * — a zero-length axis, an average over no rows — since "works with data" is
 * no evidence a metrics query survives a day when nobody competed.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/admin-analytics-check.mjs
 */

import { PostgresService } from "../dist/services/DbService.js";
import {
  getCompetitionStats,
  getStreakTokenStats,
  getFeatureAdoption,
  getCommunityStats,
  getReferralGraph,
  getRetentionCohorts,
  getActivityRhythms,
  getPulse,
  resetAnalyticsCaches,
  getDrilldown,
  DRILLDOWN_KINDS,
  getTrends,
  getActivation,
  getAtRisk,
  setReferralAlias,
  clearReferralAlias,
} from "../dist/services/adminAnalyticsService.js";
import { getUsers } from "../dist/services/adminService.js";

const db = PostgresService.getInstance();

const ALICE = "adm-alice";
const BOB = "adm-bob";
const CAROL = "adm-carol";
const DAVE = "adm-dave";
const ERIN = "adm-erin";
const FRANK = "adm-frank";
const ALL = [ALICE, BOB, CAROL, DAVE, ERIN, FRANK];
const COMPS = ["adm-c-live", "adm-c-soon", "adm-c-done", "adm-c-open"];
const SESSION = "adm-b-1";

let failures = 0;
function check(label, actual, expected) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${actual}${ok ? "" : ` (expected ${expected})`}`,
  );
}
function truthy(label, value) {
  const ok = Boolean(value);
  if (!ok) failures++;
  console.log(`${ok ? "ok  " : "FAIL"}  ${label}`);
}

/** Every panel, freshly loaded (the service caches, so drop it first). */
async function snapshot() {
  resetAnalyticsCaches();
  return {
    competitions: await getCompetitionStats(),
    tokens: await getStreakTokenStats(),
    adoption: await getFeatureAdoption(),
    community: await getCommunityStats(),
    referrals: await getReferralGraph(),
    retention: await getRetentionCohorts(),
    rhythms: await getActivityRhythms(),
    pulse: await getPulse(),
    trends: await getTrends(),
    activation: await getActivation(),
    atRisk: await getAtRisk(),
  };
}

// ET calendar days, the same clock as the service's TODAY_ET_DATE_SQL. This
// used to be the UTC date, which is already TOMORROW for four hours every
// evening (8 PM–midnight ET): the d=0 rows then sat outside every ET-aligned
// window, "14 person-days" read 12, and the gate went red on any evening run
// — including the one that merges a fix. Negative n = days ahead.
const ET_DAY = new Intl.DateTimeFormat("en-CA", {
  timeZone: "America/New_York",
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});
const dayOffset = (n) => ET_DAY.format(new Date(Date.now() - n * 86_400_000));

async function cleanup() {
  // Children first. `users` cascades to most of this, but the columns that
  // hold a user id as plain text with no FK (streak_coverage.source_user) do
  // not, and competitions.winner is ON DELETE SET NULL rather than cascade.
  await db.query(
    `DELETE FROM buddy_session_participants WHERE session_id = $1`,
    [SESSION],
  );
  await db.query(`DELETE FROM buddy_sessions WHERE id = $1`, [SESSION]);
  await db.query(
    `DELETE FROM competition_users WHERE competition_id = ANY($1::text[])`,
    [COMPS],
  );
  await db.query(`DELETE FROM competitions WHERE id = ANY($1::text[])`, [
    COMPS,
  ]);
  await db.query(
    `DELETE FROM streak_coverage WHERE source_user = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM hype_log WHERE sender_id = ANY($1::text[])`, [
    ALL,
  ]);
  await db.query(`DELETE FROM posts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(
    `DELETE FROM friendships WHERE user_id = ANY($1::text[]) OR friend_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM users WHERE user_id = ANY($1::text[])`, [ALL]);
}

async function seed() {
  // Six users. Carol and Dave both name Alice at onboarding, in two different
  // spellings ("@adm-alice" and " Adm-Alice ") — one referrer, one bucket.
  // Erin names Bob. Frank names an account that does not exist: the unmatched
  // half the graph has to report rather than quietly drop.
  const users = [
    [ALICE, 12],
    [BOB, 3],
    [CAROL, 0],
    [DAVE, 40],
    [ERIN, 8],
    [FRANK, 0],
  ];
  for (const [id, streak] of users) {
    await db.query(
      `INSERT INTO users (user_id, username, apple_sub, email, current_streak, created_at,
                          streak_features_at, goal_miles)
       VALUES ($1, $2, $3, $4, $5, NOW() - INTERVAL '40 days',
               NOW() - INTERVAL '40 days', 1.0)`,
      [id, id, id, `${id}@example.com`, streak],
    );
  }
  const refer = (who, typed) =>
    db.query(
      `UPDATE users SET referral_source = 'friend', referral_detail = $2 WHERE user_id = $1`,
      [who, typed],
    );
  await refer(CAROL, `@${ALICE}`);
  await refer(DAVE, ` Adm-Alice `);
  await refer(ERIN, BOB);
  await refer(FRANK, "adm-ghost");

  // Alice ran the last 10 days, Dave the last 3 (so only Dave reads as an
  // active referral). One of Alice's workouts is soft-deleted and one of
  // Bob's is vehicle-speed excluded — neither may reach any count here.
  let w = 0;
  const addWorkout = (userId, daysAgo, extra = {}) =>
    db.query(
      `INSERT INTO workouts (workout_id, user_id, distance, local_date, date, timezone_offset,
                             workout_type, device_end_date, calories, total_duration, created_at,
                             deleted_at, exclusion_reason, ghost_friend_user_id, source)
       VALUES ($1, $2, $3, $4::date, $4::date, -300, $5, $4::date + INTERVAL '18 hours', 100, 900,
               NOW() - ($6::int || ' days')::interval, $7, $8, $9, $10)`,
      [
        `adm-w-${++w}`,
        userId,
        extra.distance ?? 1.2,
        dayOffset(daysAgo),
        extra.type ?? "running",
        daysAgo,
        extra.deleted ? new Date().toISOString() : null,
        extra.exclusion ?? null,
        extra.ghost ?? null,
        extra.source ?? "healthkit",
      ],
    );

  for (let d = 0; d < 10; d++) await addWorkout(ALICE, d);
  for (let d = 0; d < 3; d++) await addWorkout(DAVE, d);
  await addWorkout(ALICE, 20, { deleted: true });
  await addWorkout(BOB, 1, { exclusion: "vehicle_speed" });
  await addWorkout(BOB, 2, { ghost: ALICE });
  await addWorkout(CAROL, 40, { source: "manual" });

  // One competition in each lifecycle state: running with a calendar end, not
  // started yet, finished, and running with NO end date (a first-to/duration
  // competition, which must still read as live rather than falling off).
  const comps = [
    [COMPS[0], "Live Clash", "clash", dayOffset(3), dayOffset(-4), false],
    [COMPS[1], "Next Week", "race", dayOffset(-2), dayOffset(-9), false],
    [COMPS[2], "Last Month", "apex", dayOffset(40), dayOffset(33), true],
    [COMPS[3], "Open Ended", "targets", dayOffset(1), null, false],
  ];
  for (const [id, name, type, start, end, ended] of comps) {
    await db.query(
      `INSERT INTO competitions (id, competition_name, type, start_date, end_date, ended,
                                 workouts, options, owner, winner, created_at)
       VALUES ($1, $2, $3, $4::date, $5::date, $6, '["run"]'::jsonb, '{}'::jsonb, $7,
               CASE WHEN $6 THEN $7 ELSE NULL END, NOW() - INTERVAL '5 days')`,
      [id, name, type, start, end, ended, ALICE],
    );
  }
  await db.query(`UPDATE competitions SET teams = '[]'::jsonb WHERE id = $1`, [
    COMPS[0],
  ]);
  for (const [comp, user, status] of [
    [COMPS[0], ALICE, "accepted"],
    [COMPS[0], BOB, "accepted"],
    [COMPS[0], CAROL, "pending"],
    [COMPS[1], ALICE, "accepted"],
    [COMPS[2], ALICE, "accepted"],
    [COMPS[2], DAVE, "declined"],
    [COMPS[3], BOB, "accepted"],
  ]) {
    await db.query(
      `INSERT INTO competition_users (competition_id, user_id, invite_status)
       VALUES ($1, $2, $3)`,
      [comp, user, status],
    );
  }

  // One token of each kind spent, an accepted and a pending assist offer, an
  // open injury pause, and a recorded break.
  for (const [user, date, kind, source] of [
    [ALICE, dayOffset(5), "streak_save", null],
    [BOB, dayOffset(4), "double_down_recover", null],
    [CAROL, dayOffset(2), "streak_assist", ALICE],
  ]) {
    await db.query(
      `INSERT INTO streak_coverage (user_id, local_date, kind, source_user)
       VALUES ($1, $2::date, $3, $4)`,
      [user, date, kind, source],
    );
  }
  await db.query(
    `UPDATE users SET streak_save_last_used = $2::date, streak_assist_last_used = $3::date
     WHERE user_id = $1`,
    [ALICE, dayOffset(5), dayOffset(2)],
  );
  await db.query(
    `INSERT INTO streak_assist_offers (donor_id, recipient_id, initiator, target_date, status)
     VALUES ($1, $2, 'donor', $3::date, 'accepted'),
            ($4, $5, 'recipient', $6::date, 'pending')`,
    [ALICE, CAROL, dayOffset(2), BOB, DAVE, dayOffset(1)],
  );
  await db.query(
    `INSERT INTO streak_pauses (user_id, started_on, frozen_streak) VALUES ($1, $2::date, 8)`,
    [ERIN, dayOffset(6)],
  );
  await db.query(
    `INSERT INTO streak_events (user_id, local_date, kind, prior_streak)
     VALUES ($1, $2::date, 'break', 11)`,
    [FRANK, dayOffset(3)],
  );

  // Alice: 2 real photos + 1 auto route card. Bob: 1 photo. Carol: 1 photo
  // she deleted — the auto card and the deleted one must count for nobody.
  const posts = [
    [ALICE, false, false],
    [ALICE, false, false],
    [ALICE, true, false],
    [BOB, false, false],
    [CAROL, false, true],
  ];
  let pi = 0;
  for (const [user, isAuto, deleted] of posts) {
    await db.query(
      `INSERT INTO posts (user_id, media_url, local_date, is_auto, share_to_feed, deleted_at, created_at)
       VALUES ($1, '/uploads/posts/' || $2 || '.jpg', $3::date, $4, TRUE,
               CASE WHEN $5 THEN NOW() ELSE NULL END, NOW())`,
      [user, `adm-p${++pi}`, dayOffset(1), isAuto, deleted],
    );
  }

  // Accepted friendships are stored BIDIRECTIONALLY: two pairs, four rows.
  for (const [a, b, status] of [
    [ALICE, BOB, "accepted"],
    [BOB, ALICE, "accepted"],
    [ALICE, CAROL, "accepted"],
    [CAROL, ALICE, "accepted"],
    [DAVE, ERIN, "pending"],
  ]) {
    await db.query(
      `INSERT INTO friendships (user_id, friend_id, status, created_at)
       VALUES ($1, $2, $3, NOW() - INTERVAL '2 days')`,
      [a, b, status],
    );
  }

  await db.query(
    `INSERT INTO hype_log (sender_id, target_id, context_type, created_at)
     VALUES ($1, $2, 'post', NOW() - INTERVAL '1 day')`,
    [ALICE, BOB],
  );
  await db.query(
    `INSERT INTO buddy_sessions (id, join_code, host_user_id, mode, activity_type, status,
                                 origin, local_date, created_at)
     VALUES ($1, 'ADMC01', $2, 'together', 'running', 'active', 'invite', $3::date, NOW())`,
    [SESSION, ALICE, dayOffset(0)],
  );
  await db.query(
    `INSERT INTO buddy_session_participants (session_id, user_id, status, joined_at)
     VALUES ($1, $2, 'active', NOW()), ($1, $3, 'active', NOW())`,
    [SESSION, ALICE, BOB],
  );
}

async function main() {
  await cleanup();

  console.log("\n--- baseline (shapes that only break on a quiet table) ---");
  const before = await snapshot();
  check(
    "streak histogram always has all 5 buckets",
    before.rhythms.streak_buckets.length,
    5,
  );
  check(
    "token spend chart covers 30 days",
    before.tokens.spend_by_day.length,
    30,
  );
  check(
    "competition chart covers 12 weeks",
    before.competitions.by_week.length,
    12,
  );
  truthy(
    "avg roster is finite, never NaN over zero competitions",
    Number.isFinite(before.competitions.summary.avg_roster),
  );
  truthy(
    "avg buddy crew is finite",
    Number.isFinite(before.community.buddy.avg_crew),
  );
  truthy(
    "avg friends is finite",
    Number.isFinite(before.community.friends.avg_friends),
  );
  truthy("adoption lists every feature", before.adoption.features.length >= 15);
  check("trends carry a 30-day axis", before.trends.days.length, 30);
  check("and say which window they are", before.trends.window_days, 30);
  truthy(
    "every trend has a 30-point sparkline aligned to it",
    before.trends.metrics.every((t) => t.spark.length === 30),
  );
  truthy(
    "a trend with no prior period reports no percentage rather than +100%",
    before.trends.metrics.every((t) => t.previous > 0 || t.change_pct === null),
  );
  truthy(
    "activation lists every milestone",
    before.activation.steps.length >= 8,
  );
  truthy(
    "every retention cell is a real percentage",
    before.retention.cohorts.every((c) =>
      c.weeks.every((w) => w.pct >= 0 && w.pct <= 100),
    ),
  );

  await seed();
  const after = await snapshot();

  /** What the seeded world adds on top of whatever was already there. */
  const d = (path) => {
    const get = (o) => path.split(".").reduce((a, k) => a?.[k], o);
    return get(after) - get(before);
  };

  console.log("\n--- competitions ---");
  check("total competitions", d("competitions.summary.total"), 4);
  check(
    "live (incl. the one with no end date)",
    d("competitions.summary.live"),
    2,
  );
  check("upcoming", d("competitions.summary.upcoming"), 1);
  check("finished", d("competitions.summary.finished"), 1);
  check("team competitions", d("competitions.summary.team_competitions"), 1);
  // ALICE and BOB accept; CAROL's invite is only pending, and a pending
  // invite is not a player.
  check("distinct players", d("competitions.summary.players"), 2);
  check("invites accepted", d("competitions.summary.invites_accepted"), 5);
  check("invites pending", d("competitions.summary.invites_pending"), 1);
  check("invites declined", d("competitions.summary.invites_declined"), 1);
  const live = after.competitions.live.find((c) => c.id === COMPS[0]);
  check("live roster", live?.players, 2);
  check("live pending invites", live?.pending, 1);
  check("team play flagged", live?.team_play, true);
  check(
    "an open-ended competition reports no days_left",
    after.competitions.live.find((c) => c.id === COMPS[3])?.days_left,
    null,
  );
  truthy(
    "a finished competition is NOT in the live list",
    !after.competitions.live.some((c) => c.id === COMPS[2]),
  );
  check(
    "organizer credited with 4",
    after.competitions.top_organizers.find((o) => o.user_id === ALICE)?.created,
    4,
  );
  check(
    "winner credited with 1",
    after.competitions.top_winners.find((o) => o.user_id === ALICE)?.wins,
    1,
  );

  console.log("\n--- streak tokens ---");
  check("enrolled users", d("tokens.enrollment.enrolled"), 6);
  check("ever spent a Streak Save", d("tokens.enrollment.ever_streak_save"), 1);
  check("ever spent an Assist", d("tokens.enrollment.ever_assist"), 1);
  const spend = (kind) =>
    (after.tokens.spend_by_kind.find((k) => k.kind === kind)?.total ?? 0) -
    (before.tokens.spend_by_kind.find((k) => k.kind === kind)?.total ?? 0);
  check("streak_save spends", spend("streak_save"), 1);
  check("double_down_recover spends", spend("double_down_recover"), 1);
  check("streak_assist spends", spend("streak_assist"), 1);
  const assistCell = (snap, date) =>
    snap.tokens.spend_by_day.find((x) => x.date === date)?.streak_assist ?? 0;
  check(
    "the rescued day shows on the chart",
    assistCell(after, dayOffset(2)) - assistCell(before, dayOffset(2)),
    1,
  );
  check("meter population", d("tokens.held.enrolled"), 6);
  // Alice ran 10 days but spent her Save 5 days ago, so only ~5 running days
  // sit inside her window — under the 7-day target. Nobody else ran at all.
  check("nobody has earned a Streak Save yet", d("tokens.held.streak_save"), 0);
  // Assist is pure elapsed time: everyone but Alice (spent 2 days ago) holds one.
  check("Assist holders", d("tokens.held.streak_assist"), 5);
  check("assist offers accepted", d("tokens.assist_funnel.accepted"), 1);
  check("assist offers pending", d("tokens.assist_funnel.pending"), 1);
  check("open injury pauses", d("tokens.pauses.active"), 1);
  check("recorded breaks", d("tokens.breaks.total"), 1);
  check(
    "donor credited with the assist",
    after.tokens.top_donors.find((x) => x.user_id === ALICE)?.assists,
    1,
  );

  console.log("\n--- feature adoption ---");
  const featDelta = (key, field) =>
    (after.adoption.features.find((f) => f.key === key)?.[field] ?? 0) -
    (before.adoption.features.find((f) => f.key === key)?.[field] ?? 0);
  check("total users", d("adoption.total_users"), 6);
  check("photo posters", featDelta("photo_post", "users_ever"), 2);
  check(
    "photo events exclude the auto card and the deleted one",
    featDelta("photo_post", "events_ever"),
    3,
  );
  check("competition joiners (accepted only)", featDelta("competition", "users_ever"), 2);
  check("buddy walkers", featDelta("buddy", "users_ever"), 2);
  check("token spenders", featDelta("streak_token", "users_ever"), 3);
  check("injury pausers", featDelta("injury_pause", "users_ever"), 1);
  check("ghost racers", featDelta("ghost_race", "users_ever"), 1);
  check("hand-entered workouts", featDelta("manual_workout", "users_ever"), 1);
  check("friend adders", featDelta("friend", "users_ever"), 3);
  check("hypers", featDelta("hype", "users_ever"), 1);

  console.log("\n--- community ---");
  check(
    "friend pairs (bidirectional rows halved)",
    d("community.friends.pairs"),
    2,
  );
  check("pending requests", d("community.friends.pending"), 1);
  check("connected users", d("community.friends.connected_users"), 3);
  check("users with nobody", d("community.friends.solo_users"), 3);
  check("buddy sessions", d("community.buddy.sessions"), 1);
  check("buddy sessions live now", d("community.buddy.live_now"), 1);
  check(
    "top photographer counts real photos only",
    after.community.top_photographers.find((p) => p.user_id === ALICE)?.photos,
    2,
  );

  console.log("\n--- referrals ---");
  check("friend-referred signups", d("referrals.summary.friend_referred"), 4);
  check("resolved to a real account", d("referrals.summary.matched"), 3);
  check("left unresolved", d("referrals.summary.unmatched"), 1);
  const alice = after.referrals.referrers.find((r) => r.referrer_id === ALICE);
  check("two spellings fold into one referrer", alice?.count, 2);
  check("only the one still running counts as active", alice?.active, 1);
  truthy(
    "an unresolved name is still reported, as typed",
    after.referrals.referrers.some(
      (r) => !r.referrer_id && r.typed_as === "adm-ghost",
    ),
  );
  truthy(
    "each referrer carries the people they brought in",
    (alice?.referred ?? []).some((u) => u.user_id === DAVE),
  );

  console.log("\n--- users directory ---");
  const byPhotos = await getUsers({
    search: "adm-",
    limit: 10,
    offset: 0,
    sort: "photos",
  });
  check(
    "photo sort ranks the photographer first",
    byPhotos.users[0]?.user_id,
    ALICE,
  );
  check(
    "photo count excludes auto route cards",
    byPhotos.users[0]?.photo_count,
    2,
  );
  check("post count still includes them", byPhotos.users[0]?.post_count, 3);
  check(
    "a deleted photo counts for nobody",
    byPhotos.users.find((u) => u.user_id === CAROL)?.photo_count,
    0,
  );

  console.log("\n--- rhythms + pulse ---");
  check(
    "streak histogram still totals every user",
    after.rhythms.streak_buckets.reduce((a, b) => a + b.users, 0) -
      before.rhythms.streak_buckets.reduce((a, b) => a + b.users, 0),
    6,
  );
  truthy("the activity clock has buckets", after.rhythms.clock.length > 0);
  check("pulse: live competitions", d("pulse.competitions_live"), 2);
  check("pulse: buddy sessions today", d("pulse.buddy_sessions_today"), 1);
  check("pulse: photos today", d("pulse.photos_today"), 3);

  console.log("\n--- counting people vs counting events ---");
  // The bug this exists to catch: "active people" summed its DAILY distinct
  // counts, so somebody active on ten days counted as ten people and the
  // headline read larger than the entire user base. Inside the 30-day window
  // ALICE ran 10 separate days, DAVE 3 and BOB 1 — 14 person-days, but only
  // 3 PEOPLE, and 3 is what the card must say. (CAROL's one workout is 40
  // days back, outside the window entirely.)
  const activeTrend = after.trends.metrics.find((t) => t.key === "active_users");
  const activeBefore = before.trends.metrics.find(
    (t) => t.key === "active_users",
  );
  const dailySum = activeTrend.spark.reduce((a, b) => a + b, 0);
  const dailySumBefore = activeBefore.spark.reduce((a, b) => a + b, 0);
  check(
    "the daily series still sums to every person-day",
    dailySum - dailySumBefore,
    14,
  );
  check(
    "but the window total counts each person once",
    activeTrend.current - activeBefore.current,
    3,
  );
  truthy(
    "a people metric is flagged so the UI can say the bars do not add up",
    activeTrend.distinct === true,
  );
  const milesMetric = after.trends.metrics.find((t) => t.key === "miles");
  truthy(
    "an event metric still totals its days",
    Math.abs(
      milesMetric.spark.reduce((a, b) => a + b, 0) - milesMetric.current,
    ) < 0.01,
  );

  // A shorter window is a different question, not a slice of the same answer.
  const week = await getTrends(7);
  check("a 7-day window returns 7 days", week.days.length, 7);
  check("and says so", week.window_days, 7);
  const weekActive = week.metrics.find((t) => t.key === "active_users");
  truthy(
    "its distinct total never exceeds the 30-day one",
    weekActive.current <= activeTrend.current,
  );

  console.log("\n--- activation, trends, at-risk ---");
  const step = (k) => after.activation.steps.find((x) => x.key === k)?.users;
  const stepBefore = (k) =>
    before.activation.steps.find((x) => x.key === k)?.users ?? 0;
  check("signed up", step("signed_up") - stepBefore("signed_up"), 6);
  // ALICE (10 days), DAVE (3), CAROL (one hand-entered mile) and BOB, whose
  // ghost run counts — only his OTHER workout is vehicle-speed excluded.
  // ERIN and FRANK never ran at all.
  check(
    "logged a first mile",
    step("first_mile") - stepBefore("first_mile"),
    4,
  );
  check(
    "came back three days",
    step("three_days") - stepBefore("three_days"),
    2,
  );
  check("added a friend", step("friend") - stepBefore("friend"), 3);
  check("posted a photo", step("photo") - stepBefore("photo"), 2);

  const milesTrend = after.trends.metrics.find((t) => t.key === "miles");
  truthy("miles trend has a current window", milesTrend.current > 0);
  check("its sparkline is 30 days", milesTrend.spark.length, 30);
  truthy(
    "and the window total matches the sparkline it draws",
    Math.abs(
      milesTrend.spark.reduce((a, b) => a + b, 0) - milesTrend.current,
    ) < 0.01,
  );

  // ALICE ran today, so she is not at risk; DAVE ran today too. Nobody
  // seeded has a streak >= 3 AND a missing day, except ERIN (streak 8, never
  // ran) — who is on an open injury pause and must therefore be excluded.
  const atRiskIds = after.atRisk.map((r) => r.user_id);
  truthy(
    "an injury-paused user is never called at risk",
    !atRiskIds.includes(ERIN),
  );
  truthy(
    "somebody who already ran today is not at risk",
    !atRiskIds.includes(ALICE),
  );

  const activationDrill = await getDrilldown("activation_step", "photo");
  truthy(
    "the activation drill-down lists who has NOT reached the milestone",
    activationDrill.rows.some((r) => r.user_id === DAVE) &&
      !activationDrill.rows.some((r) => r.user_id === ALICE),
  );

  // ── Drill-downs ────────────────────────────────────────────────────
  // Every panel number is clickable, and the list behind it must agree with
  // the number that opened it — a drawer that says "3 people" under a bar
  // reading 5 is worse than no drawer.
  console.log("\n--- drill-downs ---");

  const dd = (kind, id) => getDrilldown(kind, id ?? null);

  const photoRows = await dd("feature", "photo_post");
  truthy(
    "the photo drill-down lists the two photographers",
    [ALICE, BOB].every((u) => photoRows.rows.some((r) => r.user_id === u)),
  );
  truthy(
    "and not the one whose only photo was deleted",
    !photoRows.rows.some((r) => r.user_id === CAROL),
  );
  check(
    "its per-user count matches the adoption events",
    photoRows.rows.find((r) => r.user_id === ALICE)?.stat,
    "2×",
  );

  const compRows = await dd("competition", COMPS[0]);
  check("competition drill-down names it", compRows.title, "Live Clash");
  check("and lists every invite, accepted or not", compRows.rows.length, 3);

  const tokenRows = await dd("token", "streak_assist");
  const rescue = tokenRows.rows.find((r) => r.user_id === CAROL);
  truthy("assist drill-down finds the rescue", Boolean(rescue));
  check("and credits the donor by name", rescue?.subtitle, `saved by @${ALICE}`);

  const bucketRows = await dd("streak_bucket", "30–99");
  truthy(
    "the 30–99 streak band contains the 40-day streaker",
    bucketRows.rows.some((r) => r.user_id === DAVE),
  );
  truthy(
    "and not the 12-day one",
    !bucketRows.rows.some((r) => r.user_id === ALICE),
  );

  const buddyRows = await dd("buddy_origin", "invite");
  const hosted = buddyRows.rows.find((r) => r.user_id === ALICE);
  truthy("buddy origin drill-down finds the session", Boolean(hosted));
  check("with its crew size", hosted?.subtitle, "2 walked · active");

  const typeRows = await dd("workout_type", "running");
  truthy(
    "workout-type drill-down excludes the deleted and excluded workouts",
    typeRows.rows.find((r) => r.user_id === ALICE)?.subtitle === "10 workouts",
  );

  check("an unknown feature key resolves to nothing", await dd("feature", "nope"), null);
  check("an unknown streak band resolves to nothing", await dd("streak_bucket", "7"), null);
  check("an unknown badge resolves to nothing", await dd("badge", "nope"), null);

  const todayPhotos = await dd("today", "photos");
  const postedToday = todayPhotos.rows.filter((r) =>
    ALL.includes(r.user_id),
  );
  check("today's photos list both posters' shots", postedToday.length, 3);
  truthy(
    "including both people",
    new Set(postedToday.map((r) => r.user_id)).size === 2,
  );
  truthy(
    "and never the photo that was deleted",
    !todayPhotos.rows.some((r) => r.user_id === CAROL),
  );
  truthy(
    "and an unknown today-key resolves to nothing",
    (await dd("today", "nope")) === null,
  );

  const bySource = await dd("referral_source", "friend");
  const mine = bySource.rows.filter((r) => ALL.includes(r.user_id));
  check("the friend-referred are listable", mine.length, 4);
  truthy(
    "and each row shows what they actually typed",
    mine.every((r) => (r.subtitle ?? "").startsWith("said:")),
  );

  const trendDay = await dd("trend_day", `miles|${dayOffset(0)}`);
  truthy(
    "a trend bar opens the people behind that day",
    trendDay.rows.some((r) => r.user_id === ALICE),
  );
  check(
    "a malformed trend-day id resolves to nothing",
    await dd("trend_day", "miles|not-a-date"),
    null,
  );
  check(
    "an unknown trend metric resolves to nothing",
    await dd("trend_day", `nope|${dayOffset(0)}`),
    null,
  );

  console.log("\n--- linking a referral nobody matched ---");
  const ghostBefore = after.referrals.referrers.find(
    (r) => r.typed_as === "adm-ghost",
  );
  check("starts unresolved", ghostBefore?.referrer_id ?? null, null);
  check(
    "linking to a non-existent account is refused",
    (await setReferralAlias("adm-ghost", "nobody-at-all", null)).ok,
    false,
  );
  await setReferralAlias("  @ADM-Ghost ", BOB, ALICE);
  resetAnalyticsCaches();
  const linked = await getReferralGraph();
  const ghostAfter = linked.referrers.find((r) => r.referrer_id === BOB);
  truthy(
    "a typed name links to a real account, whatever its spelling",
    Boolean(ghostAfter),
  );
  truthy("and is marked as resolved by hand", ghostAfter?.linked_by_hand);
  check(
    "the link moves the matched/unmatched split",
    linked.summary.unmatched - after.referrals.summary.unmatched,
    -1,
  );
  await clearReferralAlias("adm-ghost");
  resetAnalyticsCaches();
  const unlinked = await getReferralGraph();
  check(
    "and unlinking puts it back",
    unlinked.referrers.some((r) => r.typed_as === "adm-ghost"),
    true,
  );

  // Every declared kind must answer without throwing, including on ids that
  // match nothing — the drawer opens before it knows there are rows.
  for (const kind of DRILLDOWN_KINDS) {
    try {
      await dd(kind, "definitely-not-a-real-id");
      console.log(`ok    ${kind} survives an unknown id`);
    } catch (err) {
      failures++;
      console.log(`FAIL  ${kind} threw on an unknown id: ${err.message}`);
    }
  }

  if (!process.env.KEEP_SEED) await cleanup();

  console.log(
    failures === 0
      ? "\nadmin-analytics-check: PASS"
      : `\nadmin-analytics-check: ${failures} FAILURE(S)`,
  );
  await db.close();
  process.exit(failures === 0 ? 0 : 1);
}

main().catch(async (err) => {
  console.error("admin-analytics-check crashed:", err);
  await cleanup().catch(() => {});
  process.exit(1);
});
