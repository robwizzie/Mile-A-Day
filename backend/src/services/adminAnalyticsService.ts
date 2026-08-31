/**
 * Feature-usage analytics for the admin dashboard.
 *
 * Split out of adminService.ts, which already owns the headline counters,
 * the user directory, storage and post forensics. Everything here answers a
 * different question — "is a FEATURE being used, by how many people, and how
 * often" — over tables adminService never touches (competitions, streak
 * tokens, buddy walks, challenges, badges).
 *
 * Two ground rules the queries share with the rest of the app:
 *   - "Today" is the ET calendar day (TODAY_ET_DATE_SQL), never CURRENT_DATE:
 *     the DB clock is UTC and flips at 8pm ET, which would zero every daily
 *     counter every evening.
 *   - A mile only counts when `deleted_at IS NULL AND exclusion_reason IS
 *     NULL` — the same filter the streak/feed code uses.
 *
 * These read PRODUCTION tables, so nothing here fetches unbounded ROWS — the
 * lists are all LIMITed and the rest are aggregates that return one row per
 * bucket. Several of those aggregates do scan their whole table (a
 * COUNT(DISTINCT user) over posts or hype_log has no cheaper shape), which is
 * why every panel sits behind a short in-memory cache: the dashboard refetches
 * on each tab mount, and one admin reloading must not become load on the
 * app's own pool. If a table grows to where a single pass is too slow, the
 * answer is a rollup table, not a bigger cache.
 */

import { PostgresService } from "./DbService.js";
import { START_OF_TODAY_ET_SQL, TODAY_ET_DATE_SQL } from "./dailyResetTime.js";
import {
  DOUBLE_DOWN_TARGET_DAYS,
  STREAK_SAVE_TARGET_RUN_DAYS,
  STREAK_ASSIST_TARGET_DAYS,
  ENROLL_LOOKBACK_DAYS,
  METER_WINDOW_DAYS,
} from "./streakFeatureService.js";

const db = PostgresService.getInstance();

// A workout only counts toward miles/streaks when it is neither soft-deleted
// nor auto-excluded (vehicle speed, cross-app duplicate). Same rule as
// workoutService — kept as one fragment so the panels can't drift from it.
const COUNTING_WORKOUT = `w.deleted_at IS NULL AND w.exclusion_reason IS NULL`;

/**
 * A competition is LIVE when it hasn't been resolved and today sits inside
 * its window. `end_date` is nullable on purpose — first-to/duration-hours
 * competitions resolve on a target rather than a calendar day — so a NULL end
 * reads as "still running", exactly like getCompetitions' "go" status.
 */
const COMPETITION_LIVE = `NOT COALESCE(c.ended, FALSE)
  AND (c.start_date IS NULL OR c.start_date <= ${TODAY_ET_DATE_SQL})
  AND (c.end_date IS NULL OR c.end_date >= ${TODAY_ET_DATE_SQL})`;

/** Not started yet — the lobby ("get set") state. */
const COMPETITION_UPCOMING = `NOT COALESCE(c.ended, FALSE)
  AND c.start_date IS NOT NULL AND c.start_date > ${TODAY_ET_DATE_SQL}`;

// ─── Tiny TTL cache ─────────────────────────────────────────────────

/**
 * Wrap a loader in a short time-to-live cache. The dashboard refetches on
 * every tab mount and these are multi-CTE aggregates over live tables; a few
 * seconds of staleness is invisible on a metrics screen and keeps a reload
 * loop from becoming load on the app's own pool.
 */
const cacheResets: (() => void)[] = [];

/**
 * Drop every panel cache. Only for tests — scripts/admin-analytics-check.mjs
 * asserts against an empty database and then against a seeded one in the same
 * process, and would otherwise be served the empty answers it warmed.
 */
export function resetAnalyticsCaches(): void {
  for (const reset of cacheResets) reset();
}

function cached<T>(ttlMs: number, load: () => Promise<T>): () => Promise<T> {
  let hit: { at: number; data: T } | null = null;
  let inflight: Promise<T> | null = null;
  cacheResets.push(() => {
    hit = null;
  });
  return async () => {
    if (hit && Date.now() - hit.at < ttlMs) return hit.data;
    // Collapse concurrent misses onto one query rather than N.
    if (!inflight) {
      inflight = load()
        .then((data) => {
          hit = { at: Date.now(), data };
          return data;
        })
        .finally(() => {
          inflight = null;
        });
    }
    return inflight;
  };
}

// ─── Competitions ───────────────────────────────────────────────────

export interface CompetitionStats {
  summary: {
    total: number;
    live: number;
    upcoming: number;
    finished: number;
    created_7d: number;
    created_30d: number;
    team_competitions: number;
    players: number;
    total_users: number;
    invites_accepted: number;
    invites_pending: number;
    invites_declined: number;
    avg_roster: number;
  };
  by_type: {
    type: string;
    total: number;
    live: number;
    players: number;
    avg_roster: number;
  }[];
  by_week: { week: string; created: number; players: number }[];
  live: {
    id: string;
    competition_name: string | null;
    type: string;
    start_date: string | null;
    end_date: string | null;
    days_left: number | null;
    owner_username: string | null;
    players: number;
    pending: number;
    team_play: boolean;
  }[];
  top_organizers: {
    user_id: string;
    username: string | null;
    created: number;
  }[];
  top_winners: { user_id: string; username: string | null; wins: number }[];
}

