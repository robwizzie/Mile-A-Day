import { randomUUID } from "node:crypto";
import { BadRequestError } from "../errors/Errors.js";
import {
  Competition,
  CompetitionActivity,
  CompetitionOptions,
  CompetitionRecordByType,
  CompetitionRecordResponse,
  CompetitionRival,
  CompetitionType,
  CompetitionUser,
} from "../types/competitions.js";
import { PostgresService } from "./DbService.js";
import {
  getQuantityDateRangeBatch,
  getActivityBreakdownBatch,
  getUsersWithManualWorkouts,
} from "./workoutService.js";
import { getStepsDateRangeBatch } from "./dailyStepsService.js";
import { sendOrQueueCompetitionNotification } from "./pushNotificationService.js";
import { evaluateSocialBadgesForUser } from "./badgeService.js";

const WORKOUT_TYPE_MAP: Record<string, string> = {
  run: "running",
  walk: "walking",
  running: "running",
  walking: "walking",
};

const db = PostgresService.getInstance();

const ET_DATE_FORMATTER = new Intl.DateTimeFormat("en-CA", {
  timeZone: "America/New_York",
});

/**
 * Maximum length, in characters, of a user-supplied competition name.
 * Keep in sync with CompetitionLimits.nameMaxLength in
 * app/Mile A Day/Models/CompetitionLimits.swift
 */
export const COMPETITION_NAME_MAX_LENGTH = 50;

function validateCompetitionName(name: unknown): string {
  if (typeof name !== "string") {
    throw new BadRequestError("competition_name must be a string");
  }
  const trimmed = name.trim();
  if (trimmed.length === 0) {
    throw new BadRequestError("competition_name cannot be empty");
  }
  if (trimmed.length > COMPETITION_NAME_MAX_LENGTH) {
    throw new BadRequestError(
      `competition_name cannot exceed ${COMPETITION_NAME_MAX_LENGTH} characters`,
    );
  }
  return trimmed;
}

export function getTodayET(): string {
  return ET_DATE_FORMATTER.format(new Date());
}

function etDateToUtcMs(dateStr: string): number {
  const [y, m, d] = dateStr.split("-").map(Number);
  const utcGuess = Date.UTC(y, m - 1, d);
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/New_York",
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).formatToParts(new Date(utcGuess));
  const get = (type: string) =>
    parseInt(parts.find((p) => p.type === type)!.value, 10);
  const etAsUtc = Date.UTC(
    get("year"),
    get("month") - 1,
    get("day"),
    get("hour"),
    get("minute"),
    get("second"),
  );
  const offsetMs = etAsUtc - utcGuess;
  return utcGuess - offsetMs;
}

interface CreateCompetitionParams {
  competition_name: string;
  start_date?: string;
  end_date?: string;
  type: CompetitionType;
  workouts?: CompetitionActivity[];
  options: CompetitionOptions;
  owner: string;
}

export async function createCompetition(params: CreateCompetitionParams) {
  checkKeys(params);

  const {
    competition_name,
    start_date,
    end_date,
    workouts = ["run", "walk"],
    type,
    options,
    owner,
  } = params;
  const validatedName = validateCompetitionName(competition_name);

  const [competition] = await db.query(
    `INSERT INTO competitions (
            competition_name, start_date, end_date,
            workouts, type, options, owner
        ) VALUES (
			$1, $2, $3, $4, $5, $6, $7
		) RETURNING *;`,
    [
      validatedName,
      start_date || null,
      end_date || null,
      JSON.stringify(workouts),
      type,
      JSON.stringify(options),
      owner,
    ],
  );

  await db.query(
    `INSERT INTO competition_users (
            competition_id, user_id, progress, invite_status
        ) VALUES (
            $1, $2, '{}', 'accepted'
		)`,
    [competition.id, owner],
  );

  // Owner started AND entered a competition — re-evaluate those badges.
  if (owner) evaluateSocialBadgesForUser(owner).catch(() => {});

  return competition.id;
}

function checkKeys(params: CreateCompetitionParams) {
  const { end_date, workouts = ["run", "walk"], type, options, owner } = params;

  const requiredKeys = [];
  const optionKeys = Object.keys(options);
  const missingKeys: string[] = [];

  if (workouts === undefined || workouts.length === 0) {
    missingKeys.push("workouts");
  }

  if (!owner) {
    missingKeys.push("owner");
  }

  if (type === "streaks") {
    requiredKeys.push("goal", "unit", "interval");

    if (
      end_date === undefined &&
      options.duration_hours === undefined &&
      options.lives === undefined &&
      options.first_to === undefined
    ) {
      missingKeys.push("(lives, end_date, or duration_hours)");
    }
  } else if (type === "apex") {
    requiredKeys.push("unit");

    if (end_date === undefined && options.duration_hours === undefined) {
      missingKeys.push("(end_date or duration_hours)");
    }
  } else if (type === "clash") {
    requiredKeys.push("unit", "interval");

    if (
      end_date === undefined &&
      options.first_to === undefined &&
      options.duration_hours === undefined
    ) {
      missingKeys.push("(first_to, end_date, or duration_hours)");
    }
  } else if (type === "targets") {
    requiredKeys.push("goal", "unit", "interval");

    if (
      end_date === undefined &&
      options.duration_hours === undefined &&
      options.first_to === undefined
    ) {
      missingKeys.push("(first_to, end_date, or duration_hours)");
    }
  } else if (type === "race") {
    requiredKeys.push("goal", "unit");
  }

  requiredKeys.forEach((key) => {
    if (!optionKeys.includes(key)) {
      missingKeys.push(key);
    }
  });

  if (missingKeys.length) {
    throw new BadRequestError(
      `Missing required key(s): ${missingKeys.join(", ")}`,
    );
  }
}

// User-enriched query fragment for competition_users JOIN
const USERS_AGG_SQL = `
	COALESCE(
		jsonb_agg(
			jsonb_build_object(
				'competition_id', cu.competition_id,
				'user_id', cu.user_id,
				'invite_status', cu.invite_status,
				'team_id', cu.team_id,
				'progress', cu.progress,
				'username', u.username,
				'profile_image_url', u.profile_image_url
			)
		) FILTER (WHERE cu.competition_id IS NOT NULL),
		'[]'::jsonb
	) as users`;

