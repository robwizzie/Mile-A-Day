import type { PoolClient } from "pg";
import { PostgresService } from "../DbService.js";
import {
  MAX_PLAUSIBLE_MILE_SECONDS,
  countedWorkoutSql,
  realMileSplitSql,
} from "../mileTime.js";
import { displayMovingSecondsSql } from "../posts/postSql.js";
import {
  ACTIONS,
  Action,
  ActionContext,
  ActionError,
  Change,
  Checkpoint,
  Completed,
  DaySummary,
  EASE_PACE,
  EASE_VOLUME,
  EFFORT,
  Effort,
  Feeling,
  Fitness,
  Goal,
  PlanSettings,
  RunSample,
  StoredDay,
  WeekContext,
  addDays,
  checkinAction,
  completionOf,
  computeAdaptation,
  computeCheckpoints,
  computeFitness,
  dayStatus,
  generateWeek,
  hardDaysFor,
  hardDaysWarning,
  isHard,
  longRunCap,
  pacesForWeek,
  planAction,
  planMissedMoves,
  runPace,
  sameDay,
  scaleDistance,
  scalePaces,
  toSummary,
  validateChanges,
  walkFraction,
  weekIndex,
  weekStart,
  weekdayName,
} from "./engine.js";
import {
  CoachConnectionStatus,
  coachConnectionStatus,
} from "./coachConnection.js";

/**
 * Run Plans service: the DB side of the rules engine (`engine.ts`).
 *
 * Every function is scoped to ONE user (the caller's token: the app's JWT or
 * the coach MCP token) and takes the client's LOCAL `today`. Entitlement
 * (Plus) is checked by the caller — the routes gate on `isPlusActive`, and the
 * coach MCP checks it on every request — never here.
 */

const db = PostgresService.getInstance();

export class RunPlanError extends Error {
  constructor(
    public code: string,
    public status: number,
    public extra: Record<string, unknown> = {},
  ) {
    super(code);
  }
}

export type ProposalSource = "flamey" | "claude" | "engine";
export type DaySource = StoredDay["source"];

// ─── Runs / fitness ─────────────────────────────────────────────────────

const MAX_RANGE_DAYS = 120;

async function loadRuns(
  userId: string,
  from: string,
  to: string,
  opts: { runningOnly: boolean; limit?: number; newestFirst?: boolean } = {
    runningOnly: true,
  },
): Promise<RunSample[]> {
  const rows = await db.query<{
    workout_id: string;
    local_date: string;
    workout_type: string;
    distance: number;
    total_duration: number;
    moving_s: number | null;
    is_indoor: boolean | null;
  }>(
    `SELECT w.workout_id, w.local_date::text AS local_date, w.workout_type,
            w.distance, w.total_duration, ${displayMovingSecondsSql("w")} AS moving_s,
            w.is_indoor
       FROM workouts w
      WHERE w.user_id = $1 AND w.local_date BETWEEN $2::date AND $3::date
        AND ${countedWorkoutSql("w")}
        ${opts.runningOnly ? "AND w.workout_type = 'running'" : ""}
      ORDER BY w.local_date ${opts.newestFirst ? "DESC" : "ASC"}, w.device_end_date ${opts.newestFirst ? "DESC" : "ASC"}
      LIMIT $4`,
    [userId, from, to, opts.limit ?? 500],
  );
  if (!rows.length) return [];
  const splits = await db.query<{
    workout_id: string;
    split_number: number;
    split_distance: number | null;
    split_duration: number;
    split_pace: number | null;
  }>(
    `SELECT workout_id, split_number, split_distance, split_duration, split_pace
       FROM workout_splits WHERE workout_id = ANY($1) ORDER BY workout_id, split_number`,
    [rows.map((r) => r.workout_id)],
  );
  const byWorkout = new Map<string, RunSample["splits"]>();
  for (const s of splits) {
    const list = byWorkout.get(s.workout_id) ?? [];
    list.push({
      n: s.split_number,
      distance_mi: s.split_distance != null ? Number(s.split_distance) : null,
      duration_s: Number(s.split_duration),
      pace_s: s.split_pace != null ? Number(s.split_pace) : null,
    });
    byWorkout.set(s.workout_id, list);
  }
  return rows.map((r) => ({
    workout_id: r.workout_id,
    local_date: r.local_date,
    workout_type: r.workout_type,
    distance_mi: Number(r.distance),
    duration_s: Number(r.total_duration),
    moving_s: r.moving_s != null ? Number(r.moving_s) : null,
    is_indoor: r.is_indoor,
    splits: byWorkout.get(r.workout_id) ?? [],
  }));
}