async function loadCompetitionStats(): Promise<CompetitionStats> {
  const [summary, byType, byWeek, live, organizers, winners] =
    await Promise.all([
      db.query<CompetitionStats["summary"]>(`
      SELECT
        (SELECT COUNT(*) FROM competitions c)::int AS total,
        (SELECT COUNT(*) FROM competitions c WHERE ${COMPETITION_LIVE})::int AS live,
        (SELECT COUNT(*) FROM competitions c WHERE ${COMPETITION_UPCOMING})::int AS upcoming,
        (SELECT COUNT(*) FROM competitions c
           WHERE COALESCE(c.ended, FALSE)
             OR (c.end_date IS NOT NULL AND c.end_date < ${TODAY_ET_DATE_SQL}))::int AS finished,
        (SELECT COUNT(*) FROM competitions c
           WHERE c.created_at >= NOW() - INTERVAL '7 days')::int AS created_7d,
        (SELECT COUNT(*) FROM competitions c
           WHERE c.created_at >= NOW() - INTERVAL '30 days')::int AS created_30d,
        (SELECT COUNT(*) FROM competitions c WHERE c.teams IS NOT NULL)::int AS team_competitions,
        -- "Players" is anyone who ever ACCEPTED an invite: the honest
        -- denominator for "how many of our users compete at all".
        (SELECT COUNT(DISTINCT cu.user_id) FROM competition_users cu
           WHERE cu.invite_status = 'accepted')::int AS players,
        (SELECT COUNT(*) FROM users)::int AS total_users,
        (SELECT COUNT(*) FROM competition_users WHERE invite_status = 'accepted')::int AS invites_accepted,
        (SELECT COUNT(*) FROM competition_users WHERE invite_status = 'pending')::int AS invites_pending,
        (SELECT COUNT(*) FROM competition_users WHERE invite_status = 'declined')::int AS invites_declined,
        (SELECT COALESCE(AVG(n), 0) FROM (
           SELECT COUNT(*)::float AS n FROM competition_users
           WHERE invite_status = 'accepted' GROUP BY competition_id) r)::float AS avg_roster
    `),
      db.query<CompetitionStats["by_type"][number]>(`
      SELECT c.type,
             COUNT(*)::int AS total,
             COUNT(*) FILTER (WHERE ${COMPETITION_LIVE})::int AS live,
             COALESCE(SUM(r.roster), 0)::int AS players,
             COALESCE(AVG(r.roster), 0)::float AS avg_roster
      FROM competitions c
      LEFT JOIN LATERAL (
        SELECT COUNT(*)::int AS roster FROM competition_users cu
        WHERE cu.competition_id = c.id AND cu.invite_status = 'accepted'
      ) r ON TRUE
      GROUP BY c.type
      ORDER BY total DESC
    `),
      // Created-per-week for the last 12 weeks, zero-filled so a quiet week
      // reads as a gap rather than vanishing from the axis.
      db.query<CompetitionStats["by_week"][number]>(`
      SELECT to_char(wk, 'YYYY-MM-DD') AS week,
             COUNT(c.id)::int AS created,
             COALESCE(SUM(r.roster), 0)::int AS players
      FROM generate_series(
             date_trunc('week', ${TODAY_ET_DATE_SQL}::timestamp) - INTERVAL '11 weeks',
             date_trunc('week', ${TODAY_ET_DATE_SQL}::timestamp),
             INTERVAL '1 week') wk
      LEFT JOIN competitions c
        ON date_trunc('week', (c.created_at AT TIME ZONE 'America/New_York')) = wk
      LEFT JOIN LATERAL (
        SELECT COUNT(*)::int AS roster FROM competition_users cu
        WHERE cu.competition_id = c.id AND cu.invite_status = 'accepted'
      ) r ON TRUE
      GROUP BY wk
      ORDER BY wk
    `),
      db.query<CompetitionStats["live"][number]>(`
      SELECT c.id, c.competition_name, c.type,
             c.start_date::text AS start_date, c.end_date::text AS end_date,
             CASE WHEN c.end_date IS NULL THEN NULL
                  ELSE (c.end_date - ${TODAY_ET_DATE_SQL})::int END AS days_left,
             u.username AS owner_username,
             (SELECT COUNT(*) FROM competition_users cu
                WHERE cu.competition_id = c.id AND cu.invite_status = 'accepted')::int AS players,
             (SELECT COUNT(*) FROM competition_users cu
                WHERE cu.competition_id = c.id AND cu.invite_status = 'pending')::int AS pending,
             (c.teams IS NOT NULL) AS team_play
      FROM competitions c
      LEFT JOIN users u ON u.user_id = c.owner
      WHERE ${COMPETITION_LIVE} OR ${COMPETITION_UPCOMING}
      ORDER BY (${COMPETITION_LIVE}) DESC, c.end_date ASC NULLS LAST, c.start_date DESC
      LIMIT 30
    `),
      db.query<CompetitionStats["top_organizers"][number]>(`
      SELECT c.owner AS user_id, u.username, COUNT(*)::int AS created
      FROM competitions c
      JOIN users u ON u.user_id = c.owner
      GROUP BY 1, 2
      ORDER BY created DESC, u.username ASC
      LIMIT 8
    `),
      db.query<CompetitionStats["top_winners"][number]>(`
      SELECT c.winner AS user_id, u.username, COUNT(*)::int AS wins
      FROM competitions c
      JOIN users u ON u.user_id = c.winner
      WHERE c.winner IS NOT NULL
      GROUP BY 1, 2
      ORDER BY wins DESC, u.username ASC
      LIMIT 8
    `),
    ]);

  return {
    summary: summary[0],
    by_type: byType,
    by_week: byWeek,
    live,
    top_organizers: organizers,
    top_winners: winners,
  };
}

export const getCompetitionStats = cached(20_000, loadCompetitionStats);

// ─── Streak tokens ──────────────────────────────────────────────────