export async function getCompetition(
  competitionId: string,
  {
    includeActivityBreakdown = false,
  }: { includeActivityBreakdown?: boolean } = {},
): Promise<Competition> {
  const competition = (
    await db.query(
      `SELECT
				c.*,
				${USERS_AGG_SQL}
			FROM competitions c
			LEFT JOIN competition_users cu ON cu.competition_id = c.id
			LEFT JOIN users u ON u.user_id = cu.user_id
			WHERE c.id = $1
			GROUP BY c.id;`,
      [competitionId],
    )
  )[0];

  if (!competition) {
    return competition;
  }

  // Calculate scores for started competitions (start_date on or before today in ET)
  if (competition.start_date && competition.start_date <= getTodayET()) {
    // Per-day walk/run breakdown (distance + workout counts) for the detail
    // view's stats panel and calendar — opt-in because getCompetition is also
    // on hot paths (nudges, flexes, cron resolution) that never read it.
    // Steps comps don't read workouts, so they never get one.
    const withBreakdown =
      includeActivityBreakdown && competition.options?.unit !== "steps";
    const acceptedIds = competition.users
      .filter((u: CompetitionUser) => u.invite_status === "accepted")
      .map((u: CompetitionUser) => u.user_id);
    const [userScores, breakdownRows] = await Promise.all([
      getUserScores(competition),
      withBreakdown
        ? getActivityBreakdownBatch(
            acceptedIds,
            competition.start_date,
            competition.end_date ?? undefined,
            competition.workouts,
          )
        : Promise.resolve([]),
    ]);
    const activityByUser: Record<
      string,
      NonNullable<CompetitionUser["daily_activity"]>
    > = {};
    for (const row of breakdownRows) {
      const byDate = (activityByUser[row.user_id] ??= {});
      const byType = (byDate[row.local_date] ??= {});
      byType[row.workout_type] = {
        distance: Number(row.total_distance),
        count: Number(row.workout_count),
      };
    }
    competition.users = competition.users.map((user: CompetitionUser) => ({
      ...user,
      ...userScores[user.user_id],
      ...(withBreakdown
        ? { daily_activity: activityByUser[user.user_id] ?? {} }
        : {}),
    }));
    attachTeamScores(competition);
  }

  return competition;
}

/**
 * Derive per-team scores (straight sum of accepted members' scores) onto
 * competition.teams.teams entries. Purely additive response enrichment —
 * nothing is stored, so team standings always track the live recompute.
 */
function attachTeamScores(competition: Competition): void {
  const teams = competition.teams?.teams;
  if (!teams?.length) return;
  const totals = new Map<string, number>(teams.map((t) => [t.id, 0]));
  for (const user of competition.users) {
    if (user.invite_status !== "accepted" || !user.team_id) continue;
    if (totals.has(user.team_id)) {
      totals.set(user.team_id, totals.get(user.team_id)! + (user.score ?? 0));
    }
  }
  for (const team of teams) team.score = totals.get(team.id) ?? 0;
}

/**
 * Team-aware final outcome for team competitions. Teams rank by summed member
 * scores and ONLY teams can win — a participant without a team places after
 * every team (the UI tells them they're competing without a team). The stored
 * winner stays a user id for API compatibility: the winning team's best-scoring
 * member. Every member of a team shares that team's placement, so trophies go
 * to the whole team. Returns null when the comp has no teams (or no team has
 * any member) — callers fall through to the individual logic.
 */
function teamAwareOutcome(
  competition: Competition,
  scores: UserData,
): {
  winnerId: string;
  topScore: number;
  placements: Map<string, number>;
} | null {
  const teams = competition.teams?.teams;
  if (!teams?.length) return null;

  const membersByTeam = new Map<string, string[]>(teams.map((t) => [t.id, []]));
  const assigned = new Set<string>();
  for (const user of competition.users) {
    if (user.invite_status !== "accepted" || !user.team_id) continue;
    const members = membersByTeam.get(user.team_id);
    if (!members) continue; // orphaned team_id — treated as unassigned
    members.push(user.user_id);
    assigned.add(user.user_id);
  }

  const entities = teams
    .map((t) => {
      const members = (membersByTeam.get(t.id) ?? []).sort(
        (a, b) => (scores[b]?.score ?? 0) - (scores[a]?.score ?? 0),
      );
      return {
        members,
        score: members.reduce((sum, m) => sum + (scores[m]?.score ?? 0), 0),
      };
    })
    .filter((e) => e.members.length > 0)
    .sort((a, b) => b.score - a.score);
  if (entities.length === 0) return null;

  const placements = new Map<string, number>();
  let placement = 1;
  entities.forEach((entity, i) => {
    if (i > 0 && entity.score < entities[i - 1].score) placement = i + 1;
    for (const member of entity.members) placements.set(member, placement);
  });
  // Unassigned participants follow every team, ranked by their own score.
  const solo = Object.keys(scores)
    .filter((id) => !assigned.has(id))
    .sort((a, b) => (scores[b]?.score ?? 0) - (scores[a]?.score ?? 0));
  let soloPlacement = entities.length + 1;
  solo.forEach((id, i) => {
    if (i > 0 && (scores[id]?.score ?? 0) < (scores[solo[i - 1]]?.score ?? 0)) {
      soloPlacement = entities.length + i + 1;
    }
    placements.set(id, soloPlacement);
  });

  return {
    winnerId: entities[0].members[0],
    topScore: entities[0].score,
    placements,
  };
}

/**
 * How many finished competitions the record read walks. Beyond this the
 * response reports `truncated` rather than growing without bound (same shape as
 * the H2H matchup history).
 */
const RECORD_COMPETITION_LIMIT = 500;
/** Opponents returned, most-met first. */
const RECORD_RIVAL_LIMIT = 25;
/** Finished competitions echoed back for the history strip. */
const RECORD_RECENT_LIMIT = 10;

const COMPETITION_TYPES: CompetitionType[] = [
  "streaks",
  "apex",
  "clash",
  "targets",
  "race",
];

/**
 * A user's win/loss record across every competition they finished.
 *
 * Reads `competitions` + `competition_users` ONLY — deliberately never
 * `getUserScores`. Standings are recomputed live on every read, which is right
 * for a competition you're looking at and completely wrong for a career total:
 * recomputing every competition a user ever finished would make this the
 * slowest route in the app. That's also why `recent[]` carries no score —
 * scores aren't stored (`competition_users.progress` is vestigial) — and the
 * detail screen already has the full picture when you tap through.
 *
 * "Finished" is `competitions.ended`, and the outcome is `competitions.winner`,
 * which resolution stamps for every ended competition (including team play,
 * where `teamAwareOutcome` writes the winning team's best member). So there is
 * no tie state to model: a tie was already resolved to one winner server-side.
 */
