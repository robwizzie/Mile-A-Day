import { PostgresService } from "./DbService.js";
import { MIN_PLAUSIBLE_MILE_SECONDS, countedWorkoutSql, formatMilePace } from "./mileTime.js";
import { getStreakErasForUser } from "./workoutService.js";
import { holidayDayQualifiesSql, holidayProbeDates } from "./badgeService.js";
import { HOLIDAYS, holidayKeyForLocalDate, holidayKeyFromBadgeId, type HolidayKey } from "./holidays.js";
import type { UserBadge } from "../types/badge.js";

const db = PostgresService.getInstance();

/**
 * HOW a medal was earned — the additive `earned_detail` on every row of
 * `GET /users/:id/badges`. Read-only and DERIVED at read (nothing new is
 * stored at award time), from the same counted-workout rules the evaluator
 * uses, so a detail can never describe a walk the medal wasn't allowed to
 * count: `countedWorkoutSql`, the plausible-mile floor + 0.95 split distance
 * for pace, the longest era (coverage + pauses) for streaks, and
 * `holidayDayQualifiesSql` for holidays.
 *
 * Bounded per USER, never per badge: each family is one query covering all
 * of that family's medals at once (unnest of thresholds + LATERAL), and a
 * family the user holds nothing in costs nothing. Worst case (every family
 * held) is ~9 statements plus the streak-era computation.
 *
 * Wording: English sentences, second person for the owner ("You ran a 7:42
 * mile"), third for a friend viewing ("Ran a 7:42 mile", "their 25th …").
 * Distances are MILES (the client converts), pace is "m:ss" per mile with
 * `value_seconds` beside it.
 */
export interface EarnedDetail {
  summary: string;
  /** Local YYYY-MM-DD the thing happened (falls back to the award's local day). */
  date: string | null;
  value: string | null;
  unit: string | null;
  workout_id: string | null;
  /** Pace medals only: the mile time in seconds. */
  value_seconds?: number;
}

type Voice = "self" | "friend";

/** Sentences are written for the owner; a friend's copy drops "You" and "your". */
function speak(voice: Voice, sentence: string): string {
  if (voice === "self") return sentence;
  const s = sentence
    .replace(/^You ([a-z])/, (_, c: string) => c.toUpperCase())
    .replace(/\byour\b/g, "their")
    .replace(/\bYour\b/g, "Their");
  return s;
}

function ordinal(n: number): string {
  const mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 13) return `${n}th`;
  switch (n % 10) {
    case 1:
      return `${n}st`;
    case 2:
      return `${n}nd`;
    case 3:
      return `${n}rd`;
    default:
      return `${n}th`;
  }
}

function plural(n: number, one: string, many: string): string {
  return n === 1 ? one : many;
}

/** Floor to 1 decimal — never promise more than was walked (the app floors too). */
function miles1(n: number): string {
  return (Math.floor(n * 10 + 1e-9) / 10).toFixed(1);
}