/** Baseline fitness from the user's counted RUNNING workouts. Works without a plan. */
export async function getFitness(userId: string, today: string): Promise<Fitness> {
  const mileSplitWhere = `w.user_id = $1 AND w.workout_type = 'running' AND ${countedWorkoutSql("w")}
          AND w.local_date <= $2::date
          AND ws.split_distance >= 0.95
          AND ${realMileSplitSql("ws.split_pace")}
          AND ws.split_pace <= ${MAX_PLAUSIBLE_MILE_SECONDS}`;
  const [miles, bestMile, fiveK, counts, recent] = await Promise.all([
    db.query<{ best_all: number | null; best_90: number | null }>(
      `SELECT MIN(ws.split_pace) AS best_all,
              MIN(ws.split_pace) FILTER (WHERE w.local_date >= $2::date - 89) AS best_90
         FROM workouts w
         JOIN workout_splits ws ON ws.workout_id = w.workout_id
        WHERE ${mileSplitWhere}`,
      [userId, today],
    ),
    db.query<{ local_date: string; is_indoor: boolean | null }>(
      `SELECT w.local_date::text AS local_date, w.is_indoor
         FROM workouts w
         JOIN workout_splits ws ON ws.workout_id = w.workout_id
        WHERE ${mileSplitWhere}
        ORDER BY ws.split_pace, w.local_date LIMIT 1`,
      [userId, today],
    ),
    // Best ~5K effort: 3.0–3.5 mi runs, Riegel-normalized to 5K.
    db.query<{ best: number | null }>(
      `SELECT MIN(t * power(3.10686 / distance, 1.06)) AS best
         FROM (SELECT w.distance, COALESCE(${displayMovingSecondsSql("w")}, w.total_duration) AS t
                 FROM workouts w
                WHERE w.user_id = $1 AND w.workout_type = 'running' AND ${countedWorkoutSql("w")}
                  AND w.local_date BETWEEN $2::date - 89 AND $2::date
                  AND w.distance BETWEEN 3.0 AND 3.5) x
        WHERE t / distance >= 241`,
      [userId, today],
    ),
    db.query<{ n90: number; w0: number; w1: number; w2: number; w3: number }>(
      `SELECT COUNT(*)::int AS n90,
              COALESCE(SUM(distance) FILTER (WHERE $2::date - local_date BETWEEN 0 AND 6), 0)::float8 AS w0,
              COALESCE(SUM(distance) FILTER (WHERE $2::date - local_date BETWEEN 7 AND 13), 0)::float8 AS w1,
              COALESCE(SUM(distance) FILTER (WHERE $2::date - local_date BETWEEN 14 AND 20), 0)::float8 AS w2,
              COALESCE(SUM(distance) FILTER (WHERE $2::date - local_date BETWEEN 21 AND 27), 0)::float8 AS w3
         FROM workouts w
        WHERE w.user_id = $1 AND w.workout_type = 'running' AND ${countedWorkoutSql("w")}
          AND w.local_date BETWEEN $2::date - 89 AND $2::date`,
      [userId, today],
    ),
    loadRuns(userId, addDays(today, -55), today, { runningOnly: true, limit: 300 }),
  ]);
  const c = counts[0];
  return computeFitness({
    as_of: today,
    best_mile_s: miles[0]?.best_all != null ? Number(miles[0].best_all) : null,
    best_mile_date: bestMile[0]?.local_date ?? null,
    best_mile_indoor: bestMile[0]?.is_indoor ?? null,
    best_mile_90d_s: miles[0]?.best_90 != null ? Number(miles[0].best_90) : null,
    best_5k_s: fiveK[0]?.best != null ? Number(fiveK[0].best) : null,
    run_count_90d: c?.n90 ?? 0,
    weekly_miles: [c?.w3 ?? 0, c?.w2 ?? 0, c?.w1 ?? 0, c?.w0 ?? 0].map(Number),
    recent_runs: recent,
  });
}

export interface ServedRun {
  workout_id: string;
  local_date: string;
  type: string;
  distance_mi: number;
  duration_s: number;
  moving_s: number | null;
  avg_pace_s: number | null;
  walk_fraction: number;
  is_indoor: boolean | null;
  /** = moving_s / is_indoor (the names the app reads). */
  moving_seconds: number | null;
  indoor: boolean | null;
  splits: { n: number; distance_mi: number | null; duration_s: number; pace_s: number | null }[];
}

function serveRun(r: RunSample): ServedRun {
  const pace = runPace(r);
  return {
    workout_id: r.workout_id,
    local_date: r.local_date,
    type: r.workout_type,
    distance_mi: Math.round(r.distance_mi * 100) / 100,
    duration_s: Math.round(r.duration_s),
    moving_s: r.moving_s != null ? Math.round(r.moving_s) : null,
    avg_pace_s: pace != null ? Math.round(pace) : null,
    walk_fraction: walkFraction(r),
    is_indoor: r.is_indoor,
    moving_seconds: r.moving_s != null ? Math.round(r.moving_s) : null,
    indoor: r.is_indoor,
    splits: r.splits.map((s) => ({
      n: s.n,
      distance_mi: s.distance_mi != null ? Math.round(s.distance_mi * 100) / 100 : null,
      duration_s: Math.round(s.duration_s),
      pace_s: s.pace_s != null ? Math.round(s.pace_s) : null,
    })),
  };
}

/**
 * Runs in [from, to] (≤ 120 days) with splits, avg pace, moving time, walk
 * fraction and the indoor flag. `includeWalks` adds walking workouts.
 */
export async function getRuns(
  userId: string,
  from: string,
  to: string,
  opts: { includeWalks?: boolean } = {},
): Promise<ServedRun[]> {
  if (from > to) [from, to] = [to, from];
  if (Math.round((Date.parse(to) - Date.parse(from)) / 86_400_000) > MAX_RANGE_DAYS) {
    throw new RunPlanError("range_too_large", 400, { max_days: MAX_RANGE_DAYS });
  }
  const runs = await loadRuns(userId, from, to, { runningOnly: !opts.includeWalks });
  return runs.map(serveRun);
}