export async function getCompetitionRecord(
  userId: string,
): Promise<CompetitionRecordResponse> {
  const rows = await db.query<{
    id: string;
    competition_name: string;
    type: CompetitionType;
    end_date: string | null;
    winner: string | null;
    placement: number | null;
    participant_count: string;
  }>(
    `SELECT
			c.id,
			c.competition_name,
			c.type,
			c.end_date::text AS end_date,
			c.winner,
			cu.placement,
			(
				SELECT COUNT(*)
				FROM competition_users cu2
				WHERE cu2.competition_id = c.id
					AND cu2.invite_status = 'accepted'
			)::text AS participant_count
		FROM competitions c
		JOIN competition_users cu
			ON cu.competition_id = c.id
			AND cu.user_id = $1
			AND cu.invite_status = 'accepted'
		WHERE c.ended = TRUE
		ORDER BY c.end_date DESC NULLS LAST
		LIMIT $2`,
    [userId, RECORD_COMPETITION_LIMIT + 1],
  );

  const truncated = rows.length > RECORD_COMPETITION_LIMIT;
  const finished = truncated ? rows.slice(0, RECORD_COMPETITION_LIMIT) : rows;

  let wins = 0;
  let podiums = 0;
  let podiumsKnownOf = 0;
  const byType = new Map<CompetitionType, CompetitionRecordByType>(
    COMPETITION_TYPES.map((type) => [
      type,
      { type, wins: 0, losses: 0, total: 0 },
    ]),
  );

  for (const row of finished) {
    const won = row.winner !== null && row.winner === userId;
    if (won) wins++;
    if (row.placement !== null) {
      podiumsKnownOf++;
      if (row.placement >= 1 && row.placement <= 3) podiums++;
    }

    // A type outside the known five would mean the CHECK constraint changed;
    // skip rather than invent a bucket.
    const bucket = byType.get(row.type);
    if (bucket) {
      bucket.total++;
      if (won) bucket.wins++;
      else bucket.losses++;
    }
  }

  const total = finished.length;
  const losses = Math.max(0, total - wins);

  // `finished` is already newest-first, so the current streak is the leading
  // run of wins and the best is the longest run anywhere in it.
  let currentWinStreak = 0;
  let bestWinStreak = 0;
  let run = 0;
  for (const row of finished) {
    if (row.winner !== null && row.winner === userId) {
      run++;
      if (run > bestWinStreak) bestWinStreak = run;
    } else {
      if (currentWinStreak === 0) currentWinStreak = run;
      run = 0;
    }
  }
  // Never broken: every finished competition was a win.
  if (currentWinStreak === 0) currentWinStreak = run;

  return {
    record: {
      wins,
      losses,
      total,
      podiums,
      podiums_known_of: podiumsKnownOf,
    },
    win_rate: total > 0 ? wins / total : 0,
    current_win_streak: currentWinStreak,
    best_win_streak: bestWinStreak,
    by_type: COMPETITION_TYPES.map((type) => byType.get(type)!),
    rivals: await getCompetitionRivals(
      userId,
      finished.map((row) => row.id),
    ),
    recent: finished.slice(0, RECORD_RECENT_LIMIT).map((row) => ({
      competition_id: row.id,
      competition_name: row.competition_name,
      type: row.type,
      end_date: row.end_date,
      placement: row.placement,
      participant_count: parseInt(row.participant_count, 10) || 0,
      winner_user_id: row.winner,
      won: row.winner !== null && row.winner === userId,
    })),
    truncated,
  };
}

/**
 * Who you've actually played against, and how it went.
 *
 * One set-based query over the competitions already resolved above, so this
 * costs one round trip regardless of how many people you've competed with.
 * Projects named user columns rather than `u.*`: this route returns other
 * people's rows.
 */
async function getCompetitionRivals(
  userId: string,
  competitionIds: string[],
): Promise<CompetitionRival[]> {
  if (competitionIds.length === 0) return [];

  const rows = await db.query<{
    user_id: string;
    username: string | null;
    first_name: string | null;
    profile_image_url: string | null;
    wins: string;
    losses: string;
    meetings: string;
    last_competed_on: string | null;
  }>(
    `SELECT
			u.user_id,
			u.username,
			u.first_name,
			u.profile_image_url,
			COUNT(*) FILTER (WHERE c.winner = $1)::text AS wins,
			COUNT(*) FILTER (WHERE c.winner = cu.user_id)::text AS losses,
			COUNT(*)::text AS meetings,
			MAX(c.end_date)::text AS last_competed_on
		FROM competition_users cu
		JOIN competitions c ON c.id = cu.competition_id
		JOIN users u ON u.user_id = cu.user_id
		WHERE cu.competition_id = ANY($2::text[])
			AND cu.user_id <> $1
			AND cu.invite_status = 'accepted'
		GROUP BY u.user_id, u.username, u.first_name, u.profile_image_url
		-- Order by the AGGREGATES, not the ::text aliases above: sorting the
		-- text would rank "9" over "10".
		ORDER BY COUNT(*) DESC, MAX(c.end_date) DESC NULLS LAST
		LIMIT $3`,
    [userId, competitionIds, RECORD_RIVAL_LIMIT],
  );

  return rows.map((row) => ({
    user_id: row.user_id,
    username: row.username,
    first_name: row.first_name,
    profile_image_url: row.profile_image_url,
    wins: parseInt(row.wins, 10) || 0,
    losses: parseInt(row.losses, 10) || 0,
    meetings: parseInt(row.meetings, 10) || 0,
    last_competed_on: row.last_competed_on,
  }));
}

export async function getCompetitions(
  userId: string,
  {
    page = 1,
    status = "active",
    pageSize = 10,
  }: { page: number; status: string; pageSize: number },
): Promise<Competition[]> {
  let statusCondition = "";
  const TODAY_ET_SQL = "(NOW() AT TIME ZONE 'America/New_York')::date";

  if (status === "get_set" || status === "lobby") {
    statusCondition = `AND (c.start_date IS NULL OR c.start_date > ${TODAY_ET_SQL})`;
  } else if (status === "go") {
    statusCondition = `AND c.start_date <= ${TODAY_ET_SQL} AND (c.end_date IS NULL OR c.end_date >= ${TODAY_ET_SQL})`;
  } else if (status === "active") {
    // Lobby + currently running (excludes finished)
    statusCondition = `AND (c.start_date IS NULL OR c.end_date IS NULL OR c.end_date >= ${TODAY_ET_SQL})`;
  } else if (status === "finished") {
    statusCondition = `AND (c.end_date IS NOT NULL AND c.end_date < ${TODAY_ET_SQL})`;
  }
  // status === 'all' or 'on_your_mark' => no date filter from statusCondition

  const query = `SELECT
			c.*,
			${USERS_AGG_SQL}
		FROM competitions c
		LEFT JOIN competition_users cu ON cu.competition_id = c.id
		LEFT JOIN users u ON u.user_id = cu.user_id
		WHERE c.id IN (
			SELECT competition_id
	  		FROM competition_users
	  		WHERE user_id = $1
			${status === "on_your_mark" ? "AND invite_status = 'pending'" : "AND invite_status = 'accepted'"}
		)
		${statusCondition}
		GROUP BY c.id
		ORDER BY c.start_date DESC NULLS FIRST
		LIMIT $2 OFFSET $3`;

  const competitions = await db.query(query, [
    userId,
    pageSize,
    (page - 1) * pageSize,
  ]);

  // Compute scores for started competitions (same logic as getCompetition singular)
  for (const competition of competitions) {
    if (
      competition.start_date &&
      new Date(competition.start_date + " EST") <= new Date()
    ) {
      const userScores = await getUserScores(competition);
      competition.users = competition.users.map((user: CompetitionUser) => ({
        ...user,
        ...userScores[user.user_id],
      }));
      attachTeamScores(competition);
    }
  }

  return competitions;
}

