import { PostgresService } from "./DbService.js";
import {
  MIN_PLAUSIBLE_MILE_SECONDS,
  countedWorkoutSql,
} from "./mileTime.js";
import {
  ChallengeCompletionDetailResponse,
  ChallengeFriendRef,
  ChallengeH2hDetail,
  ChallengePostDetail,
  ChallengeSocialDetail,
  ChallengePaceDetail,
  ChallengeActivityDetail,
  ChallengeTimeWindowDetail,
} from "../types/badge.js";
import { ADD_FRIEND_CHALLENGE_KEY } from "./challengeRotation.js";

const db = PostgresService.getInstance();

/**
 * How a past completion was earned, re-derived from source tables at read
 * time (user_challenge_completions stores only the timestamp + workout id).
 * One (user, date) per call — every query here is a handful of indexed rows,
 * and the endpoint is fetched lazily when a completion sheet opens, never in
 * a list.
 */

/** Distinct hyped/nudged friends returned per completion; counts stay uncapped. */
const SOCIAL_FRIENDS_CAP = 12;

export async function getCompletionDetail(
  userId: string,
  localDate: string,
): Promise<ChallengeCompletionDetailResponse | null> {
  const rows = await db.query<{
    local_date: string;
    challenge_key: string;
    completed_at: Date | string | null;
    title: string;
    description_template: string;
    icon: string;
    gradient_start: string;
    gradient_end: string;
  }>(
    `SELECT ucc.local_date::text AS local_date, ucc.challenge_key, ucc.completed_at,
			dc.title, dc.description_template, dc.icon, dc.gradient_start, dc.gradient_end
		FROM user_challenge_completions ucc
		JOIN daily_challenges dc ON dc.challenge_key = ucc.challenge_key
		WHERE ucc.user_id = $1 AND ucc.local_date = $2::date`,
    [userId, localDate],
  );
  const row = rows[0];
  if (!row) return null;

  const detail: ChallengeCompletionDetailResponse = {
    localDate: row.local_date,
    challengeKey: row.challenge_key,
    title: row.title,
    description: row.description_template,
    icon: row.icon,
    gradientStart: row.gradient_start,
    gradientEnd: row.gradient_end,
    completedAt:
      row.completed_at instanceof Date
        ? row.completed_at.toISOString()
        : row.completed_at
          ? String(row.completed_at)
          : null,
    h2h: null,
    post: null,
    social: null,
    steps: null,
    pace: null,
    distance: null,
    timeWindow: null,
    activity: null,
    friend: null,
  };

  switch (row.challenge_key) {
    case "head_to_head":
      detail.h2h = await h2hDetail(userId, localDate);
      break;

    case "share_journey":
      detail.post = await postDetail(userId, localDate);
      break;

    case "hype_squad":
      detail.social = await hypedFriends(userId, localDate);
      break;

    case "wingman":
      detail.social = await nudgedFriends(userId, localDate);
      break;

    case "ten_k_steps": {
      const steps = await stepsFor(userId, localDate);
      detail.steps = steps === null ? null : { steps, goalSteps: 10000 };
      break;
    }

    case "speed_round":
      detail.pace = {
        bestPaceSecondsPerMile: await bestSplitPace(userId, localDate),
        targetPaceSecondsPerMile: 12 * 60,
      };
      break;

    case "beat_your_pace": {
      const pace = await beatYourPaceDetail(userId, localDate);
      detail.pace = pace;
      // Historical description: the target the template advertises is the
      // prior best + 30s AS OF that day, not today's all-time best.
      detail.description =
        pace.targetPaceSecondsPerMile !== null
          ? row.description_template.replace(
              "{avg_pace}",
              formatPaceMinutes(pace.targetPaceSecondsPerMile / 60),
            )
          : "Set a new personal best pace today";
      break;
    }

    case "double_down":
      detail.distance = {
        miles: await dayTotalDistance(userId, localDate),
        targetMiles: 2.0,
        scope: "all",
      };
      break;

    case "bonus_mile":
      detail.distance = {
        miles: await dayTotalDistance(userId, localDate),
        targetMiles: (await getGoalMiles(userId)) + 0.5,
        scope: "all",
      };
      break;

    case "five_k_day":
      detail.distance = {
        miles: await dayTotalDistance(userId, localDate),
        targetMiles: 3.1,
        scope: "all",
      };
      break;

    case "ten_k_day":
      detail.distance = {
        miles: await dayTotalDistance(userId, localDate),
        targetMiles: 6.2,
        scope: "all",
      };
      break;

    case "walk_it_out":
      detail.distance = {
        miles: (await runWalkMix(userId, localDate)).walk,
        targetMiles: await getGoalMiles(userId),
        scope: "walking",
      };
      break;

    case "early_bird":
      detail.timeWindow = await timeWindowDetail(
        userId,
        localDate,
        "early_bird",
      );
      break;

    case "early_or_late":
      detail.timeWindow = await timeWindowDetail(
        userId,
        localDate,
        "early_or_late",
      );
      break;

    case "cross_train": {
      const activity = await activityDetail(userId, localDate);
      activity.variant = await crossTrainVariant(userId, localDate);
      detail.activity = activity;
      break;
    }

    case "two_a_day":
      detail.activity = await activityDetail(userId, localDate);
      break;

    case ADD_FRIEND_CHALLENGE_KEY:
      detail.friend = await firstAcceptedFriend(userId);
      break;

    default:
      break;
  }

  return detail;
}