async function recentRuns(userId: string, today: string): Promise<ServedRun[]> {
  const runs = await loadRuns(userId, addDays(today, -365), today, {
    runningOnly: true,
    limit: 7,
    newestFirst: true,
  });
  return runs.map(serveRun);
}

// ─── Plan rows ────────────────────────────────────────────────────────────

interface PlanRow {
  plan_id: string;
  user_id: string;
  status: string;
  goals: Goal[];
  effort: Effort;
  hard_days: number | null;
  run_daily_mile: boolean;
  finish_by: string | null;
  start_date: string;
  baseline: Fitness;
  claude_auto_apply: boolean;
  created_at: string;
  updated_at: string;
  archived_at: string | null;
}

const PLAN_COLUMNS = `plan_id, user_id, status, goals, effort, hard_days, run_daily_mile,
  finish_by::text AS finish_by, start_date::text AS start_date, baseline,
  claude_auto_apply, created_at, updated_at, archived_at`;

async function activePlan(userId: string): Promise<PlanRow | null> {
  const rows = await db.query<PlanRow>(
    `SELECT ${PLAN_COLUMNS} FROM run_plans WHERE user_id = $1 AND status = 'active'`,
    [userId],
  );
  return rows[0] ?? null;
}

async function requirePlan(userId: string): Promise<PlanRow> {
  const p = await activePlan(userId);
  if (!p) throw new RunPlanError("no_active_plan", 404);
  return p;
}

function settingsOf(p: PlanRow): PlanSettings {
  return {
    goals: p.goals,
    effort: p.effort,
    hard_days: p.hard_days,
    run_daily_mile: p.run_daily_mile,
    finish_by: p.finish_by,
    start_date: p.start_date,
    baseline: p.baseline,
  };
}

interface DayRow {
  local_date: string;
  kind: StoredDay["kind"];
  title: string;
  distance_mi: number;
  segments: StoredDay["segments"];
  note: string | null;
  source: DaySource;
  original: DaySummary | null;
  moved_from: string | null;
}

async function loadDays(planId: string, from: string, to: string): Promise<StoredDay[]> {
  const rows = await db.query<DayRow>(
    `SELECT local_date::text AS local_date, kind, title, distance_mi::float8 AS distance_mi,
            segments, note, source, original, moved_from::text AS moved_from
       FROM run_plan_days
      WHERE plan_id = $1 AND local_date BETWEEN $2::date AND $3::date
      ORDER BY local_date`,
    [planId, from, to],
  );
  return rows.map((r) => ({
    ...r,
    distance_mi: Number(r.distance_mi),
    target_pace_s: targetPace(r.segments),
  }));
}

function targetPace(segs: StoredDay["segments"]): number | null {
  const work = segs.find((s) => s.kind === "work" && s.distance_mi && s.target_pace_s);
  if (work) return work.target_pace_s ?? null;
  return segs.find((s) => s.kind === "steady" && s.target_pace_s)?.target_pace_s ?? null;
}

async function insertDays(planId: string, days: { local_date: string; day: DaySummary }[]) {
  if (!days.length) return;
  await db.query(
    `INSERT INTO run_plan_days (plan_id, local_date, kind, title, distance_mi, segments, note, source)
     SELECT $1::uuid, d.local_date, d.kind, d.title, d.distance_mi, d.segments, d.note, 'engine'
       FROM jsonb_to_recordset($2::jsonb)
         AS d(local_date date, kind text, title text, distance_mi numeric, segments jsonb, note text)
     ON CONFLICT (plan_id, local_date) DO NOTHING`,
    [
      planId,
      JSON.stringify(
        days.map((d) => ({
          local_date: d.local_date,
          kind: d.day.kind,
          title: d.day.title,
          distance_mi: d.day.distance_mi,
          segments: d.day.segments,
          note: d.day.note,
        })),
      ),
    ],
  );
}

// ─── Plan state (horizon + statuses + missed moves) ───────────────────────

interface PlanState {
  plan: PlanRow;
  settings: PlanSettings;
  fitness: Fitness;
  checkpoints: Checkpoint[];
  weekCtx: WeekContext;
  hardDays: number;
  /** Days loaded for the window, with derived status + completion. */
  days: (StoredDay & { completed: Completed | null })[];
  today: string;
}

/**
 * Materialize the horizon (current + next week), derive statuses from the
 * user's counted workouts, and move missed hard days. Loads [from, to] (the
 * horizon by default, plus two weeks back for adaptation).
 */