export async function removeUserFromCompetition(
  competitionId: string,
  userId: string,
) {
  await db.query(
    `DELETE FROM competition_users
		WHERE competition_id = $1 AND user_id = $2`,
    [competitionId, userId],
  );
}

export async function sendCompetitionInvite(
  competitionId: string,
  inviteUserId: string,
) {
  await db.query(
    `INSERT INTO competition_users (
			competition_id, user_id, invite_status
		) VALUES (
			$1, $2, 'pending'
		)`,
    [competitionId, inviteUserId],
  );
}

export async function updateCompetitionInvite(
  competitionId: string,
  inviteUserId: string,
  status: "accepted" | "declined",
): Promise<CompetitionUser> {
  const [updatedUserStatus] = await db.query(
    `UPDATE competition_users
		SET invite_status = $1
		WHERE competition_id = $2 AND user_id = $3
		RETURNING *`,
    [status, competitionId, inviteUserId],
  );

  // Entered a competition — re-evaluate the "competed in X" badges.
  if (status === "accepted") {
    evaluateSocialBadgesForUser(inviteUserId).catch(() => {});
  }

  return updatedUserStatus;
}

/**
 * Auto-start a competition once every invite has been answered 'accepted'.
 * Called after an invite acceptance. Mirrors the manual Start button: the
 * competition begins at midnight ET (start_date = tomorrow's ET date) and
 * end_date is derived from options.duration_hours when set.
 *
 * No-ops unless: not yet started/scheduled (start_date IS NULL), every
 * competition_users row is 'accepted' (a pending OR declined invite blocks
 * auto-start — the owner can still start manually), and >= 2 participants.
 * The UPDATE is guarded with `start_date IS NULL` so concurrent accepts
 * can't double-start or double-notify.
 *
 * Returns true if this call started the competition.
 */
export async function autoStartIfAllAccepted(
  competitionId: string,
): Promise<boolean> {
  const [comp] = await db.query<{
    start_date: string | null;
    competition_name: string;
    options: CompetitionOptions | null;
    accepted_count: number;
    unanswered_count: number;
  }>(
    `SELECT c.start_date, c.competition_name, c.options,
			COUNT(*) FILTER (WHERE cu.invite_status = 'accepted')::int AS accepted_count,
			COUNT(*) FILTER (WHERE cu.invite_status <> 'accepted')::int AS unanswered_count
		FROM competitions c
		JOIN competition_users cu ON cu.competition_id = c.id
		WHERE c.id = $1
		GROUP BY c.id`,
    [competitionId],
  );

  if (
    !comp ||
    comp.start_date ||
    comp.unanswered_count > 0 ||
    comp.accepted_count < 2
  ) {
    return false;
  }

  // Start at midnight ET tomorrow so the first official day is a full day
  // for everyone — same computation as the manual start in startComp().
  const todayET = getTodayET();
  const [y, m, d] = todayET.split("-").map(Number);
  const tomorrowUTC = new Date(Date.UTC(y, m - 1, d + 1));
  const startDate = tomorrowUTC.toISOString().split("T")[0];

  let endDate: string | null = null;
  if (comp.options?.duration_hours) {
    const end = new Date(
      tomorrowUTC.getTime() + comp.options.duration_hours * 60 * 60 * 1000,
    );
    endDate = end.toISOString().split("T")[0];
  }

  const updated = await db.query(
    `UPDATE competitions
		SET start_date = $2, end_date = COALESCE($3::date, end_date)
		WHERE id = $1 AND start_date IS NULL
		RETURNING id`,
    [competitionId, startDate, endDate],
  );
  if (updated.length === 0) return false; // lost a race with another accept/manual start

  // Unlike the manual start, nobody clicked a button — notify ALL participants.
  const participants = await db.query<{ user_id: string }>(
    `SELECT user_id FROM competition_users WHERE competition_id = $1 AND invite_status = 'accepted'`,
    [competitionId],
  );
  for (const participant of participants) {
    sendOrQueueCompetitionNotification(
      participant.user_id,
      "competition_started",
      competitionId,
      comp.competition_name,
    ).catch((err) =>
      console.error(
        "[Push] Error sending competition auto-start notification:",
        err.message,
      ),
    );
  }

  return true;
}

interface UpdateCompetitionParams {
  competitionId: string;
  competition_name?: string;
  start_date?: string;
  end_date?: string;
  workouts?: CompetitionActivity[];
  type?: CompetitionType;
  options?: Partial<CompetitionOptions>;
}

export async function updateCompetition(
  params: UpdateCompetitionParams,
): Promise<Competition> {
  const { competitionId, options, ...updateFields } = params;

  const existingCompetition = await getCompetition(competitionId);

  if (!existingCompetition) {
    throw new BadRequestError(`Competition with id ${competitionId} not found`);
  }

  if (updateFields.competition_name !== undefined) {
    updateFields.competition_name = validateCompetitionName(
      updateFields.competition_name,
    );
  }

  const updates: string[] = [];
  const values: any[] = [];
  let paramIndex = 1;

  for (const [key, value] of Object.entries(updateFields)) {
    if (value !== undefined) {
      if (key === "workouts") {
        updates.push(`${key} = $${paramIndex}`);
        values.push(JSON.stringify(value));
      } else {
        updates.push(`${key} = $${paramIndex}`);
        values.push(value);
      }
      paramIndex++;
    }
  }

  if (options && Object.keys(options).length > 0) {
    const mergedOptions = {
      ...existingCompetition.options,
      ...options,
    };
    updates.push(`options = $${paramIndex}`);
    values.push(JSON.stringify(mergedOptions));
    paramIndex++;
  }

  if (updates.length === 0) {
    return existingCompetition;
  }

  values.push(competitionId);

  const query = `
		UPDATE competitions
		SET ${updates.join(", ")}
		WHERE id = $${paramIndex}
		RETURNING *
	`;

  const [updatedCompetition] = await db.query(query, values);

  return getCompetition(updatedCompetition.id);
}

export async function deleteCompetition(
  competitionId: string,
  userId: string,
): Promise<void> {
  const competition = await getCompetition(competitionId);

  if (!competition) {
    throw new BadRequestError(`Competition with id ${competitionId} not found`);
  }

  if (competition.owner !== userId) {
    throw new BadRequestError("Only the competition owner can delete it");
  }

  // Delete competition_users first (foreign key), then competition
  await db.query("DELETE FROM competition_users WHERE competition_id = $1", [
    competitionId,
  ]);
  await db.query("DELETE FROM competitions WHERE id = $1", [competitionId]);
}