// ─── Head-to-Head ───────────────────────────────────────────────────

/**
 * The day's duel plus the all-time record against that rival. Miles are
 * re-derived from workouts with the resolver's 2-decimal rounding (late
 * syncs self-heal), and a block in either direction hides the whole section —
 * same rules as getMatchupHistory.
 */
async function h2hDetail(
  userId: string,
  localDate: string,
): Promise<ChallengeH2hDetail | null> {
  const rows = await db.query<{
    rival_id: string;
    mutual: boolean;
    username: string | null;
    profile_image_url: string | null;
    my_miles: string | null;
    rival_miles: string | null;
  }>(
    `SELECT m.rival_id, m.mutual, u.username, u.profile_image_url,
			COALESCE((
				SELECT SUM(w.distance) FROM workouts w
				WHERE w.user_id = m.user_id AND w.local_date = m.local_date
					AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
			), 0)::text AS my_miles,
			COALESCE((
				SELECT SUM(w.distance) FROM workouts w
				WHERE w.user_id = m.rival_id AND w.local_date = m.local_date
					AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
			), 0)::text AS rival_miles
		FROM h2h_matchups m
		JOIN users u ON u.user_id = m.rival_id
		WHERE m.user_id = $1 AND m.local_date = $2::date
			AND NOT EXISTS (
				SELECT 1 FROM user_blocks b
				WHERE (b.blocker_id = $1 AND b.blocked_id = m.rival_id)
					OR (b.blocker_id = m.rival_id AND b.blocked_id = $1)
			)`,
    [userId, localDate],
  );
  const duel = rows[0];
  if (!duel) return null;

  const mine = round2(parseFloat(duel.my_miles ?? "0") || 0);
  const theirs = round2(parseFloat(duel.rival_miles ?? "0") || 0);

  // All-time record vs this rival, over resolved duels only, with the same
  // re-derived miles the history endpoint reports.
  const past = await db.query<{
    my_miles: string | null;
    rival_miles: string | null;
  }>(
    `SELECT
			COALESCE((
				SELECT SUM(w.distance) FROM workouts w
				WHERE w.user_id = m.user_id AND w.local_date = m.local_date
					AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
			), 0)::text AS my_miles,
			COALESCE((
				SELECT SUM(w.distance) FROM workouts w
				WHERE w.user_id = m.rival_id AND w.local_date = m.local_date
					AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
			), 0)::text AS rival_miles
		FROM h2h_matchups m
		WHERE m.user_id = $1 AND m.rival_id = $2 AND m.resolved_at IS NOT NULL`,
    [userId, duel.rival_id],
  );
  const record = { wins: 0, losses: 0, ties: 0 };
  for (const p of past) {
    const a = round2(parseFloat(p.my_miles ?? "0") || 0);
    const b = round2(parseFloat(p.rival_miles ?? "0") || 0);
    if (a > b) record.wins++;
    else if (a < b) record.losses++;
    else record.ties++;
  }

  return {
    rival: {
      userId: duel.rival_id,
      username: duel.username,
      profileImageUrl: duel.profile_image_url,
    },
    myMiles: mine,
    rivalMiles: theirs,
    result: mine > theirs ? "won" : mine < theirs ? "lost" : "tied",
    mutual: duel.mutual === true,
    record,
  };
}