async function planState(
  plan: PlanRow,
  today: string,
  range?: { from: string; to: string },
): Promise<PlanState> {
  const fitness = await getFitness(plan.user_id, today);
  const settings = settingsOf(plan);
  const checkpoints = computeCheckpoints({
    goals: settings.goals,
    effort: settings.effort,
    start_date: settings.start_date,
    finish_by: settings.finish_by,
    fitness,
    baseline: settings.baseline,
  });
  const weekCtx: WeekContext = { settings, fitness, checkpoints };
  const hardDays = hardDaysFor(settings.effort, settings.hard_days);

  // Horizon: this week + next week, rolled forward on read.
  const monday = weekStart(today);
  const horizonEnd = addDays(monday, 13);
  const existing = new Set(
    (
      await db.query<{ d: string }>(
        `SELECT local_date::text AS d FROM run_plan_days
          WHERE plan_id = $1 AND local_date BETWEEN $2::date AND $3::date`,
        [plan.plan_id, monday, horizonEnd],
      )
    ).map((r) => r.d),
  );
  const missing: { local_date: string; day: DaySummary }[] = [];
  for (const wk of [monday, addDays(monday, 7)]) {
    const dates = [...Array(7).keys()].map((i) => addDays(wk, i));
    if (dates.every((d) => existing.has(d) || d < settings.start_date)) continue;
    for (const d of generateWeek(weekCtx, wk)) {
      if (d.local_date >= settings.start_date && !existing.has(d.local_date)) missing.push(d);
    }
  }
  await insertDays(plan.plan_id, missing);

  const from = [range?.from ?? addDays(monday, -14), settings.start_date].sort().reverse()[0];
  const to = range?.to ?? horizonEnd;
  const stored = await loadDays(plan.plan_id, from, to);
  const runs = from <= today
    ? await loadRuns(plan.user_id, from, today < to ? today : to, { runningOnly: false })
    : [];
  const byDate = new Map<string, RunSample[]>();
  for (const r of runs) byDate.set(r.local_date, [...(byDate.get(r.local_date) ?? []), r]);

  const withStatus = () =>
    stored.map((d) => {
      const completed = d.local_date <= today ? completionOf(byDate.get(d.local_date) ?? []) : null;
      return { ...d, completed, status: dayStatus(d.kind, d.distance_mi, d.local_date, today, completed) };
    });
  let days = withStatus();

  // Missed hard days move to the next free non-hard day this week.
  const moves = planMissedMoves(days, today, hardDays);
  for (const m of moves) {
    const src = days.find((d) => d.local_date === m.from)!;
    const dst = days.find((d) => d.local_date === m.to)!;
    const note = `Moved from ${weekdayName(m.from)}, which was missed.`;
    await db.query(
      `UPDATE run_plan_days
          SET kind = $3, title = $4, distance_mi = $5, segments = $6::jsonb, note = $7,
              moved_from = $8::date, original = COALESCE(original, $9::jsonb), updated_at = now()
        WHERE plan_id = $1 AND local_date = $2::date AND source = 'engine' AND moved_from IS NULL
          AND NOT EXISTS (SELECT 1 FROM run_plan_days x WHERE x.plan_id = $1 AND x.moved_from = $8::date)`,
      [plan.plan_id, m.to, src.kind, src.title, src.distance_mi, JSON.stringify(src.segments), note, m.from, JSON.stringify(toSummary(dst))],
    );
    const idx = stored.findIndex((d) => d.local_date === m.to);
    stored[idx] = {
      ...stored[idx],
      kind: src.kind,
      title: src.title,
      distance_mi: src.distance_mi,
      segments: src.segments,
      target_pace_s: src.target_pace_s,
      note,
      moved_from: m.from,
      original: stored[idx].original ?? toSummary(dst),
    };
  }
  if (moves.length) days = withStatus();

  return { plan, settings, fitness, checkpoints, weekCtx, hardDays, days, today };
}

function actionContext(st: PlanState, source: ActionContext["source"]): ActionContext {
  return {
    today: st.today,
    days: st.days,
    hard_days: st.hardDays,
    run_daily_mile: st.settings.run_daily_mile,
    effort: st.settings.effort,
    long_cap: longRunCap(st.fitness),
    paces: pacesForWeek(st.weekCtx, Math.max(0, weekIndex(st.settings.start_date, st.today))),
    source,
  };
}

// ─── Serving ──────────────────────────────────────────────────────────────

export interface ServedDay {
  local_date: string;
  kind: string;
  title: string;
  distance_mi: number;
  segments: DaySummary["segments"];
  target_pace_s: number | null;
  note: string | null;
  status: string;
  moved: boolean;
  source: DaySource;
  completed: Completed | null;
  /** Additive: true when performance adaptation changed this day on read. */
  adapted: boolean;
}

/** Served days in [from, to] with performance adaptation applied (on read). */
function serveDays(st: PlanState, from: string, to: string): ServedDay[] {
  const today = st.today;
  const hardSessions = st.days
    .filter((d) => isHard(d.kind) && (d.local_date < today || (d.local_date === today && d.status === "done")))
    .map((d) => ({ local_date: d.local_date, segments: d.segments, completed: d.completed, status: d.status! }));
  const adapt = computeAdaptation(hardSessions);
  const upcomingHard = st.days.filter(
    (d) => isHard(d.kind) && d.local_date >= today && d.status !== "done" && d.source === "engine",
  );
  const easeDate = adapt.ease ? upcomingHard.find((d) => d.local_date > adapt.ease!.after)?.local_date : undefined;
  const movedTo = new Map(st.days.filter((d) => d.moved_from).map((d) => [d.moved_from!, d.local_date]));
  const thisWeek = weekStart(today);

  return st.days
    .filter((d) => d.local_date >= from && d.local_date <= to)
    .map((d) => {
      let day: DaySummary = toSummary(d);
      let adapted = false;
      if (d.local_date === easeDate) {
        day = { ...scalePaces(scaleDistance(day, EASE_VOLUME, st.settings.run_daily_mile), EASE_PACE), note: adapt.ease!.note };
        adapted = true;
      } else if (adapt.tighten && upcomingHard.some((u) => u.local_date === d.local_date)) {
        day = { ...scalePaces(day, adapt.tighten.factor), note: adapt.tighten.note };
        adapted = true;
      }
      let note = day.note;
      if (d.status === "missed" && isHard(d.kind)) {
        const to = movedTo.get(d.local_date);
        if (to) note = `Missed. Moved to ${weekdayName(to)}.`;
        else if (weekStart(d.local_date) === thisWeek) note = "Missed. No room to move it this week without stacking hard days, so it's dropped.";
      }
      return {
        local_date: d.local_date,
        kind: day.kind,
        title: day.title,
        distance_mi: day.distance_mi,
        segments: day.segments,
        target_pace_s: day.target_pace_s,
        note,
        status: d.status!,
        moved: d.moved_from != null,
        source: d.source,
        completed: d.completed,
        adapted,
      };
    });
}