/** Maximum number of teams per competition. */
export const MAX_TEAMS = 12;

function validateTeamName(name: unknown): string {
  if (typeof name !== "string") {
    throw new BadRequestError("team name must be a string");
  }
  const trimmed = name.trim();
  if (trimmed.length === 0) {
    throw new BadRequestError("team name cannot be empty");
  }
  if (trimmed.length > COMPETITION_NAME_MAX_LENGTH) {
    throw new BadRequestError(
      `team name cannot exceed ${COMPETITION_NAME_MAX_LENGTH} characters`,
    );
  }
  return trimmed;
}

export interface SetCompetitionTeamsParams {
  member_pick?: boolean;
  teams?: { id?: string; name: string }[];
  assignments?: Record<string, string | null>;
}

/**
 * Owner-only team setup (authz + lobby check live in the controller).
 * Replaces the team list and/or member_pick flag, applies membership
 * assignments, and clears memberships that point at deleted teams.
 * An empty team list turns team play off entirely (column back to NULL).
 */
export async function setCompetitionTeams(
  competition: Competition,
  params: SetCompetitionTeamsParams,
): Promise<Competition> {
  const { member_pick, teams, assignments } = params;

  if (member_pick !== undefined && typeof member_pick !== "boolean") {
    throw new BadRequestError("member_pick must be a boolean");
  }

  let teamList = competition.teams?.teams ?? [];
  if (teams !== undefined) {
    if (!Array.isArray(teams)) {
      throw new BadRequestError("teams must be an array");
    }
    if (teams.length > MAX_TEAMS) {
      throw new BadRequestError(`Cannot have more than ${MAX_TEAMS} teams`);
    }
    teamList = teams.map((t) => ({
      // Keep client-known ids for renames; mint ids for new teams.
      id:
        typeof t.id === "string" && t.id.length > 0
          ? t.id
          : `t_${randomUUID().replaceAll("-", "").slice(0, 12)}`,
      name: validateTeamName(t.name),
    }));
    const ids = teamList.map((t) => t.id);
    const names = teamList.map((t) => t.name.toLowerCase());
    if (new Set(ids).size !== ids.length) {
      throw new BadRequestError("duplicate team ids");
    }
    if (new Set(names).size !== names.length) {
      throw new BadRequestError("duplicate team names");
    }
  }

  const stored =
    teamList.length === 0
      ? null
      : {
          member_pick: member_pick ?? competition.teams?.member_pick ?? false,
          teams: teamList.map(({ id, name }) => ({ id, name })),
        };

  const validIds = teamList.map((t) => t.id);
  const participantIds = new Set(competition.users.map((u) => u.user_id));
  const entries = Object.entries(assignments ?? {});
  for (const [userId, teamId] of entries) {
    if (!participantIds.has(userId)) {
      throw new BadRequestError(`${userId} is not in this competition`);
    }
    if (teamId !== null && !validIds.includes(teamId)) {
      throw new BadRequestError(`unknown team id: ${teamId}`);
    }
  }

  await db.query(
    `UPDATE competitions SET teams = $1, updated_at = NOW() WHERE id = $2`,
    [stored ? JSON.stringify(stored) : null, competition.id],
  );
  // Membership on a deleted team (or teams turned off) reverts to unassigned.
  await db.query(
    `UPDATE competition_users SET team_id = NULL
		WHERE competition_id = $1 AND team_id IS NOT NULL AND team_id <> ALL($2::text[])`,
    [competition.id, validIds],
  );
  for (const [userId, teamId] of entries) {
    await db.query(
      `UPDATE competition_users SET team_id = $1 WHERE competition_id = $2 AND user_id = $3`,
      [teamId, competition.id, userId],
    );
  }

  return getCompetition(competition.id);
}

/** Self-assignment (authz — member_pick/owner/lobby — lives in the controller). */
export async function pickCompetitionTeam(
  competitionId: string,
  userId: string,
  teamId: string | null,
): Promise<Competition> {
  await db.query(
    `UPDATE competition_users SET team_id = $1 WHERE competition_id = $2 AND user_id = $3`,
    [teamId, competitionId, userId],
  );
  return getCompetition(competitionId);
}

/**
 * Per-participant recent-form stats for the Balance/Randomize UI: average
 * per day over the last 14 FULL days (ending yesterday ET — today would skew
 * low), filtered to the competition's activities (run/walk/both) or steps,
 * plus the same average projected onto the competition's interval.
 */
export async function getCompetitionTeamStats(competition: Competition) {
  const WINDOW_DAYS = 14;
  const [y, m, d] = getTodayET().split("-").map(Number);
  const todayMs = Date.UTC(y, m - 1, d);
  const toStr = (ms: number) => new Date(ms).toISOString().split("T")[0];
  const start = toStr(todayMs - WINDOW_DAYS * 86400000);
  const end = toStr(todayMs - 86400000);

  const acceptedIds = competition.users
    .filter((u) => u.invite_status === "accepted")
    .map((u) => u.user_id);
  const isStepUnit = competition.options.unit === "steps";
  const rows = isStepUnit
    ? await getStepsDateRangeBatch(acceptedIds, start, end)
    : await getQuantityDateRangeBatch(
        acceptedIds,
        start,
        end,
        competition.workouts,
      );

  const totals: Record<string, number> = {};
  for (const id of acceptedIds) totals[id] = 0;
  for (const row of rows) totals[row.user_id] += Number(row.total_distance);

  const interval = competition.options.interval ?? "day";
  // ponytail: month ≈ 30 days — close enough for a balancing heuristic.
  const multiplier = interval === "week" ? 7 : interval === "month" ? 30 : 1;
  const round2 = (n: number) => Math.round(n * 100) / 100;

  const stats: Record<
    string,
    { avg_per_day: number; avg_per_interval: number }
  > = {};
  for (const id of acceptedIds) {
    const avgPerDay = totals[id] / WINDOW_DAYS;
    stats[id] = {
      avg_per_day: round2(avgPerDay),
      avg_per_interval: round2(avgPerDay * multiplier),
    };
  }

  return {
    window_days: WINDOW_DAYS,
    interval,
    unit: competition.options.unit,
    stats,
  };
}

interface UserData {
  [userId: string]: {
    intervals: {
      [intervalKey: string]: number;
    };
    score: number;
    remaining_lives?: number;
    has_manual_workouts?: boolean;
  };
}