function addDays(date: string, days: number): string {
  const d = new Date(`${date}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

function reqOf(b: UserBadge): number | null {
  return b.requirement !== null && Number.isFinite(Number(b.requirement))
    ? Number(b.requirement)
    : null;
}

/** "walked" / "ran" from the day's (or workout's) running share. */
function verb(runMiles: number, totalMiles: number): "ran" | "walked" {
  return totalMiles > 0 && runMiles > totalMiles / 2 ? "ran" : "walked";
}

/**
 * `earned_detail` for each of `badges` (one user's rows), keyed by badge id.
 * Never throws: a family whose query fails reports null for its medals.
 */
export async function earnedDetailsFor(
  userId: string,
  badges: UserBadge[],
  voice: Voice,
): Promise<Map<string, EarnedDetail | null>> {
  const out = new Map<string, EarnedDetail | null>();
  if (badges.length === 0) return out;

  const by = (pred: (b: UserBadge) => boolean) => badges.filter(pred);
  const streakB = by((b) => b.category === "streak" || b.badgeId === "special_first_week");
  const milesB = by((b) => b.category === "miles" || b.badgeId === "special_first_mile");
  const paceB = by((b) => b.category === "pace");
  const dailyB = by((b) => b.category === "daily_distance");
  const holidayB = by((b) => b.category === "holiday");
  const challengeB = by((b) => b.category === "challenge");
  const weeklyB = by((b) => b.category === "weekly_challenge");
  const marginB = by((b) => b.badgeId.startsWith("ghost_margin_"));

  const safe = <T>(p: Promise<T>, fallback: T) =>
    p.catch((e: any) => {
      console.error("[badges] earned_detail query failed:", e?.message ?? e);
      return fallback;
    });

  // Local day of each award (the fallback date), from the user's own offset.
  const tzP = safe(
    db.query<{ badge_id: string; day: string }>(
      `SELECT ub.badge_id,
	          to_char(((ub.earned_at AT TIME ZONE 'UTC') + (COALESCE(
	              (SELECT ns.timezone_offset_minutes FROM notification_settings ns WHERE ns.user_id = ub.user_id),
	              (SELECT w.timezone_offset FROM workouts w WHERE w.user_id = ub.user_id ORDER BY w.device_end_date DESC LIMIT 1),
	              0) || ' minutes')::interval)::date, 'YYYY-MM-DD') AS day
	     FROM user_badges ub WHERE ub.user_id = $1`,
      [userId],
    ),
    [],
  );

  const erasP = streakB.length
    ? safe(getStreakErasForUser(userId).then((r) => r.eras), [])
    : Promise.resolve([]);

  // Cumulative counted miles by local day → the first day each total was crossed.
  const milesThresholds = milesB
    .map((b) => (b.badgeId === "special_first_mile" ? 1 : reqOf(b)))
    .filter((n): n is number => n !== null);
  const milesP = milesThresholds.length
    ? safe(
        db.query<{ threshold: number; day: string | null; cum: number | null }>(
          `WITH d AS (
	         SELECT w.local_date, SUM(w.distance) AS miles
	           FROM workouts w WHERE w.user_id = $1 AND ${countedWorkoutSql("w")}
	          GROUP BY w.local_date
	       ), c AS MATERIALIZED (
	         SELECT local_date, SUM(miles) OVER (ORDER BY local_date) AS cum FROM d
	       )
	       SELECT t.threshold::float8 AS threshold,
	              to_char(x.local_date, 'YYYY-MM-DD') AS day, x.cum::float8 AS cum
	         FROM unnest($2::float8[]) AS t(threshold)
	         LEFT JOIN LATERAL (
	           SELECT local_date, cum FROM c WHERE cum >= t.threshold ORDER BY local_date LIMIT 1
	         ) x ON true`,
          [userId, milesThresholds],
        ),
        [],
      )
    : Promise.resolve([]);

  // First day whose counted total reached each daily threshold, with the day's
  // biggest workout and its running share (for "walked"/"ran").
  const dailyThresholds = dailyB.map(reqOf).filter((n): n is number => n !== null);
  const dailyP = dailyThresholds.length
    ? safe(
        db.query<{
          threshold: number;
          day: string | null;
          miles: number | null;
          run_miles: number | null;
          workout_id: string | null;
        }>(
          `WITH d AS MATERIALIZED (
	         SELECT w.local_date, SUM(w.distance) AS miles,
	                COALESCE(SUM(w.distance) FILTER (WHERE w.workout_type = 'running'), 0) AS run_miles,
	                (ARRAY_AGG(w.workout_id ORDER BY w.distance DESC))[1] AS workout_id
	           FROM workouts w WHERE w.user_id = $1 AND ${countedWorkoutSql("w")}
	          GROUP BY w.local_date
	       )
	       SELECT t.threshold::float8 AS threshold, to_char(x.local_date, 'YYYY-MM-DD') AS day,
	              x.miles::float8 AS miles, x.run_miles::float8 AS run_miles, x.workout_id
	         FROM unnest($2::float8[]) AS t(threshold)
	         LEFT JOIN LATERAL (
	           SELECT * FROM d WHERE d.miles >= t.threshold ORDER BY d.local_date LIMIT 1
	         ) x ON true`,
          [userId, dailyThresholds],
        ),
        [],
      )
    : Promise.resolve([]);

  // Pace: per medal, the qualifying mile — the triggering workout's best split
  // when it qualifies, else the fastest qualifying split from on/before the
  // award's day, else the fastest ever. Same split rules as computeAggregates.
  const paceRows = paceB
    .map((b) => ({ b, req: reqOf(b) }))
    .filter((p): p is { b: UserBadge; req: number } => p.req !== null);
  const paceP = paceRows.length
    ? safe(
        db.query<{
          badge_id: string;
          workout_id: string | null;
          day: string | null;
          pace: number | null;
          workout_type: string | null;
        }>(
          `WITH best AS MATERIALIZED (
	         SELECT w.workout_id, w.local_date, w.workout_type, MIN(s.split_pace) AS pace
	           FROM workout_splits s JOIN workouts w ON w.workout_id = s.workout_id
	          WHERE w.user_id = $1 AND s.split_pace >= ${MIN_PLAUSIBLE_MILE_SECONDS}
	            AND s.split_distance >= 0.95 AND ${countedWorkoutSql("w")}
	            AND s.split_pace <= $3::float8
	          GROUP BY w.workout_id, w.local_date, w.workout_type
	       )
	       SELECT r.badge_id, x.workout_id, to_char(x.local_date, 'YYYY-MM-DD') AS day,
	              x.pace::float8 AS pace, x.workout_type
	         FROM unnest($2::text[], $4::float8[], $5::text[], $6::timestamptz[]) AS r(badge_id, lim, trig, earned)
	         LEFT JOIN LATERAL (
	           SELECT * FROM best
	            WHERE best.pace <= r.lim
	            ORDER BY (best.workout_id = r.trig) DESC NULLS LAST,
	                     (best.local_date <= (r.earned AT TIME ZONE 'UTC')::date + 1) DESC,
	                     best.pace ASC, best.local_date ASC
	            LIMIT 1
	         ) x ON true`,
          [
            userId,
            paceRows.map((p) => p.b.badgeId),
            Math.max(...paceRows.map((p) => p.req)) * 60,
            paceRows.map((p) => p.req * 60),
            paceRows.map((p) => p.b.triggeringWorkoutId ?? null),
            paceRows.map((p) => p.b.earnedAt),
          ],
        ),
        [],
      )
    : Promise.resolve([]);

  // Holidays: the EARLIEST qualifying day per held holiday, same rule and
  // attribution as the award (holidayHitsAllHistory).
  const heldHolidays = new Set(
    holidayB.map((b) => holidayKeyFromBadgeId(b.badgeId)).filter((k): k is HolidayKey => k !== null),
  );
  const holidayP = heldHolidays.size
    ? safe(
        db.query<{ day: string; miles: number; run_miles: number; workout_id: string }>(
          `SELECT to_char(w.local_date, 'YYYY-MM-DD') AS day, SUM(w.distance)::float8 AS miles,
	              COALESCE(SUM(w.distance) FILTER (WHERE w.workout_type = 'running'), 0)::float8 AS run_miles,
	              (ARRAY_AGG(w.workout_id ORDER BY w.device_end_date DESC))[1] AS workout_id
	         FROM workouts w JOIN users u ON u.user_id = w.user_id
	        WHERE w.user_id = $1 AND w.local_date = ANY($2::date[]) AND ${countedWorkoutSql("w")}
	        GROUP BY w.local_date, u.goal_miles
	       HAVING ${holidayDayQualifiesSql("u", "w")}
	        ORDER BY w.local_date ASC`,
          [
            userId,
            holidayProbeDates()
              .filter((p) => heldHolidays.has(p.key))
              .map((p) => p.date),
          ],
        ),
        [],
      )
    : Promise.resolve([]);

  // Nth-completion days for the count medals whose history is kept.
  const challengeP = challengeB.length
    ? safe(
        db.query<{ day: string; workout_id: string | null }>(
          `SELECT to_char(local_date, 'YYYY-MM-DD') AS day, completing_workout_id AS workout_id
	         FROM user_challenge_completions WHERE user_id = $1
	        ORDER BY local_date ASC, completed_at ASC`,
          [userId],
        ),
        [],
      )
    : Promise.resolve([]);
  const weeklyP = weeklyB.length
    ? safe(
        db.query<{ week_start: string }>(
          `SELECT to_char(week_start, 'YYYY-MM-DD') AS week_start
	         FROM user_weekly_challenge_completions WHERE user_id = $1
	        ORDER BY week_start ASC`,
          [userId],
        ),
        [],
      )
    : Promise.resolve([]);

  // Ghost margin: the first win at/over each margin.
  const marginRows = marginB
    .map((b) => ({ b, req: reqOf(b) }))
    .filter((m): m is { b: UserBadge; req: number } => m.req !== null);
  const marginP = marginRows.length
    ? safe(
        db.query<{ threshold: number; day: string | null; margin: number | null; workout_id: string | null }>(
          `SELECT t.threshold::float8 AS threshold, to_char(x.local_date, 'YYYY-MM-DD') AS day,
	              x.ghost_margin_seconds::float8 AS margin, x.workout_id
	         FROM unnest($2::float8[]) AS t(threshold)
	         LEFT JOIN LATERAL (
	           SELECT w.local_date, w.ghost_margin_seconds, w.workout_id FROM workouts w
	            WHERE w.user_id = $1 AND w.deleted_at IS NULL AND w.ghost_margin_seconds >= t.threshold
	            ORDER BY w.local_date ASC, w.device_end_date ASC LIMIT 1
	         ) x ON true`,
          [userId, marginRows.map((m) => m.req)],
        ),
        [],
      )
    : Promise.resolve([]);

  const [tz, eras, milesR, dailyR, paceR, holidayR, challengeR, weeklyR, marginR] = await Promise.all([
    tzP,
    erasP,
    milesP,
    dailyP,
    paceP,
    holidayP,
    challengeP,
    weeklyP,
    marginP,
  ]);

  const earnedDay = new Map(tz.map((r) => [r.badge_id, r.day]));
  const milesAt = new Map(milesR.map((r) => [Number(r.threshold), r]));
  const dailyAt = new Map(dailyR.map((r) => [Number(r.threshold), r]));
  const paceFor = new Map(paceR.map((r) => [r.badge_id, r]));
  const marginAt = new Map(marginR.map((r) => [Number(r.threshold), r]));
  const holidayFirst = new Map<HolidayKey, (typeof holidayR)[number]>();
  for (const r of holidayR) {
    const key = holidayKeyForLocalDate(r.day);
    if (key && !holidayFirst.has(key)) holidayFirst.set(key, r);
  }

  /** The day the streak first reached `n` (earliest era long enough). */
  const streakDay = (n: number): string | null => {
    let best: string | null = null;
    for (const era of eras) {
      if (era.length < n) continue;
      const day = addDays(era.start_date, n - 1);
      const capped = day > era.end_date ? era.end_date : day;
      if (best === null || capped < best) best = capped;
    }
    return best;
  };

  const d = (
    b: UserBadge,
    sentence: string,
    fields: Partial<Omit<EarnedDetail, "summary">> = {},
  ): EarnedDetail => ({
    summary: speak(voice, sentence),
    date: fields.date ?? earnedDay.get(b.badgeId) ?? null,
    value: fields.value ?? null,
    unit: fields.unit ?? null,
    workout_id: fields.workout_id ?? null,
    ...(fields.value_seconds !== undefined ? { value_seconds: fields.value_seconds } : {}),
  });

  for (const b of badges) {
    const n = reqOf(b);
    const id = b.badgeId;
    let detail: EarnedDetail | null = null;
    try {
      switch (b.category) {
        case "streak":
          if (n !== null) {
            detail = d(b, `You reached a ${n}-day streak`, {
              date: streakDay(n) ?? undefined,
              value: String(n),
              unit: "days",
            });
          }
          break;
        case "miles":
          if (n !== null) {
            const r = milesAt.get(n);
            detail = d(b, `You passed ${n.toLocaleString("en-US")} lifetime miles`, {
              date: r?.day ?? undefined,
              value: String(n),
              unit: "mi",
            });
          }
          break;
        case "pace": {
          const r = paceFor.get(id);
          if (r && r.pace !== null) {
            const secs = Math.round(Number(r.pace));
            const mmss = formatMilePace(secs);
            const v = r.workout_type === "running" ? "ran" : "walked";
            // "an 8:05 mile", "an 11:40 mile" — the article follows the sound.
            const article = /^(8|11|18):/.test(mmss) ? "an" : "a";
            detail = d(b, `You ${v} ${article} ${mmss} mile`, {
              date: r.day ?? undefined,
              value: mmss,
              unit: "min/mi",
              workout_id: r.workout_id,
              value_seconds: secs,
            });
          } else if (n !== null) {
            detail = d(b, `You ran a sub-${n}:00 mile`, { unit: "min/mi" });
          }
          break;
        }
        case "daily_distance":
          if (n !== null) {
            const r = dailyAt.get(n);
            if (r && r.miles !== null) {
              detail = d(
                b,
                `You ${verb(Number(r.run_miles ?? 0), Number(r.miles))} ${miles1(Number(r.miles))} mi in one day`,
                { date: r.day ?? undefined, value: miles1(Number(r.miles)), unit: "mi", workout_id: r.workout_id },
              );
            } else {
              detail = d(b, `You covered ${n} mi in one day`, { value: String(n), unit: "mi" });
            }
          }
          break;
        case "holiday": {
          const key = holidayKeyFromBadgeId(id);
          const h = HOLIDAYS.find((x) => x.key === key);
          const r = key ? holidayFirst.get(key) : undefined;
          if (h && r) {
            const miles = Number(r.miles);
            detail = d(
              b,
              `You ${verb(Number(r.run_miles), miles)} ${miles1(miles)} mi on ${h.holidayName} ${r.day.slice(0, 4)}`,
              { date: r.day, value: miles1(miles), unit: "mi", workout_id: r.workout_id },
            );
          } else if (h) {
            detail = d(b, `You got your mile in on ${h.holidayName}`);
          }
          break;
        }
        case "special":
          if (id === "special_first_mile") {
            const r = milesAt.get(1);
            detail = d(b, "You walked your first mile", { date: r?.day ?? undefined, value: "1", unit: "mi" });
          } else if (id === "special_first_week") {
            detail = d(b, "A full week of miles", { date: streakDay(7) ?? undefined, value: "7", unit: "days" });
          }
          break;
        case "challenge":
          if (n !== null) {
            const r = challengeR[n - 1];
            detail = d(
              b,
              n === 1 ? "You completed your first daily challenge" : `You completed your ${ordinal(n)} daily challenge`,
              { date: r?.day ?? undefined, value: String(n), unit: "challenges", workout_id: r?.workout_id ?? null },
            );
          }
          break;
        case "weekly_challenge":
          if (n !== null) {
            if (id.startsWith("weekly_streak_")) {
              detail = d(b, `You completed ${n} weekly challenges in a row`, { value: String(n), unit: "weeks" });
            } else {
              const r = weeklyR[n - 1];
              detail = d(
                b,
                n === 1 ? "You completed your first weekly challenge" : `You completed your ${ordinal(n)} weekly challenge`,
                { date: r ? addDays(r.week_start, 6) : undefined, value: String(n), unit: "challenges" },
              );
            }
          }
          break;
        case "story":
          if (n !== null) {
            detail = d(b, n === 1 ? "You shared your first story" : `You shared ${n} stories`, {
              value: String(n),
              unit: plural(n, "story", "stories"),
            });
          }
          break;
        case "hype":
          if (n !== null) {
            detail = d(b, n === 1 ? "You hyped a friend for the first time" : `You hyped friends ${n} times`, {
              value: String(n),
              unit: plural(n, "hype", "hypes"),
            });
          }
          break;
        case "nudge":
          if (n !== null) {
            detail = d(b, n === 1 ? "You sent your first nudge" : `You sent ${n} nudges`, {
              value: String(n),
              unit: plural(n, "nudge", "nudges"),
            });
          }
          break;
        case "competition":
          if (n !== null) {
            const unit = plural(n, "competition", "competitions");
            const sentence = id.startsWith("comp_started_")
              ? n === 1
                ? "You started your first competition"
                : `You started ${n} competitions`
              : id.startsWith("comp_won_")
                ? n === 1
                  ? "You won your first competition"
                  : `You won ${n} competitions`
                : n === 1
                  ? "You joined your first competition"
                  : `You joined ${n} competitions`;
            detail = d(b, sentence, { value: String(n), unit });
          }
          break;
        case "buddy":
          if (n !== null) {
            if (id.startsWith("buddy_crew_")) {
              detail = d(b, `You walked with ${n} different friends`, { value: String(n), unit: "friends" });
            } else if (id.startsWith("buddy_won_")) {
              detail = d(b, n === 1 ? "You won your first buddy walk" : `You won ${n} buddy walks`, {
                value: String(n),
                unit: plural(n, "walk", "walks"),
              });
            } else {
              detail = d(b, n === 1 ? "You finished your first buddy walk" : `You finished ${n} buddy walks`, {
                value: String(n),
                unit: plural(n, "walk", "walks"),
              });
            }
          }
          break;
        case "ghost":
          if (n !== null) {
            if (id.startsWith("ghost_margin_")) {
              const r = marginAt.get(n);
              const secs = r?.margin != null ? Math.floor(Number(r.margin)) : n;
              const pretty = secs >= 60 ? formatMilePace(secs) : `${secs}s`;
              detail = d(b, `You beat a ghost by ${pretty}`, {
                date: r?.day ?? undefined,
                value: String(secs),
                unit: "sec",
                workout_id: r?.workout_id ?? null,
              });
            } else {
              detail = d(b, n === 1 ? "You beat your first ghost" : `You beat ${n} ghosts`, {
                value: String(n),
                unit: plural(n, "ghost", "ghosts"),
              });
            }
          }
          break;
        default:
          detail = null;
      }
    } catch (e: any) {
      console.error("[badges] earned_detail failed for", id, e?.message ?? e);
      detail = null;
    }
    out.set(id, detail);
  }
  return out;
}