// ─── Share the Journey ──────────────────────────────────────────────

/**
 * The earliest surviving post of that day — the one that completed the
 * challenge. `mediaUrl` is a bare path here; the controller signs it via
 * signMediaUrlsDeep. A since-deleted post returns null (fallback view).
 */
async function postDetail(
  userId: string,
  localDate: string,
): Promise<ChallengePostDetail | null> {
  const rows = await db.query<{
    post_id: string;
    media_url: string;
    caption: string | null;
    created_at: Date | string;
  }>(
    `SELECT post_id, media_url, caption, created_at
		FROM posts
		WHERE user_id = $1 AND local_date = $2::date AND deleted_at IS NULL
		ORDER BY created_at ASC
		LIMIT 1`,
    [userId, localDate],
  );
  const post = rows[0];
  if (!post) return null;
  return {
    postId: post.post_id,
    mediaUrl: post.media_url,
    caption: post.caption,
    createdAt:
      post.created_at instanceof Date
        ? post.created_at.toISOString()
        : String(post.created_at),
  };
}

// ─── Hype Squad / Wingman ───────────────────────────────────────────

/**
 * Timezone expression for mapping an action's created_at onto the user's
 * local day. Prefers the offset of that DAY's workouts (historically honest
 * if the user has moved timezones since) before falling back to the newest
 * workout's offset, mirroring the live evaluators.
 */
function actionLocalDateSql(createdAtCol: string): string {
  return `(${createdAtCol} + (COALESCE(
		(SELECT timezone_offset FROM workouts WHERE user_id = $1 AND local_date = $2::date ORDER BY device_end_date DESC LIMIT 1),
		(SELECT timezone_offset FROM workouts WHERE user_id = $1 ORDER BY device_end_date DESC LIMIT 1),
		0) || ' minutes')::interval)::date = $2::date`;
}

async function hypedFriends(
  userId: string,
  localDate: string,
): Promise<ChallengeSocialDetail | null> {
  const friends = await db.query<{
    target_id: string;
    username: string | null;
    profile_image_url: string | null;
  }>(
    `SELECT h.target_id, u.username, u.profile_image_url
		FROM hype_log h
		JOIN users u ON u.user_id = h.target_id
		WHERE h.sender_id = $1 AND ${actionLocalDateSql("h.created_at")}
			AND NOT EXISTS (
				SELECT 1 FROM user_blocks b
				WHERE (b.blocker_id = $1 AND b.blocked_id = h.target_id)
					OR (b.blocker_id = h.target_id AND b.blocked_id = $1)
			)
		GROUP BY h.target_id, u.username, u.profile_image_url
		ORDER BY MIN(h.created_at) ASC
		LIMIT ${SOCIAL_FRIENDS_CAP}`,
    [userId, localDate],
  );
  if (friends.length === 0) return null;

  const totals = await db.query<{ c: string }>(
    `SELECT COUNT(*)::text AS c FROM hype_log h
		WHERE h.sender_id = $1 AND ${actionLocalDateSql("h.created_at")}`,
    [userId, localDate],
  );

  return {
    friends: friends.map(toFriendRef),
    totalActions: parseInt(totals[0]?.c ?? "0", 10) || friends.length,
  };
}