export async function getUserScores(
  competition: Competition,
  { excludeCurrentInterval = false }: { excludeCurrentInterval?: boolean } = {},
): Promise<UserData> {
  const userData: UserData = {};

  // Only called when start_date is non-null (guarded by caller)
  if (!competition.start_date) return userData;

  // Only process accepted users.
  const acceptedUsers = competition.users.filter(
    (u: CompetitionUser) => u.invite_status === "accepted",
  );
  const acceptedUserIds = acceptedUsers.map((u) => u.user_id);
  const endDate = competition.end_date ?? getTodayET();

  // Step competitions read from daily_steps; distance competitions from workouts.
  // Manual-workout flag is irrelevant for steps (HealthKit-observer-fed only).
  const isStepUnit = competition.options.unit === "steps";

  const [batchRows, manualUserIds] = await Promise.all([
    isStepUnit
      ? getStepsDateRangeBatch(
          acceptedUserIds,
          competition.start_date,
          competition.end_date ?? undefined,
        )
      : getQuantityDateRangeBatch(
          acceptedUserIds,
          competition.start_date,
          competition.end_date ?? undefined,
          competition.workouts,
        ),
    isStepUnit
      ? Promise.resolve(new Set<string>())
      : getUsersWithManualWorkouts(
          acceptedUserIds,
          competition.start_date,
          endDate,
        ),
  ]);

  // Initialize empty buckets for every accepted user so users with zero workouts still appear.
  for (const userId of acceptedUserIds) {
    userData[userId] = {
      intervals: {},
      score: 0,
      has_manual_workouts: manualUserIds.has(userId),
    };
  }

  // Bucket rows into per-user interval totals.
  for (const row of batchRows) {
    const intervalKey = getCurrentInterval(
      row.local_date,
      competition.options.interval,
      competition.start_date,
    );
    const buckets = userData[row.user_id].intervals;
    buckets[intervalKey] =
      (buckets[intervalKey] ?? 0) + Number(row.total_distance);
  }

  const allIntervals = getIntervalRange(competition);
  const todaysInterval = getCurrentInterval(
    getTodayET(),
    competition.options.interval,
    competition.start_date,
  );

  // Determine the inclusive end index for scoring:
  // - If excludeCurrentInterval=true, stop one interval before today.
  // - Otherwise, include today (or end_date if past today).
  const todayIdx = allIntervals.indexOf(todaysInterval);
  let scoringEndIdx: number;
  if (excludeCurrentInterval) {
    scoringEndIdx = todayIdx >= 0 ? todayIdx - 1 : allIntervals.length - 1;
  } else {
    scoringEndIdx = todayIdx >= 0 ? todayIdx : allIntervals.length - 1;
  }

  // Zero-fill userData.intervals for all intervals up to scoringEndIdx
  for (let i = 0; i <= scoringEndIdx; i++) {
    const interval = allIntervals[i];
    Object.keys(userData).forEach((userId) => {
      if (!userData[userId].intervals[interval]) {
        userData[userId].intervals[interval] = 0;
      }
    });
  }

  if (competition.type === "streaks") {
    // Prefer options.lives; fall back to options.first_to for legacy streak competitions.
    const totalLives =
      competition.options.lives ?? competition.options.first_to ?? 1;

    // Initialize remaining_lives for each user
    Object.keys(userData).forEach((userId) => {
      userData[userId].remaining_lives = totalLives;
    });

    for (let i = 0; i <= scoringEndIdx; i++) {
      const interval = allIntervals[i];
      const isToday = interval === todaysInterval;
      Object.keys(userData).forEach((userId) => {
        // Once eliminated, stay eliminated — score freezes.
        if ((userData[userId].remaining_lives ?? 0) <= 0) return;

        const userIntervals = userData[userId].intervals;
        if ((userIntervals[interval] ?? 0) >= competition.options.goal) {
          userData[userId].score++;
        } else if (!isToday) {
          // Don't penalize on today's partial-day data.
          userData[userId].remaining_lives!--;
        }
      });
    }
  } else if (competition.type === "apex") {
    Object.keys(userData).forEach((userId) => {
      let score = 0;
      for (let i = 0; i <= scoringEndIdx; i++) {
        score += userData[userId].intervals[allIntervals[i]] ?? 0;
      }
      userData[userId].score = score;
    });
  } else if (competition.type === "clash") {
    // Clash always excludes today's partial-day data (per-interval head-to-head).
    const clashEndIdx = todayIdx >= 0 ? todayIdx - 1 : scoringEndIdx;
    for (let i = 0; i <= clashEndIdx; i++) {
      const interval = allIntervals[i];
      const userQuantities: { [quantities: number]: string[] } = {};

      Object.keys(userData).forEach((userId) => {
        const quantity = userData[userId].intervals[interval] ?? 0;
        if (!Object.keys(userQuantities).includes(quantity.toString())) {
          userQuantities[quantity] = [];
        }
        userQuantities[quantity].push(userId);
      });

      const maxQuantity = Math.max(
        ...Object.keys(userQuantities).map((q) => parseFloat(q)),
      );

      if (maxQuantity > 0) {
        userQuantities[maxQuantity].forEach(
          (userId) => userData[userId].score++,
        );
      }
    }
  } else if (competition.type === "targets") {
    for (let i = 0; i <= scoringEndIdx; i++) {
      const interval = allIntervals[i];
      Object.keys(userData).forEach((userId) => {
        if (
          (userData[userId].intervals[interval] ?? 0) >=
          competition.options.goal
        ) {
          userData[userId].score++;
        }
      });
    }
  } else if (competition.type === "race") {
    Object.keys(userData).forEach((userId) => {
      let score = 0;
      for (let i = 0; i <= scoringEndIdx; i++) {
        score += userData[userId].intervals[allIntervals[i]] ?? 0;
      }
      userData[userId].score = score;
    });
  }

  return userData;
}

export function getCurrentInterval(
  currentDate: Date | string | number,
  interval?: "day" | "week" | "month",
  startDate?: string | null,
): string {
  let year: number, month: number, day: number;

  if (
    typeof currentDate === "string" &&
    /^\d{4}-\d{2}-\d{2}$/.test(currentDate)
  ) {
    [year, month, day] = currentDate.split("-").map(Number);
  } else {
    const date =
      currentDate instanceof Date ? currentDate : new Date(currentDate);
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone: "America/New_York",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).formatToParts(date);
    year = parseInt(parts.find((p) => p.type === "year")!.value);
    month = parseInt(parts.find((p) => p.type === "month")!.value);
    day = parseInt(parts.find((p) => p.type === "day")!.value);
  }

  const pad = (n: number) => String(n).padStart(2, "0");

  if (interval === "week") {
    // Anchor weekly windows to the competition's start date so the first week
    // is start..start+6 (not snapped to a Sun–Sat calendar week). The interval
    // key is the date that begins the 7-day window containing currentDate.
    if (startDate && /^\d{4}-\d{2}-\d{2}$/.test(startDate)) {
      const [sy, sm, sd] = startDate.split("-").map(Number);
      const startMs = Date.UTC(sy, sm - 1, sd);
      const curMs = Date.UTC(year, month - 1, day);
      const weekIndex = Math.floor((curMs - startMs) / 86400000 / 7);
      const windowStartMs = startMs + weekIndex * 7 * 86400000;
      const d = new Date(windowStartMs);
      return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
    }
    // Fallback (no start date): snap to the calendar week ending Sunday.
    const d = new Date(year, month - 1, day);
    const daysUntilSunday = (7 - d.getDay()) % 7;
    d.setDate(d.getDate() + daysUntilSunday);
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  } else if (interval === "month") {
    return `${year}-${pad(month)}`;
  } else {
    return `${year}-${pad(month)}-${pad(day)}`;
  }
}