export interface StreakTokenStats {
  enrollment: {
    total_users: number;
    enrolled: number;
    ever_double_down: number;
    ever_streak_save: number;
    ever_assist: number;
  };
  /** Coverage rows are the ledger of tokens actually SPENT. */
  spend_by_kind: {
    kind: string;
    total: number;
    last_30d: number;
    last_7d: number;
    users: number;
  }[];
  spend_by_day: {
    date: string;
    streak_save: number;
    double_down: number;
    streak_assist: number;
  }[];
  /** Enrolled users whose meter is full right now (a token in hand). */
  held: {
    enrolled: number;
    double_down: number;
    streak_save: number;
    streak_assist: number;
    targets: {
      double_down: number;
      streak_save: number;
      streak_assist: number;
    };
  };
  assist_offers: {
    status: string;
    initiator: string;
    count: number;
  }[];
  assist_funnel: {
    offered: number;
    accepted: number;
    declined: number;
    expired: number;
    pending: number;
  };
  pauses: {
    total: number;
    active: number;
    expired: number;
    avg_days: number;
  };
  breaks: {
    total: number;
    last_30d: number;
    saved_30d: number;
    avg_prior_streak: number;
  };
  top_donors: { user_id: string; username: string | null; assists: number }[];
}

async function loadStreakTokenStats(): Promise<StreakTokenStats> {
  const [
    enrollment,
    spendByKind,
    spendByDay,
    held,
    offers,
    funnel,
    pauses,
    breaks,
    donors,
  ] = await Promise.all([
    db.query<StreakTokenStats["enrollment"]>(`
      SELECT COUNT(*)::int AS total_users,
             COUNT(*) FILTER (WHERE streak_features_at IS NOT NULL)::int AS enrolled,
             COUNT(*) FILTER (WHERE double_down_last_used IS NOT NULL)::int AS ever_double_down,
             COUNT(*) FILTER (WHERE streak_save_last_used IS NOT NULL)::int AS ever_streak_save,
             COUNT(*) FILTER (WHERE streak_assist_last_used IS NOT NULL)::int AS ever_assist
      FROM users
    `),
    db.query<StreakTokenStats["spend_by_kind"][number]>(`
      SELECT kind,
             COUNT(*)::int AS total,
             COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '30 days')::int AS last_30d,
             COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '7 days')::int AS last_7d,
             COUNT(DISTINCT user_id)::int AS users
      FROM streak_coverage
      GROUP BY kind
      ORDER BY total DESC
    `),
    // Keyed on local_date — the DAY that was rescued, which is the day an
    // admin is looking for when a user asks "what happened to my streak".
    db.query<StreakTokenStats["spend_by_day"][number]>(`
      SELECT d::date::text AS date,
             COUNT(*) FILTER (WHERE sc.kind = 'streak_save')::int AS streak_save,
             COUNT(*) FILTER (WHERE sc.kind = 'double_down_recover')::int AS double_down,
             COUNT(*) FILTER (WHERE sc.kind = 'streak_assist')::int AS streak_assist
      FROM generate_series(${TODAY_ET_DATE_SQL} - 29, ${TODAY_ET_DATE_SQL}, INTERVAL '1 day') d
      LEFT JOIN streak_coverage sc ON sc.local_date = d::date
      GROUP BY d
      ORDER BY d
    `),
    // Mirrors streakFeatureService.getMeters set-wise: the meter counts
    // qualifying days since GREATEST(last use, enrollment lookback, hard
    // window) — GREATEST ignores NULLs, so a never-spent token measures from
    // the floor. The one deliberate difference is "today": the real meter
    // uses each user's own local day and this uses ET for everyone, which can
    // move a borderline user by a day. The constants are imported rather than
    // restated so the panel can't drift from the feature.
    db.query<{
      enrolled: number;
      double_down: number;
      streak_save: number;
      streak_assist: number;
    }>(
      `
      WITH enrolled AS (
        SELECT u.user_id,
               GREATEST(
                 (u.streak_features_at AT TIME ZONE 'UTC')::date - $4::int,
                 ${TODAY_ET_DATE_SQL} - $5::int
               ) AS floor_date,
               u.double_down_last_used, u.streak_save_last_used, u.streak_assist_last_used
        FROM users u
        WHERE u.streak_features_at IS NOT NULL
      )
      SELECT COUNT(*)::int AS enrolled,
             COUNT(*) FILTER (WHERE dd.n >= $1::int)::int AS double_down,
             COUNT(*) FILTER (WHERE sv.n >= $2::int)::int AS streak_save,
             COUNT(*) FILTER (WHERE e.streak_assist_last_used IS NULL
               OR (${TODAY_ET_DATE_SQL} - e.streak_assist_last_used) >= $3::int)::int AS streak_assist
      FROM enrolled e
      LEFT JOIN LATERAL (
        SELECT COUNT(*)::int AS n FROM (
          SELECT w.local_date FROM workouts w
          WHERE w.user_id = e.user_id AND ${COUNTING_WORKOUT}
            AND w.local_date > GREATEST(e.floor_date, e.double_down_last_used)
            AND w.local_date <= ${TODAY_ET_DATE_SQL}
          GROUP BY w.local_date HAVING SUM(w.distance) >= 0.95
        ) x
      ) dd ON TRUE
      LEFT JOIN LATERAL (
        SELECT COUNT(*)::int AS n FROM (
          SELECT w.local_date FROM workouts w
          WHERE w.user_id = e.user_id AND ${COUNTING_WORKOUT}
            AND w.workout_type = 'running'
            AND w.local_date > GREATEST(e.floor_date, e.streak_save_last_used)
            AND w.local_date <= ${TODAY_ET_DATE_SQL}
          GROUP BY w.local_date HAVING SUM(w.distance) >= 0.95
        ) x
      ) sv ON TRUE
    `,
      [
        DOUBLE_DOWN_TARGET_DAYS,
        STREAK_SAVE_TARGET_RUN_DAYS,
        STREAK_ASSIST_TARGET_DAYS,
        ENROLL_LOOKBACK_DAYS,
        METER_WINDOW_DAYS,
      ],
    ),
    db.query<StreakTokenStats["assist_offers"][number]>(`
      SELECT status, initiator, COUNT(*)::int AS count
      FROM streak_assist_offers
      GROUP BY 1, 2
      ORDER BY count DESC
    `),
    db.query<StreakTokenStats["assist_funnel"]>(`
      SELECT COUNT(*)::int AS offered,
             COUNT(*) FILTER (WHERE status = 'accepted')::int AS accepted,
             COUNT(*) FILTER (WHERE status = 'declined')::int AS declined,
             COUNT(*) FILTER (WHERE status = 'expired')::int AS expired,
             COUNT(*) FILTER (WHERE status = 'pending')::int AS pending
      FROM streak_assist_offers
    `),
    db.query<StreakTokenStats["pauses"]>(`
      SELECT COUNT(*)::int AS total,
             COUNT(*) FILTER (WHERE resumed_on IS NULL AND expired_at IS NULL)::int AS active,
             COUNT(*) FILTER (WHERE expired_at IS NOT NULL)::int AS expired,
             COALESCE(AVG(COALESCE(resumed_on, ${TODAY_ET_DATE_SQL}) - started_on), 0)::float AS avg_days
      FROM streak_pauses
    `),
    db.query<StreakTokenStats["breaks"]>(`
      SELECT COUNT(*)::int AS total,
             COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '30 days')::int AS last_30d,
             (SELECT COUNT(*) FROM streak_coverage
                WHERE created_at >= NOW() - INTERVAL '30 days')::int AS saved_30d,
             COALESCE(AVG(prior_streak), 0)::float AS avg_prior_streak
      FROM streak_events
      WHERE kind = 'break'
    `),
    // Who gives their miles away. `source_user` is plain text (no FK) so a
    // deleted donor still shows, just without a username.
    db.query<StreakTokenStats["top_donors"][number]>(`
      SELECT sc.source_user AS user_id, u.username, COUNT(*)::int AS assists
      FROM streak_coverage sc
      LEFT JOIN users u ON u.user_id = sc.source_user
      WHERE sc.kind = 'streak_assist' AND sc.source_user IS NOT NULL
      GROUP BY 1, 2
      ORDER BY assists DESC
      LIMIT 8
    `),
  ]);

  return {
    enrollment: enrollment[0],
    spend_by_kind: spendByKind,
    spend_by_day: spendByDay,
    held: {
      ...held[0],
      targets: {
        double_down: DOUBLE_DOWN_TARGET_DAYS,
        streak_save: STREAK_SAVE_TARGET_RUN_DAYS,
        streak_assist: STREAK_ASSIST_TARGET_DAYS,
      },
    },
    assist_offers: offers,
    assist_funnel: funnel[0],
    pauses: pauses[0],
    breaks: breaks[0],
    top_donors: donors,
  };
}