async function nudgedFriends(
  userId: string,
  localDate: string,
): Promise<ChallengeSocialDetail | null> {
  // Wingman counts friend nudges AND competition nudges, like the evaluator.
  const nudgesSql = `
		SELECT target_id, created_at FROM friend_nudge_log WHERE sender_id = $1 AND ${actionLocalDateSql("created_at")}
		UNION ALL
		SELECT target_id, created_at FROM nudge_log WHERE sender_id = $1 AND ${actionLocalDateSql("created_at")}`;

  const friends = await db.query<{
    target_id: string;
    username: string | null;
    profile_image_url: string | null;
  }>(
    `SELECT n.target_id, u.username, u.profile_image_url
		FROM (${nudgesSql}) n
		JOIN users u ON u.user_id = n.target_id
		WHERE NOT EXISTS (
			SELECT 1 FROM user_blocks b
			WHERE (b.blocker_id = $1 AND b.blocked_id = n.target_id)
				OR (b.blocker_id = n.target_id AND b.blocked_id = $1)
		)
		GROUP BY n.target_id, u.username, u.profile_image_url
		ORDER BY MIN(n.created_at) ASC
		LIMIT ${SOCIAL_FRIENDS_CAP}`,
    [userId, localDate],
  );
  if (friends.length === 0) return null;

  const totals = await db.query<{ c: string }>(
    `SELECT COUNT(*)::text AS c FROM (${nudgesSql}) n`,
    [userId, localDate],
  );

  return {
    friends: friends.map(toFriendRef),
    totalActions: parseInt(totals[0]?.c ?? "0", 10) || friends.length,
  };
}

function toFriendRef(r: {
  target_id: string;
  username: string | null;
  profile_image_url: string | null;
}): ChallengeFriendRef {
  return {
    userId: r.target_id,
    username: r.username,
    profileImageUrl: r.profile_image_url,
  };
}

// ─── Steps ──────────────────────────────────────────────────────────

async function stepsFor(
  userId: string,
  localDate: string,
): Promise<number | null> {
  const rows = await db.query<{ steps: number | null }>(
    `SELECT steps FROM daily_steps WHERE user_id = $1 AND local_date = $2::date`,
    [userId, localDate],
  );
  return rows.length === 0 ? null : (rows[0]?.steps ?? 0);
}

// ─── Pace ───────────────────────────────────────────────────────────

/** Fastest plausible full-mile split that day, seconds per mile. */
async function bestSplitPace(
  userId: string,
  localDate: string,
): Promise<number | null> {
  const rows = await db.query<{ min_pace: string | null }>(
    `SELECT MIN(s.split_pace)::text AS min_pace
		FROM workout_splits s JOIN workouts w ON w.workout_id = s.workout_id
		WHERE w.user_id = $1 AND w.local_date = $2::date
			AND ${countedWorkoutSql("w")}
			AND s.split_pace >= ${MIN_PLAUSIBLE_MILE_SECONDS} AND s.split_distance >= 0.95`,
    [userId, localDate],
  );
  const pace = rows[0]?.min_pace ? parseFloat(rows[0].min_pace) : 0;
  return pace > 0 ? pace : null;
}

/**
 * The target beat_your_pace advertised THAT day: all-time best split before
 * that date + 30s. Splits earlier than the completion date can't change, so
 * this recomputes to exactly what the award-time predicate saw.
 */
async function beatYourPaceDetail(
  userId: string,
  localDate: string,
): Promise<ChallengePaceDetail> {
  const rows = await db.query<{
    prior_min: string | null;
    today_min: string | null;
  }>(
    `WITH prior AS (
			SELECT MIN(s.split_pace) AS p
			FROM workout_splits s JOIN workouts w ON w.workout_id = s.workout_id
			WHERE w.user_id = $1 AND w.local_date < $2::date AND ${countedWorkoutSql("w")}
				AND s.split_pace >= ${MIN_PLAUSIBLE_MILE_SECONDS} AND s.split_distance >= 0.95
		), today AS (
			SELECT MIN(s.split_pace) AS p
			FROM workout_splits s JOIN workouts w ON w.workout_id = s.workout_id
			WHERE w.user_id = $1 AND w.local_date = $2::date AND ${countedWorkoutSql("w")}
				AND s.split_pace >= ${MIN_PLAUSIBLE_MILE_SECONDS} AND s.split_distance >= 0.95
		)
		SELECT prior.p::text AS prior_min, today.p::text AS today_min FROM prior, today`,
    [userId, localDate],
  );
  const prior = rows[0]?.prior_min ? parseFloat(rows[0].prior_min) : 0;
  const today = rows[0]?.today_min ? parseFloat(rows[0].today_min) : 0;
  return {
    bestPaceSecondsPerMile: today > 0 ? today : null,
    targetPaceSecondsPerMile: prior > 0 ? prior + 30 : null,
  };
}