function getIntervalRange(competition: Competition): string[] {
  if (!competition.start_date) return [];

  const intervals: string[] = [];
  const endDateStr = competition.end_date ?? getTodayET();

  const [sy, sm, sd] = competition.start_date.split("-").map(Number);
  const [ey, em, ed] = endDateStr.split("-").map(Number);

  // Pure calendar-date iteration via UTC math — DST-free because we never mix timezones.
  // Weekly windows are anchored to the start date (handled by getCurrentInterval), so we
  // iterate from start_date itself in 7-day steps rather than snapping to a calendar week.
  const endUtcMs = Date.UTC(ey, em - 1, ed);
  let currentMs = Date.UTC(sy, sm - 1, sd);

  const toDateStr = (ms: number): string => {
    const d = new Date(ms);
    const y = d.getUTCFullYear();
    const m = String(d.getUTCMonth() + 1).padStart(2, "0");
    const day = String(d.getUTCDate()).padStart(2, "0");
    return `${y}-${m}-${day}`;
  };

  while (currentMs <= endUtcMs) {
    const intervalKey = getCurrentInterval(
      toDateStr(currentMs),
      competition.options.interval,
      competition.start_date,
    );
    intervals.push(intervalKey);

    if (competition.options.interval === "week") {
      currentMs += 7 * 86400000;
    } else if (competition.options.interval === "month") {
      const nd = new Date(currentMs);
      nd.setUTCMonth(nd.getUTCMonth() + 1);
      currentMs = nd.getTime();
    } else {
      // 'day' or default
      currentMs += 86400000;
    }
  }

  return intervals;
}

export async function checkRaceCompletions(userId: string): Promise<void> {
  const activeRaces = await db.query<Competition & { id: string }>(
    `SELECT c.*
		FROM competitions c
		JOIN competition_users cu ON cu.competition_id = c.id
		WHERE cu.user_id = $1
			AND cu.invite_status = 'accepted'
			AND c.type = 'race'
			AND c.start_date IS NOT NULL
			AND c.start_date <= (NOW() AT TIME ZONE 'America/New_York')::date
			AND c.winner IS NULL
			AND (c.end_date IS NULL OR c.end_date >= (NOW() AT TIME ZONE 'America/New_York')::date)`,
    [userId],
  );

  if (activeRaces.length === 0) return;

  for (const race of activeRaces) {
    // Team races finish on combined TEAM distance — evaluate with the same
    // team-aware outcome the cron uses, not this runner's solo total.
    if (race.teams?.teams?.length) {
      const fullComp = await getCompetition(race.id);
      if (!fullComp) continue;
      const scores = await getUserScores(fullComp);
      const outcome = teamAwareOutcome(fullComp, scores);
      if (outcome && outcome.topScore >= race.options.goal) {
        await db.query(
          `UPDATE competitions SET end_date = $1, winner = $2, ended = true WHERE id = $3 AND winner IS NULL`,
          [getTodayET(), outcome.winnerId, race.id],
        );
        await resolveCompetitionPlacements(race.id, scores, fullComp);
        evaluateSocialBadgesForUser(outcome.winnerId).catch(() => {});
      }
      continue;
    }

    const workoutTypes = (race.workouts ?? ["running", "walking"])
      .map((t: string) => WORKOUT_TYPE_MAP[t])
      .filter(Boolean);

    const startDate = race.start_date!;
    const today = getTodayET();
    const endDate = race.end_date ?? today;

    const [result] = await db.query<{ total: number }>(
      `SELECT COALESCE(SUM(distance), 0) as total
			FROM workouts
			WHERE user_id = $1
				AND local_date >= $2
				AND local_date <= $3
				AND workout_type = ANY($4::text[])
				AND deleted_at IS NULL AND exclusion_reason IS NULL`,
      [userId, startDate, endDate, workoutTypes],
    );

    if (result.total >= race.options.goal) {
      await db.query(
        `UPDATE competitions SET end_date = $1, winner = $2, ended = true WHERE id = $3 AND winner IS NULL`,
        [today, userId, race.id],
      );
      await resolveCompetitionPlacements(race.id);
      evaluateSocialBadgesForUser(userId).catch(() => {});
    }
  }
}

export async function resolveExpiredCompetitions(): Promise<void> {
  const now = new Date();
  const todayStr = getTodayET();

  const candidates = await db.query<Competition & { id: string }>(
    `SELECT c.*, ${USERS_AGG_SQL}
		FROM competitions c
		LEFT JOIN competition_users cu ON cu.competition_id = c.id
		LEFT JOIN users u ON u.user_id = cu.user_id
		WHERE c.start_date IS NOT NULL
			AND c.start_date <= (NOW() AT TIME ZONE 'America/New_York')::date
			AND c.winner IS NULL
		GROUP BY c.id`,
  );

  for (const competition of candidates) {
    try {
      await resolveIfComplete(competition, now, todayStr);
    } catch (err: any) {
      console.error(
        `[CRON] Error resolving competition ${competition.id}:`,
        err.message,
      );
    }
  }
}

// Returns the last calendar date whose interval is fully complete as of `todayStr`
// (i.e. the day before the current interval begins). Early-resolution scoring always
// excludes the in-progress current interval, so a competition that resolves at the
// midnight cron must record THIS as its end_date — not the resolution day itself.
// Otherwise, once the calendar advances past the resolution day, live score recomputes
// (getUserScores via getCompetition) fold the resolution day back in as a now-complete
// interval and retroactively change the standings (e.g. a non-winner gaining a phantom
// point for the day after the competition was already decided).
export function lastCompletedIntervalEnd(
  todayStr: string,
  interval: "day" | "week" | "month" | undefined,
  startDate: string,
): string {
  const [ty, tm, td] = todayStr.split("-").map(Number);
  const todayMs = Date.UTC(ty, tm - 1, td);

  let currentIntervalStartMs: number;
  if (interval === "week" && /^\d{4}-\d{2}-\d{2}$/.test(startDate)) {
    // Weekly windows are anchored to start_date (see getCurrentInterval).
    const [sy, sm, sd] = startDate.split("-").map(Number);
    const startMs = Date.UTC(sy, sm - 1, sd);
    const weekIndex = Math.floor((todayMs - startMs) / 86400000 / 7);
    currentIntervalStartMs = startMs + weekIndex * 7 * 86400000;
  } else if (interval === "month") {
    currentIntervalStartMs = Date.UTC(ty, tm - 1, 1);
  } else {
    currentIntervalStartMs = todayMs; // daily (default)
  }

  const pad = (n: number) => String(n).padStart(2, "0");
  const d = new Date(currentIntervalStartMs - 86400000);
  return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
}