export const getStreakTokenStats = cached(30_000, loadStreakTokenStats);

// ─── Feature adoption ───────────────────────────────────────────────

export interface FeatureAdoption {
  total_users: number;
  active_30d: number;
  features: {
    key: string;
    label: string;
    group: string;
    users_ever: number;
    users_30d: number;
    events_ever: number;
    events_30d: number;
  }[];
}

/**
 * One row per feature: how many DISTINCT people have ever touched it, how many
 * touched it in the last 30 days, and the raw event counts behind both.
 *
 * Each entry names the table, the column identifying the actor, the timestamp
 * that dates an event, and any predicate that makes a row count as real usage.
 * Keeping them as data rather than 14 hand-written queries is what makes the
 * numbers comparable — every feature is measured the same way.
 */
const ADOPTION_SOURCES: {
  key: string;
  label: string;
  group: string;
  from: string;
  actor: string;
  at: string;
  where?: string;
}[] = [
  {
    key: "photo_post",
    label: "Posted a photo",
    group: "Social",
    from: "posts p",
    actor: "p.user_id",
    at: "p.created_at",
    where: "NOT p.is_auto AND p.deleted_at IS NULL",
  },
  {
    key: "story",
    label: "Shared a story",
    group: "Social",
    from: "posts p",
    actor: "p.user_id",
    at: "p.created_at",
    where: "p.share_to_story AND p.deleted_at IS NULL",
  },
  {
    key: "collab",
    label: "Collab post (tagged a friend)",
    group: "Social",
    from: "posts p",
    actor: "p.user_id",
    at: "p.created_at",
    where: "p.coauthor_user_id IS NOT NULL AND p.deleted_at IS NULL",
  },
  {
    key: "comment",
    label: "Commented",
    group: "Social",
    from: "post_comments pc",
    actor: "pc.user_id",
    at: "pc.created_at",
    where: "pc.deleted_at IS NULL",
  },
  {
    key: "hype",
    label: "Sent a hype",
    group: "Social",
    from: "hype_log h",
    actor: "h.sender_id",
    at: "h.created_at",
  },
  {
    key: "nudge",
    label: "Nudged a friend",
    group: "Social",
    from: "friend_nudge_log fn",
    actor: "fn.sender_id",
    at: "fn.created_at",
  },
  {
    key: "highlight",
    label: "Made a story highlight",
    group: "Social",
    from: "post_highlights ph",
    actor: "ph.user_id",
    at: "ph.created_at",
  },
  {
    key: "friend",
    label: "Added a friend",
    group: "Social",
    from: "friendships f",
    actor: "f.user_id",
    at: "f.created_at",
    where: "f.status = 'accepted'",
  },
  {
    key: "competition",
    label: "Joined a competition",
    group: "Compete",
    // competition_users has no timestamp of its own, so an invite is dated by
    // the competition it belongs to — which is the creation date, close enough
    // for a 30-day adoption window and the only date that exists.
    from: "competition_users cu JOIN competitions c ON c.id = cu.competition_id",
    actor: "cu.user_id",
    at: "c.created_at",
    where: "cu.invite_status = 'accepted'",
  },
  {
    key: "buddy",
    label: "Walked with a buddy",
    group: "Compete",
    from: "buddy_session_participants bp",
    actor: "bp.user_id",
    at: "bp.joined_at",
    where: "bp.status IN ('active', 'finished')",
  },
  {
    key: "daily_challenge",
    label: "Completed a daily challenge",
    group: "Compete",
    from: "user_challenge_completions ucc",
    actor: "ucc.user_id",
    at: "ucc.completed_at",
  },
  {
    key: "weekly_challenge",
    label: "Completed a weekly challenge",
    group: "Compete",
    from: "user_weekly_challenge_completions uwc",
    actor: "uwc.user_id",
    at: "uwc.completed_at",
  },
  {
    key: "badge",
    label: "Earned a badge",
    group: "Compete",
    from: "user_badges ub",
    actor: "ub.user_id",
    at: "ub.earned_at",
  },
  {
    key: "streak_token",
    label: "Spent a streak token",
    group: "Streak",
    from: "streak_coverage sc",
    actor: "sc.user_id",
    at: "sc.created_at",
  },
  {
    key: "injury_pause",
    label: "Paused for injury",
    group: "Streak",
    from: "streak_pauses sp",
    actor: "sp.user_id",
    at: "sp.created_at",
  },
  {
    key: "ghost_race",
    label: "Raced a friend's ghost",
    group: "Streak",
    from: "workouts w",
    actor: "w.user_id",
    at: "w.created_at",
    where: `w.ghost_friend_user_id IS NOT NULL AND ${COUNTING_WORKOUT}`,
  },
  {
    key: "manual_workout",
    label: "Added or edited a workout by hand",
    group: "Streak",
    from: "workouts w",
    actor: "w.user_id",
    at: "w.created_at",
    where: "w.source IN ('manual', 'edited')",
  },
];