export interface ServedPlan {
  id: string;
  status: string;
  goals: Goal[];
  effort: Effort;
  effort_label: string;
  hard_days: number | null;
  hard_days_effective: number;
  run_daily_mile: boolean;
  finish_by: string | null;
  start_date: string;
  /** 1-based week of the plan that `today` falls in. */
  week: number;
  baseline: Fitness;
  paces: ReturnType<typeof pacesForWeek>;
  long_run_cap_mi: number;
  claude_auto_apply: boolean;
  created_at: string;
  updated_at: string;
}

export interface ServedProposal {
  id: string;
  source: ProposalSource;
  action: string;
  summary: string;
  rationale: string | null;
  changes: Change[];
  cap_note: string | null;
  status: string;
  created_at: string;
  decided_at: string | null;
}

export interface CurrentPlanResponse {
  plan: ServedPlan | null;
  days: ServedDay[];
  /** Today's Day (null without a plan). */
  today: ServedDay | null;
  today_date: string;
  week_total_mi: number;
  week_done_mi: number;
  checkpoints: Checkpoint[];
  pending_proposals: ServedProposal[];
  recent_runs: ServedRun[];
  claude: CoachConnectionStatus;
  warning: string | null;
  /** Today's most recent check-in on this plan, or null. */
  latest_checkin: ServedCheckin | null;
  cap_note?: string | null;
}

function servePlan(st: PlanState): ServedPlan {
  const p = st.plan;
  return {
    id: p.plan_id,
    status: p.status,
    goals: p.goals,
    effort: p.effort,
    effort_label: EFFORT[p.effort].label,
    hard_days: p.hard_days,
    hard_days_effective: st.hardDays,
    run_daily_mile: p.run_daily_mile,
    finish_by: p.finish_by,
    start_date: p.start_date,
    week: Math.max(0, weekIndex(p.start_date, st.today)) + 1,
    baseline: p.baseline,
    paces: pacesForWeek(st.weekCtx, Math.max(0, weekIndex(p.start_date, st.today))),
    long_run_cap_mi: longRunCap(st.fitness),
    claude_auto_apply: p.claude_auto_apply,
    created_at: p.created_at,
    updated_at: p.updated_at,
  };
}

interface ProposalRow {
  id: string;
  source: ProposalSource;
  action: string;
  summary: string;
  rationale: string | null;
  changes: Change[];
  cap_note: string | null;
  status: string;
  created_at: string;
  decided_at: string | null;
}
const PROPOSAL_COLUMNS = `id, source, action, summary, rationale, changes, cap_note, status, created_at, decided_at`;
const serveProposal = (r: ProposalRow): ServedProposal => ({ ...r });

/** Pending proposals that no longer fit the plan (past day, day changed) expire. */
async function expireStale(st: PlanState) {
  const pending = await db.query<ProposalRow>(
    `SELECT ${PROPOSAL_COLUMNS} FROM run_plan_proposals WHERE plan_id = $1 AND status = 'pending'`,
    [st.plan.plan_id],
  );
  const stale = pending.filter((p) => staleReason(st, p.changes) != null).map((p) => p.id);
  if (stale.length) {
    await db.query(
      `UPDATE run_plan_proposals SET status = 'expired', decided_at = now()
        WHERE id = ANY($1::uuid[]) AND status = 'pending'`,
      [stale],
    );
  }
}

function staleReason(st: PlanState, changes: Change[]): string | null {
  for (const c of changes) {
    if (c.local_date < st.today) return "past";
    const d = st.days.find((x) => x.local_date === c.local_date);
    if (!d || !sameDay(d, c.before)) return "changed";
  }
  return null;
}

async function buildCurrent(userId: string, today: string, plan?: PlanRow | null): Promise<CurrentPlanResponse> {
  const p = plan === undefined ? await activePlan(userId) : plan;
  const [claude, recent_runs] = await Promise.all([coachConnectionStatus(userId), recentRuns(userId, today)]);
  if (!p) {
    return { plan: null, days: [], today: null, today_date: today, week_total_mi: 0, week_done_mi: 0, checkpoints: [], pending_proposals: [], recent_runs, claude, warning: null, latest_checkin: null };
  }
  const st = await planState(p, today);
  await expireStale(st);
  const pending = await db.query<ProposalRow>(
    `SELECT ${PROPOSAL_COLUMNS} FROM run_plan_proposals
      WHERE plan_id = $1 AND status = 'pending' ORDER BY created_at DESC LIMIT 20`,
    [p.plan_id],
  );
  const latest = await db.query<ServedCheckin>(
    `SELECT id, plan_id, local_date::text AS local_date, feeling, message, pain_flag, created_at
       FROM run_plan_checkins WHERE plan_id = $1 AND local_date = $2::date
      ORDER BY created_at DESC LIMIT 1`,
    [p.plan_id, today],
  );
  const monday = weekStart(today);
  const days = serveDays(st, monday, addDays(monday, 13));
  const week = days.filter((d) => d.local_date <= addDays(monday, 6));
  const r2 = (n: number) => Math.round(n * 100) / 100;
  return {
    plan: servePlan(st),
    days,
    today: days.find((d) => d.local_date === today) ?? null,
    today_date: today,
    week_total_mi: r2(week.reduce((a, d) => a + d.distance_mi, 0)),
    week_done_mi: r2(week.reduce((a, d) => a + (d.completed?.distance_mi ?? 0), 0)),
    checkpoints: st.checkpoints,
    pending_proposals: pending.map(serveProposal),
    recent_runs,
    claude,
    warning: hardDaysWarning(st.hardDays),
    latest_checkin: latest[0] ?? null,
  };
}