// ─── Time window (Early Bird / Night Owl) ───────────────────────────

/**
 * The qualifying goal-mile workout and which window it landed in. The finish
 * time is rendered in the WORKOUT's own timezone via to_char (a timestamptz
 * would arrive as a JS Date and re-shift with the server's zone).
 */
async function timeWindowDetail(
  userId: string,
  localDate: string,
  key: "early_bird" | "early_or_late",
): Promise<ChallengeTimeWindowDetail | null> {
  const windowPredicate =
    key === "early_bird"
      ? `EXTRACT(HOUR FROM (device_end_date + timezone_offset * INTERVAL '1 minute')) < 12`
      : `(EXTRACT(HOUR FROM (device_end_date + timezone_offset * INTERVAL '1 minute')) < 9
				OR EXTRACT(HOUR FROM (device_end_date + timezone_offset * INTERVAL '1 minute')) >= 20)`;

  const rows = await db.query<{
    distance: string | null;
    local_hm: string;
    local_hour: string;
  }>(
    `SELECT distance::text AS distance,
			to_char(device_end_date + timezone_offset * INTERVAL '1 minute', 'HH24:MI') AS local_hm,
			EXTRACT(HOUR FROM (device_end_date + timezone_offset * INTERVAL '1 minute'))::text AS local_hour
		FROM workouts
		WHERE user_id = $1 AND local_date = $2::date
			AND distance >= (SELECT COALESCE(goal_miles, 1.0) FROM users WHERE user_id = $1) * 0.95
			AND ${windowPredicate}
			AND deleted_at IS NULL AND exclusion_reason IS NULL
		ORDER BY device_end_date ASC
		LIMIT 1`,
    [userId, localDate],
  );
  const w = rows[0];
  if (!w) return null;
  const hour = parseInt(w.local_hour, 10) || 0;
  return {
    window: key === "early_bird" ? "early" : hour < 9 ? "early" : "late",
    finishedLocalTime: w.local_hm ?? null,
    qualifyingMiles: w.distance ? parseFloat(w.distance) || null : null,
  };
}

// ─── Activity (Cross-Train / Two-a-Day) ─────────────────────────────

async function activityDetail(
  userId: string,
  localDate: string,
): Promise<ChallengeActivityDetail> {
  const rows = await db.query<{
    workout_count: string;
    run: string | null;
    walk: string | null;
  }>(
    `SELECT
			COUNT(*) FILTER (WHERE distance > 0)::text AS workout_count,
			COALESCE(SUM(distance) FILTER (WHERE workout_type = 'running'), 0)::text AS run,
			COALESCE(SUM(distance) FILTER (WHERE workout_type = 'walking'), 0)::text AS walk
		FROM workouts
		WHERE user_id = $1 AND local_date = $2::date AND deleted_at IS NULL AND exclusion_reason IS NULL`,
    [userId, localDate],
  );
  return {
    workoutCount: parseInt(rows[0]?.workout_count ?? "0", 10) || 0,
    runMiles: parseFloat(rows[0]?.run ?? "0") || 0,
    walkMiles: parseFloat(rows[0]?.walk ?? "0") || 0,
    variant: null,
  };
}

/**
 * Which cross-train variant that day asked for. Deterministic from the 7 days
 * BEFORE the date (the live selector's exact window), so it recomputes
 * faithfully for history.
 */