async function loadFeatureAdoption(): Promise<FeatureAdoption> {
  // One statement, one arm per feature. Every arm is code-controlled text from
  // the table above — no request input reaches the SQL.
  const arms = ADOPTION_SOURCES.map(
    (s) => `SELECT '${s.key}' AS key,
              COUNT(DISTINCT ${s.actor})::int AS users_ever,
              COUNT(DISTINCT ${s.actor}) FILTER (
                WHERE ${s.at} >= NOW() - INTERVAL '30 days')::int AS users_30d,
              COUNT(*)::int AS events_ever,
              COUNT(*) FILTER (WHERE ${s.at} >= NOW() - INTERVAL '30 days')::int AS events_30d
            FROM ${s.from}
            ${s.where ? `WHERE ${s.where}` : ""}`,
  ).join(" UNION ALL ");

  const [rows, [totals]] = await Promise.all([
    db.query<{
      key: string;
      users_ever: number;
      users_30d: number;
      events_ever: number;
      events_30d: number;
    }>(arms),
    db.query<{ total_users: number; active_30d: number }>(`
      SELECT (SELECT COUNT(*) FROM users)::int AS total_users,
             (SELECT COUNT(DISTINCT w.user_id) FROM workouts w
                WHERE ${COUNTING_WORKOUT}
                  AND w.local_date >= ${TODAY_ET_DATE_SQL} - 29)::int AS active_30d
    `),
  ]);

  const byKey = new Map(rows.map((r) => [r.key, r]));
  return {
    total_users: totals.total_users,
    active_30d: totals.active_30d,
    features: ADOPTION_SOURCES.map((s) => {
      const r = byKey.get(s.key);
      return {
        key: s.key,
        label: s.label,
        group: s.group,
        users_ever: r?.users_ever ?? 0,
        users_30d: r?.users_30d ?? 0,
        events_ever: r?.events_ever ?? 0,
        events_30d: r?.events_30d ?? 0,
      };
    }),
  };
}

export const getFeatureAdoption = cached(30_000, loadFeatureAdoption);

// ─── Community health (friends, buddy walks, challenges, badges) ─────

export interface CommunityStats {
  friends: {
    /** Accepted friendships are stored BIDIRECTIONALLY — pairs, not rows. */
    pairs: number;
    pending: number;
    connected_users: number;
    total_users: number;
    avg_friends: number;
    solo_users: number;
  };
  buddy: {
    sessions: number;
    sessions_30d: number;
    live_now: number;
    completed: number;
    participants: number;
    avg_crew: number;
    by_mode: { mode: string; count: number }[];
    by_origin: { origin: string; count: number }[];
  };
  challenges: {
    served: number;
    completed: number;
    served_30d: number;
    completed_30d: number;
    by_challenge: {
      challenge_key: string;
      title: string | null;
      served: number;
      completed: number;
    }[];
  };
  badges: {
    earned: number;
    holders: number;
    top: { badge_id: string; name: string; rarity: string; earned: number }[];
  };
  live_now: { tracking: number; buddy_sessions: number };
  top_photographers: {
    user_id: string;
    username: string | null;
    photos: number;
    last_photo_at: string | null;
  }[];
}