// ─── Public API ───────────────────────────────────────────────────────────

/** GET /run-plans/current — plan (or null), horizon days, checkpoints, pending proposals. */
export async function getCurrentPlan(userId: string, today: string): Promise<CurrentPlanResponse> {
  return buildCurrent(userId, today);
}

/** Served plan days in [from, to] (≤ 62 days; only materialized days exist). */
export async function getPlanDays(userId: string, from: string, to: string, today: string): Promise<ServedDay[]> {
  if (from > to) [from, to] = [to, from];
  if (Math.round((Date.parse(to) - Date.parse(from)) / 86_400_000) > 62) {
    throw new RunPlanError("range_too_large", 400, { max_days: 62 });
  }
  const plan = await requirePlan(userId);
  const monday = weekStart(today);
  const st = await planState(plan, today, {
    from: from < addDays(monday, -14) ? from : addDays(monday, -14),
    to: to > addDays(monday, 13) ? to : addDays(monday, 13),
  });
  return serveDays(st, from, to);
}

export interface CreatePlanInput {
  goals: Goal[];
  effort: Effort;
  hard_days?: number | null;
  finish_by?: string | null;
  run_daily_mile: boolean;
}

/** POST /run-plans — archives any active plan, builds a new one from today. */
export async function createPlan(userId: string, input: CreatePlanInput, today: string): Promise<CurrentPlanResponse> {
  const baseline = await getFitness(userId, today);
  try {
    await inTransaction(async (client) => {
      await client.query(
        `UPDATE run_plans SET status = 'archived', archived_at = now(), updated_at = now()
          WHERE user_id = $1 AND status = 'active'`,
        [userId],
      );
      await client.query(
        `INSERT INTO run_plans (user_id, goals, effort, hard_days, run_daily_mile, finish_by, start_date, baseline)
         VALUES ($1, $2::jsonb, $3, $4, $5, $6::date, $7::date, $8::jsonb)`,
        [userId, JSON.stringify(input.goals), input.effort, input.hard_days ?? null, input.run_daily_mile, input.finish_by ?? null, today, JSON.stringify(baseline)],
      );
    });
  } catch (e: any) {
    if (e?.code === "23505") throw new RunPlanError("plan_conflict", 409);
    throw e;
  }
  return buildCurrent(userId, today);
}

export interface UpdatePlanInput {
  effort?: Effort;
  hard_days?: number | null;
  run_daily_mile?: boolean;
  claude_auto_apply?: boolean;
  goals?: Goal[];
  finish_by?: string | null;
}

/** PATCH /run-plans/current — regenerates future engine-owned days when the shape changed. */
export async function updatePlan(userId: string, patch: UpdatePlanInput, today: string): Promise<CurrentPlanResponse> {
  const plan = await requirePlan(userId);
  const sets: string[] = [];
  const params: unknown[] = [plan.plan_id];
  const set = (col: string, val: unknown, cast = "") => {
    params.push(val);
    sets.push(`${col} = $${params.length}${cast}`);
  };
  if (patch.effort !== undefined) set("effort", patch.effort);
  if (patch.hard_days !== undefined) set("hard_days", patch.hard_days);
  if (patch.run_daily_mile !== undefined) set("run_daily_mile", patch.run_daily_mile);
  if (patch.claude_auto_apply !== undefined) set("claude_auto_apply", patch.claude_auto_apply);
  if (patch.goals !== undefined) set("goals", JSON.stringify(patch.goals), "::jsonb");
  if (patch.finish_by !== undefined) set("finish_by", patch.finish_by, "::date");
  if (!sets.length) return buildCurrent(userId, today, plan);
  await db.query(`UPDATE run_plans SET ${sets.join(", ")}, updated_at = now() WHERE plan_id = $1`, params);

  const reshape = (["effort", "hard_days", "run_daily_mile", "goals", "finish_by"] as const).some((k) => patch[k] !== undefined);
  if (reshape) {
    // Future engine-owned days regenerate; today's too unless it already has miles.
    const ranToday = (await loadRuns(userId, today, today, { runningOnly: false, limit: 1 })).length > 0;
    await db.query(
      `DELETE FROM run_plan_days
        WHERE plan_id = $1 AND source = 'engine' AND moved_from IS NULL
          AND (local_date > $2::date OR (local_date = $2::date AND NOT $3::boolean))`,
      [plan.plan_id, today, ranToday],
    );
  }
  return buildCurrent(userId, today);
}