async function crossTrainVariant(
  userId: string,
  localDate: string,
): Promise<"walk_today" | "run_today" | "mixed"> {
  const rows = await db.query<{ run: string | null; walk: string | null }>(
    `SELECT
			COALESCE(SUM(distance) FILTER (WHERE workout_type = 'running'), 0)::text AS run,
			COALESCE(SUM(distance) FILTER (WHERE workout_type = 'walking'), 0)::text AS walk
		FROM workouts
		WHERE user_id = $1
		  AND local_date < $2::date
		  AND local_date >= ($2::date - INTERVAL '7 days')::date
		  AND deleted_at IS NULL AND exclusion_reason IS NULL`,
    [userId, localDate],
  );
  const run = parseFloat(rows[0]?.run ?? "0") || 0;
  const walk = parseFloat(rows[0]?.walk ?? "0") || 0;
  const total = run + walk;
  if (total < 0.5) return "mixed";
  const walkRatio = walk / total;
  if (walkRatio < 0.25) return "walk_today";
  if (walkRatio > 0.75) return "run_today";
  return "mixed";
}

// ─── Make a Friend ──────────────────────────────────────────────────

/**
 * The friend behind an add_friend completion. The challenge only ever fires
 * on the 0 → 1 accepted-friend transition, so the earliest surviving
 * friendship IS that friend (an unfriended-since row simply falls back null).
 */
async function firstAcceptedFriend(
  userId: string,
): Promise<ChallengeFriendRef | null> {
  const rows = await db.query<{
    friend_id: string;
    username: string | null;
    profile_image_url: string | null;
  }>(
    `SELECT f.friend_id, u.username, u.profile_image_url
		FROM friendships f
		JOIN users u ON u.user_id = f.friend_id
		WHERE f.user_id = $1 AND f.status = 'accepted'
		ORDER BY f.created_at ASC NULLS FIRST
		LIMIT 1`,
    [userId],
  );
  const f = rows[0];
  if (!f) return null;
  return {
    userId: f.friend_id,
    username: f.username,
    profileImageUrl: f.profile_image_url,
  };
}

// ─── Shared helpers (mirrors of dailyChallengeService's private ones) ─

async function dayTotalDistance(
  userId: string,
  localDate: string,
): Promise<number> {
  const rows = await db.query<{ total: string | null }>(
    `SELECT COALESCE(SUM(distance),0)::text AS total FROM workouts
		WHERE user_id = $1 AND local_date = $2::date AND deleted_at IS NULL AND exclusion_reason IS NULL`,
    [userId, localDate],
  );
  return parseFloat(rows[0]?.total ?? "0") || 0;
}

async function runWalkMix(
  userId: string,
  localDate: string,
): Promise<{ run: number; walk: number }> {
  const rows = await db.query<{
    workout_type: string | null;
    total: string | null;
  }>(
    `SELECT workout_type, COALESCE(SUM(distance),0)::text AS total
		FROM workouts
		WHERE user_id = $1 AND local_date = $2::date AND deleted_at IS NULL AND exclusion_reason IS NULL
		GROUP BY workout_type`,
    [userId, localDate],
  );
  let run = 0;
  let walk = 0;
  for (const r of rows) {
    const v = parseFloat(r.total ?? "0") || 0;
    if (r.workout_type === "running") run += v;
    else if (r.workout_type === "walking") walk += v;
  }
  return { run, walk };
}

async function getGoalMiles(userId: string): Promise<number> {
  const rows = await db.query<{ goal_miles: string }>(
    `SELECT goal_miles::text AS goal_miles FROM users WHERE user_id = $1`,
    [userId],
  );
  return parseFloat(rows[0]?.goal_miles ?? "1.0") || 1.0;
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

function formatPaceMinutes(minutesPerMile: number): string {
  const m = Math.floor(minutesPerMile);
  const s = Math.round((minutesPerMile - m) * 60);
  const ss = s < 10 ? `0${s}` : `${s}`;
  return `${m}:${ss}`;
}