async function loadCommunityStats(): Promise<CommunityStats> {
  const [
    friends,
    buddy,
    byMode,
    byOrigin,
    challenges,
    byChallenge,
    badges,
    topBadges,
    liveNow,
    photographers,
  ] = await Promise.all([
    db.query<CommunityStats["friends"]>(`
      SELECT
        (SELECT COUNT(*) FROM friendships WHERE status = 'accepted')::int / 2 AS pairs,
        (SELECT COUNT(*) FROM friendships WHERE status = 'pending')::int AS pending,
        (SELECT COUNT(DISTINCT user_id) FROM friendships WHERE status = 'accepted')::int AS connected_users,
        (SELECT COUNT(*) FROM users)::int AS total_users,
        (SELECT COALESCE(AVG(n), 0) FROM (
           SELECT COUNT(*)::float AS n FROM friendships
           WHERE status = 'accepted' GROUP BY user_id) f)::float AS avg_friends,
        ((SELECT COUNT(*) FROM users)
          - (SELECT COUNT(DISTINCT user_id) FROM friendships WHERE status = 'accepted'))::int AS solo_users
    `),
    db.query<Omit<CommunityStats["buddy"], "by_mode" | "by_origin">>(`
      SELECT
        (SELECT COUNT(*) FROM buddy_sessions)::int AS sessions,
        (SELECT COUNT(*) FROM buddy_sessions
           WHERE created_at >= NOW() - INTERVAL '30 days')::int AS sessions_30d,
        (SELECT COUNT(*) FROM buddy_sessions WHERE status = 'active')::int AS live_now,
        (SELECT COUNT(*) FROM buddy_sessions WHERE ended_at IS NOT NULL)::int AS completed,
        (SELECT COUNT(DISTINCT user_id) FROM buddy_session_participants
           WHERE status IN ('active', 'finished'))::int AS participants,
        (SELECT COALESCE(AVG(n), 0) FROM (
           SELECT COUNT(*)::float AS n FROM buddy_session_participants
           WHERE status IN ('active', 'finished') GROUP BY session_id) b)::float AS avg_crew
    `),
    db.query<{ mode: string; count: number }>(`
      SELECT mode, COUNT(*)::int AS count FROM buddy_sessions
      GROUP BY mode ORDER BY count DESC
    `),
    db.query<{ origin: string; count: number }>(`
      SELECT origin, COUNT(*)::int AS count FROM buddy_sessions
      GROUP BY origin ORDER BY count DESC
    `),
    db.query<Omit<CommunityStats["challenges"], "by_challenge">>(`
      SELECT
        (SELECT COUNT(*) FROM user_daily_challenges)::int AS served,
        (SELECT COUNT(*) FROM user_challenge_completions)::int AS completed,
        (SELECT COUNT(*) FROM user_daily_challenges
           WHERE local_date >= ${TODAY_ET_DATE_SQL} - 29)::int AS served_30d,
        (SELECT COUNT(*) FROM user_challenge_completions
           WHERE local_date >= ${TODAY_ET_DATE_SQL} - 29)::int AS completed_30d
    `),
    // Served vs completed per challenge — the completion RATE is what says
    // whether a challenge is fun or just impossible.
    db.query<CommunityStats["challenges"]["by_challenge"][number]>(`
      SELECT s.challenge_key, dc.title,
             s.served::int AS served,
             COALESCE(c.completed, 0)::int AS completed
      FROM (SELECT challenge_key, COUNT(*) AS served
              FROM user_daily_challenges GROUP BY challenge_key) s
      LEFT JOIN (SELECT challenge_key, COUNT(*) AS completed
              FROM user_challenge_completions GROUP BY challenge_key) c
        ON c.challenge_key = s.challenge_key
      LEFT JOIN daily_challenges dc ON dc.challenge_key = s.challenge_key
      ORDER BY s.served DESC
      LIMIT 20
    `),
    db.query<{ earned: number; holders: number }>(`
      SELECT COUNT(*)::int AS earned, COUNT(DISTINCT user_id)::int AS holders
      FROM user_badges
    `),
    db.query<CommunityStats["badges"]["top"][number]>(`
      SELECT b.badge_id, b.name, b.rarity, COUNT(ub.id)::int AS earned
      FROM badges b
      JOIN user_badges ub ON ub.badge_id = b.badge_id
      GROUP BY b.badge_id, b.name, b.rarity
      ORDER BY earned DESC
      LIMIT 10
    `),
    db.query<CommunityStats["live_now"]>(`
      SELECT
        (SELECT COUNT(*) FROM live_tracking_sessions
           WHERE last_seen_at >= NOW() - INTERVAL '5 minutes')::int AS tracking,
        (SELECT COUNT(*) FROM buddy_sessions WHERE status = 'active')::int AS buddy_sessions
    `),
    // "How often is the social feature actually working" — who is putting
    // real photos on the feed, and when they last did.
    db.query<CommunityStats["top_photographers"][number]>(`
      SELECT p.user_id, u.username, COUNT(*)::int AS photos,
             MAX(p.created_at) AS last_photo_at
      FROM posts p
      LEFT JOIN users u ON u.user_id = p.user_id
      WHERE NOT p.is_auto AND p.deleted_at IS NULL
      GROUP BY p.user_id, u.username
      ORDER BY photos DESC
      LIMIT 10
    `),
  ]);

  return {
    friends: friends[0],
    buddy: { ...buddy[0], by_mode: byMode, by_origin: byOrigin },
    challenges: { ...challenges[0], by_challenge: byChallenge },
    badges: { ...badges[0], top: topBadges },
    live_now: liveNow[0],
    top_photographers: photographers,
  };
}

export const getCommunityStats = cached(20_000, loadCommunityStats);

// ─── Referral graph ─────────────────────────────────────────────────

export interface ReferralGraph {
  summary: {
    total_users: number;
    friend_referred: number;
    matched: number;
    unmatched: number;
    referrers: number;
  };
  referrers: {
    referrer_id: string | null;
    referrer_username: string | null;
    /** The name as typed, when it doesn't resolve to a real account. */
    typed_as: string;
    count: number;
    active: number;
    referred: {
      user_id: string;
      username: string | null;
      name: string | null;
      created_at: string;
      last_active: string | null;
      total_miles: number;
      current_streak: number;
    }[];
  }[];
}

/**
 * Who brought whom in.
 *
 * There is no referral-code system — attribution is the free-text name a new
 * user types when they pick "Friend" at onboarding (`users.referral_detail`).
 * So this RESOLVES that text against real usernames (trimmed, case-folded, a
 * leading "@" stripped) and reports the matched and unmatched halves
 * separately rather than pretending every typed name is an account.
 *
 * Each referred user carries their own activity, because the number that
 * matters isn't how many names a referrer collected — it's how many of them
 * are still running.
 */