/** DELETE /run-plans/current */
export async function archivePlan(userId: string): Promise<{ ok: true; archived: boolean }> {
  const rows = await db.query(
    `UPDATE run_plans SET status = 'archived', archived_at = now(), updated_at = now()
      WHERE user_id = $1 AND status = 'active' RETURNING plan_id`,
    [userId],
  );
  return { ok: true, archived: rows.length > 0 };
}

export interface ProposalInput {
  action: Action;
  params?: Record<string, unknown>;
  summary?: string | null;
  rationale?: string | null;
}

function planOrThrow(ctx: ActionContext, action: Action, params: Record<string, unknown>) {
  try {
    return planAction(ctx, action, params);
  } catch (e) {
    if (e instanceof ActionError) throw new RunPlanError("action_not_possible", 422, { cap_note: e.cap_note });
    throw e;
  }
}

/**
 * Validate + cap an action into a PENDING proposal. A Claude proposal on a
 * plan with `claude_auto_apply` is applied at once (status 'applied').
 */
export async function createProposal(
  userId: string,
  today: string,
  input: ProposalInput,
  source: ProposalSource,
): Promise<ServedProposal> {
  if (!ACTIONS.includes(input.action)) throw new RunPlanError("invalid_action", 400);
  const plan = await requirePlan(userId);
  const st = await planState(plan, today);
  const result = planOrThrow(actionContext(st, source), input.action, input.params ?? {});
  const rows = await db.query<ProposalRow>(
    `INSERT INTO run_plan_proposals (plan_id, source, action, summary, rationale, changes, cap_note)
     VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7)
     RETURNING ${PROPOSAL_COLUMNS}`,
    [plan.plan_id, source, input.action, (input.summary || result.summary).slice(0, 500), input.rationale?.slice(0, 2000) ?? null, JSON.stringify(result.changes), result.cap_note],
  );
  const proposal = rows[0];
  if (source === "claude" && plan.claude_auto_apply) {
    await applyProposalRow(plan, proposal.id, today);
    const again = await db.query<ProposalRow>(`SELECT ${PROPOSAL_COLUMNS} FROM run_plan_proposals WHERE id = $1`, [proposal.id]);
    return serveProposal(again[0]);
  }
  return serveProposal(proposal);
}

const daySourceFor = (s: ProposalSource): DaySource => (s === "engine" ? "flamey" : s);

/**
 * Write a change set inside `client`'s transaction. Each day must still be
 * exactly its `before` (else 409 proposal_stale); `original` keeps the
 * engine's version from before the first change.
 */
async function writeChanges(client: PoolClient, planId: string, changes: Change[], source: DaySource) {
  for (const c of changes) {
    const a = c.after;
    const res = await client.query(
      `UPDATE run_plan_days
          SET kind = $3, title = $4, distance_mi = $5, segments = $6::jsonb, note = $7,
              source = $8, original = COALESCE(original, $9::jsonb), updated_at = now()
        WHERE plan_id = $1 AND local_date = $2::date
          AND kind = $10 AND distance_mi = $11::numeric AND segments = $12::jsonb`,
      [planId, c.local_date, a.kind, a.title, a.distance_mi, JSON.stringify(a.segments), a.note, source,
        JSON.stringify(c.before), c.before.kind, c.before.distance_mi, JSON.stringify(c.before.segments)],
    );
    if (res.rowCount !== 1) throw new RunPlanError("proposal_stale", 409);
  }
}

async function inTransaction<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
  const client = await db.getClient();
  client.on("error", (e) => console.error("[runPlans] client error:", e));
  try {
    await client.query("BEGIN");
    const out = await fn(client);
    await client.query("COMMIT");
    return out;
  } catch (e) {
    await client.query("ROLLBACK").catch(() => {});
    throw e;
  } finally {
    client.release();
  }
}

async function applyProposalRow(plan: PlanRow, proposalId: string, today: string) {
  const rows = await db.query<ProposalRow>(
    `SELECT ${PROPOSAL_COLUMNS} FROM run_plan_proposals WHERE id = $1 AND plan_id = $2`,
    [proposalId, plan.plan_id],
  );
  const p = rows[0];
  if (!p) throw new RunPlanError("proposal_not_found", 404);
  if (p.status !== "pending") throw new RunPlanError("proposal_not_pending", 409, { status: p.status });
  const st = await planState(plan, today);
  const expire = async () => {
    await db.query(`UPDATE run_plan_proposals SET status = 'expired', decided_at = now() WHERE id = $1 AND status = 'pending'`, [p.id]);
    throw new RunPlanError("proposal_stale", 409);
  };
  if (staleReason(st, p.changes)) await expire();
  try {
    validateChanges(actionContext(st, p.source), p.changes, p.action as Action);
  } catch (e) {
    if (e instanceof ActionError) {
      await expire();
    }
    throw e;
  }
  try {
    await inTransaction(async (client) => {
      const claim = await client.query(
        `UPDATE run_plan_proposals SET status = 'applied', decided_at = now() WHERE id = $1 AND status = 'pending'`,
        [p.id],
      );
      if (claim.rowCount !== 1) throw new RunPlanError("proposal_not_pending", 409);
      await writeChanges(client, plan.plan_id, p.changes, daySourceFor(p.source));
    });
  } catch (e) {
    if (e instanceof RunPlanError && e.code === "proposal_stale") {
      await db.query(`UPDATE run_plan_proposals SET status = 'expired', decided_at = now() WHERE id = $1 AND status = 'pending'`, [p.id]);
    }
    throw e;
  }
}