async function resolveIfComplete(
  competition: Competition,
  now: Date,
  todayStr: string,
): Promise<void> {
  let shouldResolve = false;
  let computedEndDate: string | null = null;

  // Check 1: end_date has passed (string compare is DST-free since both sides are 'YYYY-MM-DD')
  if (competition.end_date && competition.end_date < todayStr) {
    shouldResolve = true;
  }

  // Check 2: duration_hours elapsed (no end_date set yet)
  if (
    !shouldResolve &&
    !competition.end_date &&
    competition.options.duration_hours &&
    competition.start_date
  ) {
    const startMs = etDateToUtcMs(competition.start_date);
    const durationMs = competition.options.duration_hours * 60 * 60 * 1000;
    if (now.getTime() >= startMs + durationMs) {
      shouldResolve = true;
      computedEndDate = lastCompletedIntervalEnd(
        todayStr,
        competition.options.interval,
        competition.start_date,
      );
    }
  }

  // Check 3: first_to condition (clash and targets — first competitor to reach the
  // point target wins; races use goal, apex uses duration, streaks use first_to as
  // "lives" via the streaks elimination check below).
  if (
    !shouldResolve &&
    competition.options.first_to &&
    (competition.type === "clash" || competition.type === "targets")
  ) {
    const scores = await getUserScores(competition, {
      excludeCurrentInterval: true,
    });
    const scoreValues = Object.values(scores);
    if (scoreValues.length > 0) {
      // Team comps race to first_to on TEAM totals — an individual can't
      // trigger (or win) on their own.
      const outcome = teamAwareOutcome(competition, scores);
      const maxScore = outcome
        ? outcome.topScore
        : Math.max(...scoreValues.map((s) => s.score));
      if (maxScore >= competition.options.first_to) {
        shouldResolve = true;
        computedEndDate = lastCompletedIntervalEnd(
          todayStr,
          competition.options.interval,
          competition.start_date!,
        );
      }
    }
  }

  // Check 3b: streaks — end when one survivor remains (sole survivor wins) or all eliminated
  if (!shouldResolve && competition.type === "streaks") {
    const scores = await getUserScores(competition, {
      excludeCurrentInterval: true,
    });
    const scoreValues = Object.values(scores);
    if (scoreValues.length > 0) {
      const survivors = scoreValues.filter((s) => (s.remaining_lives ?? 0) > 0);
      const allEliminated = survivors.length === 0;
      const soleSurvivor = scoreValues.length > 1 && survivors.length === 1;
      if (allEliminated || soleSurvivor) {
        shouldResolve = true;
        computedEndDate = lastCompletedIntervalEnd(
          todayStr,
          competition.options.interval,
          competition.start_date!,
        );
      }
    }
  }

  // Check 4: race goal reached (backup for races not caught on upload).
  // Team races finish on combined TEAM distance, not any one runner's.
  if (!shouldResolve && competition.type === "race") {
    const scores = await getUserScores(competition, {
      excludeCurrentInterval: true,
    });
    const outcome = teamAwareOutcome(competition, scores);
    const raceScores = outcome
      ? [outcome.topScore]
      : Object.values(scores).map((s) => s.score);
    for (const score of raceScores) {
      if (score >= competition.options.goal) {
        shouldResolve = true;
        computedEndDate = lastCompletedIntervalEnd(
          todayStr,
          competition.options.interval,
          competition.start_date!,
        );
        break;
      }
    }
  }

  if (!shouldResolve) return;

  if (computedEndDate) {
    await db.query(`UPDATE competitions SET end_date = $1 WHERE id = $2`, [
      computedEndDate,
      competition.id,
    ]);
    competition.end_date = computedEndDate;
  }

  const finalScores = await getUserScores(competition, {
    excludeCurrentInterval: true,
  });
  const sortedUsers = Object.entries(finalScores).sort(
    ([, a], [, b]) => b.score - a.score,
  );

  if (sortedUsers.length === 0) return;

  // Team comps: the winning TEAM decides the outcome — record its best member
  // as the (user-typed) winner so the stored result matches what the app
  // announces.
  const outcome = teamAwareOutcome(competition, finalScores);
  const winnerId = outcome?.winnerId ?? sortedUsers[0][0];
  await db.query(
    `UPDATE competitions SET winner = $1, ended = true WHERE id = $2 AND winner IS NULL`,
    [winnerId, competition.id],
  );

  await resolveCompetitionPlacements(competition.id, finalScores, competition);
  evaluateSocialBadgesForUser(winnerId).catch(() => {});

  // Notify all accepted participants that the competition finished
  const acceptedUsers = competition.users.filter(
    (u: CompetitionUser) => u.invite_status === "accepted",
  );
  for (const user of acceptedUsers) {
    sendOrQueueCompetitionNotification(
      user.user_id,
      "competition_finished",
      competition.id,
      competition.competition_name,
    ).catch((err) =>
      console.error(
        "[Push] Error sending competition finish notification:",
        err.message,
      ),
    );
  }
}

async function resolveCompetitionPlacements(
  competitionId: string,
  precomputedScores?: UserData,
  precomputedCompetition?: Competition,
): Promise<void> {
  const competition =
    precomputedCompetition ?? (await getCompetition(competitionId));
  if (!competition) return;
  const scores = precomputedScores ?? (await getUserScores(competition));

  // Team comps: members share their team's placement (whole team medals).
  const outcome = teamAwareOutcome(competition, scores);
  if (outcome) {
    for (const [userId, placement] of outcome.placements) {
      await db.query(
        `UPDATE competition_users SET placement = $1 WHERE competition_id = $2 AND user_id = $3`,
        [placement, competitionId, userId],
      );
    }
    return;
  }

  const sorted = Object.entries(scores).sort(
    ([, a], [, b]) => b.score - a.score,
  );

  let currentPlacement = 1;
  for (let i = 0; i < sorted.length; i++) {
    const [userId, data] = sorted[i];
    if (i > 0 && data.score < sorted[i - 1][1].score) {
      currentPlacement = i + 1;
    }
    await db.query(
      `UPDATE competition_users SET placement = $1 WHERE competition_id = $2 AND user_id = $3`,
      [currentPlacement, competitionId, userId],
    );
  }
}