async function loadReferralGraph(): Promise<ReferralGraph> {
  const rows = await db.query<{
    user_id: string;
    username: string | null;
    name: string | null;
    created_at: string;
    handle: string;
    referrer_id: string | null;
    referrer_username: string | null;
    last_active: string | null;
    total_miles: number;
    current_streak: number;
  }>(`
    WITH referred AS (
      SELECT u.user_id, u.username,
             NULLIF(TRIM(COALESCE(u.first_name, '') || ' ' || COALESCE(u.last_name, '')), '') AS name,
             u.created_at, u.current_streak,
             lower(regexp_replace(btrim(u.referral_detail), '^@', '')) AS handle
      FROM users u
      WHERE u.referral_source = 'friend'
        AND COALESCE(btrim(u.referral_detail), '') <> ''
    )
    SELECT r.user_id, r.username, r.name, r.created_at, r.handle, r.current_streak,
           ru.user_id AS referrer_id, ru.username AS referrer_username,
           w.last_active, COALESCE(w.total_miles, 0)::float AS total_miles
    FROM referred r
    LEFT JOIN users ru ON lower(ru.username) = r.handle
    LEFT JOIN LATERAL (
      SELECT MAX(w.local_date)::text AS last_active, SUM(w.distance) AS total_miles
      FROM workouts w
      WHERE w.user_id = r.user_id AND ${COUNTING_WORKOUT}
    ) w ON TRUE
    ORDER BY r.created_at DESC
    LIMIT 1000
  `);

  const [{ total_users }] = await db.query<{ total_users: number }>(
    `SELECT COUNT(*)::int AS total_users FROM users`,
  );

  // Group by the resolved account when there is one, and by the typed text
  // when there isn't — two people typing the same misspelling are one bucket.
  const groups = new Map<string, ReferralGraph["referrers"][number]>();
  const activeCutoff = new Date(Date.now() - 7 * 86_400_000)
    .toISOString()
    .slice(0, 10);

  for (const r of rows) {
    const key = r.referrer_id ?? `typed:${r.handle}`;
    let g = groups.get(key);
    if (!g) {
      g = {
        referrer_id: r.referrer_id,
        referrer_username: r.referrer_username,
        typed_as: r.handle,
        count: 0,
        active: 0,
        referred: [],
      };
      groups.set(key, g);
    }
    g.count += 1;
    if (r.last_active && r.last_active >= activeCutoff) g.active += 1;
    g.referred.push({
      user_id: r.user_id,
      username: r.username,
      name: r.name,
      created_at: r.created_at,
      last_active: r.last_active,
      total_miles: r.total_miles,
      current_streak: r.current_streak,
    });
  }

  const referrers = [...groups.values()].sort(
    (a, b) =>
      b.count - a.count ||
      (a.referrer_username ?? "").localeCompare(b.referrer_username ?? ""),
  );
  const matched = rows.filter((r) => r.referrer_id).length;

  return {
    summary: {
      total_users,
      friend_referred: rows.length,
      matched,
      unmatched: rows.length - matched,
      referrers: referrers.length,
    },
    referrers,
  };
}

export const getReferralGraph = cached(30_000, loadReferralGraph);

// ─── Retention cohorts ──────────────────────────────────────────────

export interface RetentionCohorts {
  max_week: number;
  cohorts: {
    cohort: string;
    size: number;
    weeks: { week: number; users: number; pct: number }[];
  }[];
}

/**
 * Weekly signup cohorts × week-N retention, where "retained" means the user
 * logged a COUNTING workout that week. Twelve cohorts is the bound; the
 * triangle narrows on its own as cohorts get younger.
 */
async function loadRetention(): Promise<RetentionCohorts> {
  const COHORT_WEEKS = 12;

  const [sizes, cells] = await Promise.all([
    db.query<{ cohort: string; size: number }>(`
      SELECT to_char(date_trunc('week', (u.created_at AT TIME ZONE 'America/New_York')), 'YYYY-MM-DD') AS cohort,
             COUNT(*)::int AS size
      FROM users u
      WHERE (u.created_at AT TIME ZONE 'America/New_York')::date
              >= date_trunc('week', ${TODAY_ET_DATE_SQL}::timestamp)::date - ${(COHORT_WEEKS - 1) * 7}
      GROUP BY 1
      ORDER BY 1
    `),
    db.query<{ cohort: string; week: number; users: number }>(`
      WITH cohort AS (
        SELECT u.user_id,
               date_trunc('week', (u.created_at AT TIME ZONE 'America/New_York'))::date AS cohort_week
        FROM users u
        WHERE (u.created_at AT TIME ZONE 'America/New_York')::date
                >= date_trunc('week', ${TODAY_ET_DATE_SQL}::timestamp)::date - ${(COHORT_WEEKS - 1) * 7}
      )
      SELECT to_char(c.cohort_week, 'YYYY-MM-DD') AS cohort,
             ((date_trunc('week', w.local_date::timestamp)::date - c.cohort_week) / 7)::int AS week,
             COUNT(DISTINCT c.user_id)::int AS users
      FROM cohort c
      JOIN workouts w ON w.user_id = c.user_id AND ${COUNTING_WORKOUT}
      WHERE w.local_date >= c.cohort_week
      GROUP BY 1, 2
      ORDER BY 1, 2
    `),
  ]);

  const byCohort = new Map<string, Map<number, number>>();
  let maxWeek = 0;
  for (const c of cells) {
    if (c.week < 0) continue;
    if (!byCohort.has(c.cohort)) byCohort.set(c.cohort, new Map());
    byCohort.get(c.cohort)!.set(c.week, c.users);
    if (c.week > maxWeek) maxWeek = c.week;
  }

  return {
    max_week: maxWeek,
    cohorts: sizes.map((s) => {
      const weeks = byCohort.get(s.cohort) ?? new Map<number, number>();
      return {
        cohort: s.cohort,
        size: s.size,
        weeks: Array.from({ length: maxWeek + 1 }, (_, w) => {
          const users = weeks.get(w) ?? 0;
          return {
            week: w,
            users,
            pct: s.size ? Math.round((users / s.size) * 1000) / 10 : 0,
          };
        }),
      };
    }),
  };
}