/** POST /run-plans/proposals/:id/apply → current */
export async function applyProposal(userId: string, proposalId: string, today: string): Promise<CurrentPlanResponse> {
  const plan = await requirePlan(userId);
  await applyProposalRow(plan, proposalId, today);
  return buildCurrent(userId, today);
}

/** POST /run-plans/proposals/:id/decline → { ok } */
export async function declineProposal(userId: string, proposalId: string): Promise<{ ok: true }> {
  const rows = await db.query<{ status: string }>(
    `SELECT pr.status FROM run_plan_proposals pr JOIN run_plans rp ON rp.plan_id = pr.plan_id
      WHERE pr.id = $1 AND rp.user_id = $2`,
    [proposalId, userId],
  );
  if (!rows[0]) throw new RunPlanError("proposal_not_found", 404);
  if (rows[0].status !== "pending") throw new RunPlanError("proposal_not_pending", 409, { status: rows[0].status });
  await db.query(
    `UPDATE run_plan_proposals SET status = 'declined', decided_at = now() WHERE id = $1 AND status = 'pending'`,
    [proposalId],
  );
  return { ok: true };
}

/** POST /run-plans/days/:date/adjust — easier | shorter | just_mile, applied at once. */
export async function adjustDay(
  userId: string,
  date: string,
  action: "easier" | "shorter" | "just_mile",
  today: string,
): Promise<CurrentPlanResponse> {
  const plan = await requirePlan(userId);
  const st = await planState(plan, today);
  const result = planOrThrow(actionContext(st, "user"), action, { local_date: date });
  await inTransaction((client) => writeChanges(client, plan.plan_id, result.changes, "user"));
  const current = await buildCurrent(userId, today);
  return { ...current, cap_note: result.cap_note };
}

export interface CheckinInput {
  feeling?: Feeling | null;
  message?: string | null;
  pain_flag?: boolean;
}

export interface ServedCheckin {
  id: string;
  plan_id: string;
  local_date: string;
  feeling: Feeling | null;
  message: string | null;
  pain_flag: boolean;
  created_at: string;
}

/**
 * POST /run-plans/checkins — records the check-in and maps it to a pending
 * proposal: tired→easier, sore/pain→just_mile + soften next hard,
 * great→harder, normal→none. An impossible mapping gives `proposal: null`.
 */
export async function recordCheckin(
  userId: string,
  today: string,
  input: CheckinInput,
): Promise<{ checkin: ServedCheckin; proposal: ServedProposal | null }> {
  const plan = await requirePlan(userId);
  const rows = await db.query<ServedCheckin>(
    `INSERT INTO run_plan_checkins (plan_id, user_id, local_date, feeling, message, pain_flag)
     VALUES ($1, $2, $3::date, $4, $5, $6)
     RETURNING id, plan_id, local_date::text AS local_date, feeling, message, pain_flag, created_at`,
    [plan.plan_id, userId, today, input.feeling ?? null, input.message ?? null, input.pain_flag === true],
  );
  const mapped = checkinAction(input.feeling ?? null, input.pain_flag === true);
  let proposal: ServedProposal | null = null;
  if (mapped) {
    try {
      proposal = await createProposal(userId, today, { action: mapped.action, params: mapped.params, rationale: mapped.rationale }, "flamey");
    } catch (e) {
      if (!(e instanceof RunPlanError && e.code === "action_not_possible")) throw e;
    }
  }
  return { checkin: rows[0], proposal };
}

/** Check-ins in [from, to] across the user's plans (≤ 366 days). */
export async function listCheckins(userId: string, from: string, to: string): Promise<ServedCheckin[]> {
  if (from > to) [from, to] = [to, from];
  return db.query<ServedCheckin>(
    `SELECT id, plan_id, local_date::text AS local_date, feeling, message, pain_flag, created_at
       FROM run_plan_checkins
      WHERE user_id = $1 AND local_date BETWEEN $2::date AND $3::date
        AND local_date >= $3::date - 366
      ORDER BY local_date DESC, created_at DESC LIMIT 200`,
    [userId, from, to],
  );
}

/** Proposals on the active plan, newest first. */
export async function listProposals(
  userId: string,
  opts: { status?: string; source?: ProposalSource; limit?: number } = {},
): Promise<ServedProposal[]> {
  const plan = await activePlan(userId);
  if (!plan) return [];
  const rows = await db.query<ProposalRow>(
    `SELECT ${PROPOSAL_COLUMNS} FROM run_plan_proposals
      WHERE plan_id = $1 AND ($2::text IS NULL OR status = $2) AND ($3::text IS NULL OR source = $3)
      ORDER BY created_at DESC LIMIT $4`,
    [plan.plan_id, opts.status ?? null, opts.source ?? null, Math.min(100, Math.max(1, opts.limit ?? 50))],
  );
  return rows.map(serveProposal);
}

/** Profile for the coach: goals, effort, baseline, current fitness, checkpoints. */
export async function getProfile(userId: string, today: string) {
  const plan = await activePlan(userId);
  const fitness = await getFitness(userId, today);
  if (!plan) return { plan: null, fitness, checkpoints: [] as Checkpoint[] };
  const st = await planState(plan, today);
  return { plan: servePlan(st), fitness, checkpoints: st.checkpoints, warning: hardDaysWarning(st.hardDays) };
}