export const getRetentionCohorts = cached(60_000, loadRetention);

// ─── Activity rhythms ───────────────────────────────────────────────

export interface ActivityRhythms {
  /** Workout finishes bucketed by the RUNNER's local weekday + hour. */
  clock: { dow: number; hour: number; count: number }[];
  by_hour: { hour: number; count: number }[];
  by_weekday: { dow: number; count: number; miles: number }[];
  streak_buckets: { label: string; users: number }[];
  window_days: number;
}

/**
 * When people actually run, in their OWN wall clock.
 *
 * `device_end_date` is a timestamptz and `timezone_offset` is the device's
 * offset in MINUTES (same column localNowSql falls back to), so the local
 * finish time is the UTC instant plus that offset. Reading the raw
 * timestamptz instead would smear a global user base across the ET axis.
 */
async function loadActivityRhythms(): Promise<ActivityRhythms> {
  const WINDOW_DAYS = 90;
  const localTime = `((w.device_end_date AT TIME ZONE 'UTC') + (w.timezone_offset || ' minutes')::interval)`;
  const recent = `${COUNTING_WORKOUT} AND w.local_date >= ${TODAY_ET_DATE_SQL} - ${WINDOW_DAYS - 1}`;

  const [clock, byHour, byWeekday, buckets] = await Promise.all([
    db.query<{ dow: number; hour: number; count: number }>(`
      SELECT EXTRACT(DOW FROM ${localTime})::int AS dow,
             EXTRACT(HOUR FROM ${localTime})::int AS hour,
             COUNT(*)::int AS count
      FROM workouts w
      WHERE ${recent}
      GROUP BY 1, 2
    `),
    db.query<{ hour: number; count: number }>(`
      SELECT EXTRACT(HOUR FROM ${localTime})::int AS hour, COUNT(*)::int AS count
      FROM workouts w
      WHERE ${recent}
      GROUP BY 1 ORDER BY 1
    `),
    db.query<{ dow: number; count: number; miles: number }>(`
      SELECT EXTRACT(DOW FROM ${localTime})::int AS dow,
             COUNT(*)::int AS count,
             COALESCE(SUM(w.distance), 0)::float AS miles
      FROM workouts w
      WHERE ${recent}
      GROUP BY 1 ORDER BY 1
    `),
    // Streak distribution: the shape of this histogram is the retention story
    // in one picture — a fat 1-6 bar and a thin 30+ tail means people start
    // streaks and lose them.
    db.query<{ label: string; users: number }>(`
      SELECT bucket AS label, COUNT(*)::int AS users
      FROM (
        SELECT CASE
                 WHEN current_streak = 0 THEN '0'
                 WHEN current_streak BETWEEN 1 AND 6 THEN '1–6'
                 WHEN current_streak BETWEEN 7 AND 29 THEN '7–29'
                 WHEN current_streak BETWEEN 30 AND 99 THEN '30–99'
                 ELSE '100+'
               END AS bucket
        FROM users
      ) b
      GROUP BY bucket
    `),
  ]);

  // Fixed order so the chart never reshuffles as buckets empty out.
  const ORDER = ["0", "1–6", "7–29", "30–99", "100+"];
  const bucketMap = new Map(buckets.map((b) => [b.label, b.users]));

  return {
    clock,
    by_hour: byHour,
    by_weekday: byWeekday,
    streak_buckets: ORDER.map((label) => ({
      label,
      users: bucketMap.get(label) ?? 0,
    })),
    window_days: WINDOW_DAYS,
  };
}

export const getActivityRhythms = cached(60_000, loadActivityRhythms);

// ─── Today's pulse ──────────────────────────────────────────────────

export interface PulseStats {
  posts_today: number;
  photos_today: number;
  comments_today: number;
  competitions_live: number;
  buddy_sessions_today: number;
  tokens_spent_today: number;
  challenges_completed_today: number;
  badges_today: number;
  friends_today: number;
  tracking_now: number;
}

/** A single row of "what's happening right now", for the overview strip. */
export async function getPulse(): Promise<PulseStats> {
  const [row] = await db.query<PulseStats>(`
    SELECT
      (SELECT COUNT(*) FROM posts
         WHERE created_at >= ${START_OF_TODAY_ET_SQL} AND deleted_at IS NULL)::int AS posts_today,
      (SELECT COUNT(*) FROM posts
         WHERE created_at >= ${START_OF_TODAY_ET_SQL} AND deleted_at IS NULL AND NOT is_auto)::int AS photos_today,
      (SELECT COUNT(*) FROM post_comments
         WHERE created_at >= ${START_OF_TODAY_ET_SQL} AND deleted_at IS NULL)::int AS comments_today,
      (SELECT COUNT(*) FROM competitions c WHERE ${COMPETITION_LIVE})::int AS competitions_live,
      (SELECT COUNT(*) FROM buddy_sessions
         WHERE created_at >= ${START_OF_TODAY_ET_SQL})::int AS buddy_sessions_today,
      (SELECT COUNT(*) FROM streak_coverage
         WHERE created_at >= ${START_OF_TODAY_ET_SQL})::int AS tokens_spent_today,
      (SELECT COUNT(*) FROM user_challenge_completions
         WHERE completed_at >= ${START_OF_TODAY_ET_SQL})::int AS challenges_completed_today,
      (SELECT COUNT(*) FROM user_badges
         WHERE earned_at >= ${START_OF_TODAY_ET_SQL})::int AS badges_today,
      (SELECT COUNT(*) FROM friendships
         WHERE status = 'accepted' AND created_at >= ${START_OF_TODAY_ET_SQL})::int / 2 AS friends_today,
      (SELECT COUNT(*) FROM live_tracking_sessions
         WHERE last_seen_at >= NOW() - INTERVAL '5 minutes')::int AS tracking_now
  `);
  return row;
}
