import type { PoolClient } from "pg";
import { PostgresService } from "../DbService.js";
import { countedWorkoutSql } from "../mileTime.js";
import { userOffsetMinutesSql } from "../dailyResetTime.js";
import { listShoes } from "../shoeService.js";
import { displayMovingSecondsSql } from "../posts/postSql.js";
import {
  ActualRun,
  AdaptContext,
  BuildContext,
  COACH_RULES_TEXT,
  Day,
  DaySpec,
  Difficulty,
  EngineError,
  FitnessProfile,
  Goal,
  GradeInputs,
  GradeRecord,
  OptionIntent,
  PROPOSAL_KINDS,
  PlanSettings,
  ProposalDraft,
  ProposalKind,
  ProposalSource,
  ProposedChange,
  RunHistoryItem,
  SHOE_RUN_TYPES,
  ShoeRunType,
  WALK_MODES,
  WalkMode,
  addDays,
  buildContextFor,
  buildDay,
  checkinProposal,
  checkpointsFor,
  dateRange,
  dayStatus,
  estimateFor,
  fatigueSignals,
  focusOf,
  generateDays,
  goalDistanceMi,
  gradeSession,
  gradeSummaryTemplate,
  hardSessionsFor,
  hrBandsFor,
  isIsoDate,
  missedRunProposals,
  normalizeProfile,
  optionsFor,
  paceUpdateProposal,
  pacesFor,
  planWeeks,
  rebuild,
  resolveVdot,
  returnFromBreakProposal,
  shoeRunTypeFor,
  spikeLimit,
  validateChanges,
  validateGoals,
  walkDayProposals,
  weekStart,
  weekdayIndex,
} from "./engine.js";
import { AiStatus, getAiStatus } from "./coachSettings.js";

/**
 * Run Plans v2 service — the DB side of `engine.ts`.
 *
 * THE RULE: plan days change only through (a) applying a proposal the user
 * decided (`applyProposal` / `applyAfterRun` → `applyScheduledFor`), (b) undo,
 * (c) the user's own settings edit (`updatePlan`), (d) `applyOverseerChange`
 * (admin, own plan, `confirmed_in_chat`), or (e) materializing NEW future days.
 * Every adaptation — formula, Apple, Anthropic, overseer, the user's Claude —
 * is a `run_plan_proposals` row. Entitlement (Plus) is the caller's job.
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

export const DAYS_AHEAD = 28;
export const UNDO_HOURS = 24;
const MAX_RANGE_DAYS = 120;
const RUN_TYPES_SQL = `('running')`;
const ON_FOOT_SQL = `('running', 'walking', 'hiking')`;

// ─── Rows ─────────────────────────────────────────────────────────────────

export interface PlanRow {
  plan_id: string;
  user_id: string;
  status: string;
  goals: Goal[];
  target_date: string | null;
  runs_per_week: number;
  difficulty: Difficulty;
  walk_mode: WalkMode;
  fixed_walk_days: number[];
  coach_notes: string;
  shoe_assignments: Partial<Record<ShoeRunType, string | null>>;
  start_date: string;
  baseline: Baseline;
  source: string;
  last_open_date: string | null;
  last_nightly_date: string | null;
  created_at: string;
  updated_at: string;
}
interface Baseline {
  vdot: number;
  vdot_source: string;
  pace_factor: number;
  experience: FitnessProfile["experience"];
  profile_at: string | null;
}
const PLAN_COLS = `plan_id, user_id, status, goals, target_date::text AS target_date, runs_per_week, difficulty, walk_mode,
  fixed_walk_days, coach_notes, shoe_assignments, start_date::text AS start_date, baseline, source,
  last_open_date::text AS last_open_date, last_nightly_date::text AS last_nightly_date, created_at, updated_at`;

export async function activePlan(userId: string, client?: PoolClient): Promise<PlanRow | null> {
  const q = `SELECT ${PLAN_COLS} FROM run_plans WHERE user_id = $1 AND status = 'active'`;
  const rows = client ? (await client.query<PlanRow>(q, [userId])).rows : await db.query<PlanRow>(q, [userId]);
  return rows[0] ?? null;
}
async function requirePlan(userId: string): Promise<PlanRow> {
  const p = await activePlan(userId);
  if (!p) throw new RunPlanError("no_plan", 404);
  return p;
}

interface DayRow {
  local_date: string;
  kind: string;
  day: Day;
  note: string | null;
  note_source: string;
  version: number;
  source: string;
}
async function loadDays(planId: string, from: string, to: string, client?: PoolClient): Promise<Map<string, DayRow>> {
  const q = `SELECT local_date::text AS local_date, kind, day, note, note_source, version, source
       FROM run_plan_days WHERE plan_id = $1 AND local_date BETWEEN $2::date AND $3::date ORDER BY local_date`;
  const rows = client ? (await client.query<DayRow>(q, [planId, from, to])).rows : await db.query<DayRow>(q, [planId, from, to]);
  return new Map(rows.map((r) => [r.local_date, { ...r, day: { ...r.day, note: r.note } }]));
}

export async function getProfile(userId: string): Promise<{ profile: FitnessProfile | null; updated_at: string | null }> {
  const rows = await db.query<{ profile: FitnessProfile; updated_at: string }>(
    `SELECT profile, updated_at FROM run_fitness_profiles WHERE user_id = $1`,
    [userId],
  );
  return rows[0] ? { profile: rows[0].profile, updated_at: rows[0].updated_at } : { profile: null, updated_at: null };
}

export async function putProfile(userId: string, raw: unknown, today: string): Promise<{ profile: FitnessProfile; updated_at: string; proposals: ServedProposal[] }> {
  const size = JSON.stringify(raw ?? null).length;
  if (size > 32 * 1024) throw new RunPlanError("profile_too_large", 413);
  let profile: FitnessProfile;
  try {
    const { today: _t, ...rest } = (raw ?? {}) as Record<string, unknown>;
    profile = normalizeProfile(rest);
  } catch (e) {
    if (e instanceof EngineError) throw new RunPlanError(e.code, 400, e.extra);
    throw e;
  }
  const computedAt = typeof profile.computed_at === "string" && !Number.isNaN(Date.parse(profile.computed_at)) ? profile.computed_at : null;
  const rows = await db.query<{ updated_at: string }>(
    `INSERT INTO run_fitness_profiles (user_id, profile, computed_at, updated_at) VALUES ($1, $2::jsonb, $3::timestamptz, now())
     ON CONFLICT (user_id) DO UPDATE SET profile = EXCLUDED.profile, computed_at = EXCLUDED.computed_at, updated_at = now()
     RETURNING updated_at`,
    [userId, JSON.stringify(profile), computedAt],
  );
  // A new fitness estimate (race/test) may move paces: that's a proposal (rule 20).
  let proposals: ServedProposal[] = [];
  const plan = await activePlan(userId);
  if (plan) proposals = await profilePaceProposal(userId, today).catch((e) => (console.error("[runPlans] profile pace proposal:", e), []));
  return { profile, updated_at: rows[0].updated_at, proposals };
}

/** Counted runs (and optionally walks/hikes) in [from, to], with start hour and splits. */
async function loadRuns(userId: string, from: string, to: string, onFoot = false): Promise<ActualRun[]> {
  const rows = await db.query<{
    workout_id: string; local_date: string; workout_type: string; distance: number; total_duration: number; moving_s: number | null; start_hour: number | null;
  }>(
    `SELECT w.workout_id, w.local_date::text AS local_date, w.workout_type, w.distance, w.total_duration,
            ${displayMovingSecondsSql("w")} AS moving_s,
            EXTRACT(HOUR FROM ((w.device_end_date AT TIME ZONE 'UTC') - w.total_duration * INTERVAL '1 second' + w.timezone_offset * INTERVAL '1 minute'))::int AS start_hour
       FROM workouts w
      WHERE w.user_id = $1 AND w.local_date BETWEEN $2::date AND $3::date AND ${countedWorkoutSql("w")}
        AND w.workout_type IN ${onFoot ? ON_FOOT_SQL : RUN_TYPES_SQL}
      ORDER BY w.local_date, w.device_end_date LIMIT 1000`,
    [userId, from, to],
  );
  if (!rows.length) return [];
  const splits = await db.query<{ workout_id: string; split_distance: number | null; split_duration: number; split_pace: number | null }>(
    `SELECT workout_id, split_distance, split_duration, split_pace FROM workout_splits WHERE workout_id = ANY($1) ORDER BY workout_id, split_number`,
    [rows.map((r) => r.workout_id)],
  );
  const by = new Map<string, NonNullable<ActualRun["splits"]>>();
  for (const s of splits) {
    const l = by.get(s.workout_id) ?? [];
    l.push({ distance_mi: s.split_distance != null ? Number(s.split_distance) : null, duration_s: Number(s.split_duration), pace_s: s.split_pace != null ? Number(s.split_pace) : null });
    by.set(s.workout_id, l);
  }
  return rows.map((r) => ({
    workout_id: r.workout_id,
    local_date: r.local_date,
    workout_type: r.workout_type,
    distance_mi: Number(r.distance),
    duration_s: Number(r.total_duration),
    moving_s: r.moving_s != null ? Number(r.moving_s) : null,
    start_hour: r.start_hour,
    splits: by.get(r.workout_id) ?? [],
  }));
}

// ─── Plan context (settings, paces, days) ─────────────────────────────────

export function settingsOf(p: PlanRow): PlanSettings {
  return {
    goals: p.goals,
    target_date: p.target_date,
    runs_per_week: p.runs_per_week,
    difficulty: p.difficulty,
    walk_mode: p.walk_mode,
    fixed_walk_days: p.fixed_walk_days ?? [],
    start_date: p.start_date,
    pace_factor: p.baseline.pace_factor ?? 1,
  };
}

interface PlanContext {
  plan: PlanRow;
  settings: PlanSettings;
  profile: FitnessProfile | null;
  bctx: BuildContext;
  gen: { settings: PlanSettings; profile: FitnessProfile | null; paces: ReturnType<typeof pacesFor>; hr: ReturnType<typeof hrBandsFor> };
}
function contextFor(plan: PlanRow, profile: FitnessProfile | null): PlanContext {
  // Paces are fixed at the plan's VDOT; pace updates move `pace_factor` (applied per day via DaySpec).
  const paces = pacesFor(plan.baseline.vdot, plan.baseline.vdot_source as any);
  const hr = hrBandsFor(profile);
  const settings = settingsOf(plan);
  const gen = { settings, profile: profile ? { ...profile, experience: plan.baseline.experience ?? profile.experience } : profile, paces, hr };
  return { plan, settings, profile, bctx: buildContextFor(gen), gen };
}

/** Insert any missing days through `through` (new days only, never overwrites). */
async function materialize(ctx: PlanContext, today: string, through: string, actual: RunHistoryItem[]): Promise<void> {
  const from = ctx.plan.start_date > today ? ctx.plan.start_date : today;
  const end = ctx.plan.target_date && ctx.plan.target_date < through ? addDays(weekStart(ctx.plan.target_date), 6) : through;
  if (end < from) return;
  const existing = await loadDays(ctx.plan.plan_id, ctx.plan.start_date, end);
  const missingFrom = dateRange(from, end).find((d) => !existing.has(d));
  if (!missingFrom) return;
  const hist: RunHistoryItem[] = [
    ...actual.filter((r) => r.local_date < today),
    ...[...existing.values()].filter((d) => d.local_date >= today && d.day.kind !== "walk").map((d) => ({ local_date: d.local_date, distance_mi: d.day.distance_mi })),
  ];
  const gen = generateDays(ctx.gen, missingFrom, end, hist).filter((d) => !existing.has(d.local_date));
  if (!gen.length) return;
  await insertDays(db, ctx.plan.plan_id, gen, "formula");
}

async function insertDays(c: { query: (q: string, p: unknown[]) => Promise<unknown> }, planId: string, days: { local_date: string; day: Day }[], source: string) {
  for (let i = 0; i < days.length; i += 200) {
    const chunk = days.slice(i, i + 200);
    const vals: unknown[] = [];
    const tuples = chunk.map((d, j) => {
      vals.push(planId, d.local_date, d.day.kind, JSON.stringify(d.day), d.day.note, source);
      const b = j * 6;
      return `($${b + 1}::uuid, $${b + 2}::date, $${b + 3}, $${b + 4}::jsonb, $${b + 5}, $${b + 6})`;
    });
    await c.query(
      `INSERT INTO run_plan_days (plan_id, local_date, kind, day, note, source) VALUES ${tuples.join(", ")}
       ON CONFLICT (plan_id, local_date) DO NOTHING`,
      vals,
    );
  }
}

interface PlanState extends PlanContext {
  today: string;
  dayRows: Map<string, DayRow>;
  days: Map<string, Day>;
  runs: ActualRun[];
  onFoot: ActualRun[];
  steps: Map<string, number>;
  grades: Map<string, GradeRow>;
  pending: ProposalRow[];
  profileRun: RunHistoryItem[];
}

async function loadState(userId: string, today: string, opts: { plan?: PlanRow; back?: number; ahead?: number } = {}): Promise<PlanState> {
  const plan = opts.plan ?? (await requirePlan(userId));
  const { profile, updated_at: profileAt } = await getProfile(userId);
  const ctx = contextFor(plan, profile);
  const back = opts.back ?? 35;
  const ahead = opts.ahead ?? DAYS_AHEAD;
  // At least 60 days (spike guard / fatigue history), and the whole served window.
  const runs = await loadRuns(userId, addDays(today, -Math.max(60, back)), addDays(today, ahead));
  const profileRun = profileHistory(profile, profileAt, today);
  await materialize(ctx, today, addDays(today, ahead), [...runs, ...profileRun]);
  const [dayRows, onFoot, stepRows, grades, pending] = await Promise.all([
    loadDays(plan.plan_id, addDays(today, -back), addDays(today, ahead + 7)),
    loadRuns(userId, addDays(today, -back), today, true),
    db.query<{ local_date: string; steps: number }>(`SELECT local_date::text AS local_date, steps FROM daily_steps WHERE user_id = $1 AND local_date BETWEEN $2::date AND $3::date`, [userId, addDays(today, -back), today]),
    loadGrades(plan.plan_id, addDays(today, -back), today),
    listProposalRows(plan.plan_id, ["pending", "scheduled"]),
  ]);
  const days = new Map([...dayRows].map(([k, v]) => [k, v.day]));
  return { ...ctx, today, dayRows, days, runs, onFoot, steps: new Map(stepRows.map((r) => [r.local_date, r.steps])), grades, pending, profileRun };
}

/**
 * The phone's "longest run in the last 30 days" (HealthKit) as one history
 * point the day before the upload, so the spike guard has a reference even
 * when the server lacks those workouts. Ignored once it's 30+ days old.
 */
function profileHistory(profile: FitnessProfile | null, updatedAt: string | Date | null, today: string): RunHistoryItem[] {
  const mi = profile?.longest_run_30d_mi;
  if (!mi || !updatedAt) return [];
  const d = addDays(new Date(updatedAt).toISOString().slice(0, 10), -1);
  return d >= addDays(today, -30) && d < today ? [{ local_date: d, distance_mi: mi }] : [];
}

function adaptContext(st: PlanState): AdaptContext {
  const pendingDates = new Set<string>();
  for (const p of st.pending) for (const c of p.changes) pendingDates.add(c.local_date);
  return {
    today: st.today,
    days: st.days,
    actual: [...st.runs.filter((r) => r.local_date < st.today).map((r) => ({ local_date: r.local_date, distance_mi: r.distance_mi })), ...st.profileRun],
    settings: st.settings,
    bctx: st.bctx,
    profile: st.profile,
    runs: st.runs,
    grades: [...st.grades.values()].map(gradeRecord),
    pendingDates,
  };
}

// ─── Served shapes ────────────────────────────────────────────────────────

export interface ServedPlan {
  plan_id: string;
  status: string;
  goals: (Goal & { current_s: number | null })[];
  target_date: string | null;
  runs_per_week: number;
  difficulty: number;
  walk_mode: WalkMode;
  fixed_walk_days: number[];
  coach_notes: string;
  shoe_assignments: Record<ShoeRunType, string | null>;
  hard_sessions_per_week: number;
  start_date: string;
  week_index: number;
  phase: string;
  weekly_target_mi: number;
  checkpoints: ReturnType<typeof checkpointsFor>;
  created_at: string;
  updated_at: string;
}
function servePlan(ctx: PlanContext, today: string): ServedPlan {
  const p = ctx.plan;
  const w = Math.max(0, Math.floor((Date.parse(weekStart(today)) - Date.parse(weekStart(p.start_date))) / (7 * 86_400_000)));
  const weeks = planWeeks(ctx.settings, ctx.gen.profile, ctx.gen.paces, w + 1);
  const wk = weeks[Math.min(w, weeks.length - 1)];
  const vdot = ctx.gen.paces.vdot / (p.baseline.pace_factor ?? 1);
  return {
    plan_id: p.plan_id,
    status: p.status,
    goals: p.goals.map((g) => ({ ...g, current_s: g.type === "distance_time" ? estimateFor(vdot, goalDistanceMi(g) ?? 3.10686) : null })),
    target_date: p.target_date,
    runs_per_week: p.runs_per_week,
    difficulty: p.difficulty,
    walk_mode: p.walk_mode,
    fixed_walk_days: p.fixed_walk_days ?? [],
    coach_notes: p.coach_notes,
    shoe_assignments: Object.fromEntries(SHOE_RUN_TYPES.map((t) => [t, p.shoe_assignments?.[t] ?? null])) as Record<ShoeRunType, string | null>,
    hard_sessions_per_week: hardSessionsFor(p.runs_per_week, p.difficulty, ctx.gen.profile?.experience ?? null, p.goals),
    start_date: p.start_date,
    week_index: w,
    phase: wk?.phase ?? "rolling",
    weekly_target_mi: wk?.volume_mi ?? 0,
    checkpoints: checkpointsFor(p.goals, vdot, p.difficulty),
    created_at: p.created_at,
    updated_at: p.updated_at,
  };
}

interface ShoeInfo { shoe_id: string; name: string; brand: string | null }
/** Shoes are owner-only and read only through shoeService. */
async function shoesFor(userId: string, ids: string[]): Promise<Map<string, ShoeInfo>> {
  if (!ids.length) return new Map();
  const want = new Set(ids);
  const rows = (await listShoes(userId)).filter((s) => want.has(s.shoe_id) && !s.retired_at);
  return new Map(rows.map((r) => [r.shoe_id, { shoe_id: r.shoe_id, name: r.name, brand: r.brand }]));
}

export interface ServedGrade {
  score: number; completion: number; on_target: number; consistency: number; source: string;
  summary: string | null; summary_source: string; workout_id: string | null; graded_at: string;
}
export interface ServedDay extends Omit<Day, "spec"> {
  local_date: string;
  weekday: number;
  note_source: string;
  shoe: ShoeInfo | null;
  status: string;
  completed: { workout_ids: string[]; distance_mi: number; duration_s: number; avg_pace_s: number | null } | null;
  grade: ServedGrade | null;
  pending_proposal_ids: string[];
  version: number;
  spec: DaySpec;
}
async function serveDays(st: PlanState, from: string, to: string): Promise<ServedDay[]> {
  const shoeIds = Object.values(st.plan.shoe_assignments ?? {}).filter((x): x is string => typeof x === "string");
  const shoes = await shoesFor(st.plan.user_id, shoeIds);
  const out: ServedDay[] = [];
  for (const d of dateRange(from, to)) {
    const row = st.dayRows.get(d);
    if (!row) continue;
    const runs = st.runs.filter((r) => r.local_date === d);
    const foot = st.onFoot.filter((r) => r.local_date === d).reduce((a, r) => a + r.distance_mi, 0);
    let status = dayStatus(row.day, d, st.today, runs, foot);
    if (row.day.kind === "walk" && status !== "walk_done" && (st.steps.get(d) ?? 0) >= 10000) status = "walk_done";
    const miles = runs.reduce((a, r) => a + r.distance_mi, 0);
    const secs = runs.reduce((a, r) => a + (r.moving_s ?? r.duration_s), 0);
    const g = st.grades.get(d);
    const shoeId = st.plan.shoe_assignments?.[shoeRunTypeFor(row.day.kind)] ?? null;
    out.push({
      ...row.day,
      local_date: d,
      weekday: weekdayIndex(d),
      note: row.note,
      note_source: row.note_source,
      shoe: shoeId ? shoes.get(shoeId) ?? null : null,
      status,
      completed: runs.length ? { workout_ids: runs.map((r) => r.workout_id), distance_mi: Math.round(miles * 100) / 100, duration_s: Math.round(secs), avg_pace_s: miles > 0 ? Math.round(secs / miles) : null } : null,
      grade: g ? { score: g.score, completion: g.completion, on_target: g.on_target, consistency: g.consistency, source: g.source, summary: g.summary, summary_source: g.summary_source, workout_id: g.workout_id, graded_at: g.graded_at } : null,
      pending_proposal_ids: st.pending.filter((p) => p.changes.some((c) => c.local_date === d)).map((p) => p.id),
      version: row.version,
    });
  }
  return out;
}

// ─── Proposals ────────────────────────────────────────────────────────────

interface StoredChange {
  local_date: string;
  before: Day | null;
  after: Day;
  before_version: number | null;
}
interface ProposalRow {
  id: string;
  plan_id: string;
  user_id: string;
  source: ProposalSource;
  kind: ProposalKind;
  status: string;
  title: string;
  reason: string;
  goal_impact: ProposalDraft["goal_impact"];
  changes: StoredChange[];
  checks: Record<string, unknown> & { plan_patch?: { pace_factor?: number; vdot?: number; prev?: Record<string, number> } | null };
  first_date: string;
  apply_after_date: string | null;
  created_at: string;
  decided_at: string | null;
  applied_at: string | null;
  undo_until: string | null;
  ai_call_id: string | null;
}
const PROPOSAL_COLS = `id, plan_id, user_id, source, kind, status, title, reason, goal_impact, changes, checks,
  first_date::text AS first_date, apply_after_date::text AS apply_after_date, created_at, decided_at, applied_at, undo_until, ai_call_id`;

async function listProposalRows(planId: string, statuses: string[] | null, limit = 200): Promise<ProposalRow[]> {
  return db.query<ProposalRow>(
    `SELECT ${PROPOSAL_COLS} FROM run_plan_proposals WHERE plan_id = $1 AND ($2::text[] IS NULL OR status = ANY($2)) ORDER BY created_at DESC LIMIT $3`,
    [planId, statuses, limit],
  );
}

export interface ServedProposal {
  id: string;
  plan_id: string;
  source: string;
  kind: string;
  status: string;
  title: string;
  reason: string;
  goal_impact: ProposalDraft["goal_impact"];
  changes: { local_date: string; before: Omit<Day, "spec"> & { spec: DaySpec } | null; after: Omit<Day, "spec"> & { spec: DaySpec }; before_version: number | null }[];
  checks: Record<string, unknown>;
  plan_patch: { pace_factor?: number; vdot?: number } | null;
  affects_next_run: boolean;
  first_date: string;
  created_at: string;
  decided_at: string | null;
  applied_at: string | null;
  undo_until: string | null;
  apply_after_date: string | null;
}
function serveProposal(p: ProposalRow, nextRunDate: string | null = null): ServedProposal {
  const { plan_patch, ...checks } = p.checks ?? {};
  return {
    id: p.id,
    plan_id: p.plan_id,
    source: p.source,
    kind: p.kind,
    status: p.status,
    title: p.title,
    reason: p.reason,
    goal_impact: p.goal_impact ?? null,
    changes: p.changes,
    checks,
    plan_patch: plan_patch ? { pace_factor: plan_patch.pace_factor, vdot: plan_patch.vdot } : null,
    affects_next_run: nextRunDate != null && p.changes.some((c) => c.local_date === nextRunDate),
    first_date: p.first_date,
    created_at: p.created_at,
    decided_at: p.decided_at,
    applied_at: p.applied_at,
    undo_until: p.undo_until,
    apply_after_date: p.apply_after_date,
  };
}

/** The next planned run on or after today that isn't done yet. */
function nextRunDate(st: PlanState): string | null {
  for (const d of dateRange(st.today, addDays(st.today, DAYS_AHEAD))) {
    const day = st.days.get(d);
    if (!day || day.kind === "walk") continue;
    const runs = st.runs.filter((r) => r.local_date === d);
    if (dayStatus(day, d, st.today, runs, 0) === "done") continue;
    return d;
  }
  return null;
}

async function history(c: { query: (q: string, p: unknown[]) => Promise<unknown> }, planId: string, userId: string, event: string, source: string | null, proposalId: string | null, summary: string, dates: string[], detail: unknown = null) {
  await c.query(
    `INSERT INTO run_plan_history (plan_id, user_id, event, source, proposal_id, summary, dates, detail) VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8::jsonb)`,
    [planId, userId, event, source, proposalId, summary.slice(0, 500), JSON.stringify(dates), detail == null ? null : JSON.stringify(detail)],
  );
}

async function inTransaction<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
  const client = await db.getClient();
  const onError = (e: unknown) => console.error("[runPlans] client error:", e);
  client.on("error", onError);
  try {
    await client.query("BEGIN");
    const out = await fn(client);
    await client.query("COMMIT");
    return out;
  } catch (e) {
    await client.query("ROLLBACK").catch(() => {});
    throw e;
  } finally {
    client.off("error", onError);
    client.release();
  }
}

export interface ProposalInput {
  source: ProposalSource;
  kind: ProposalKind;
  title: string;
  reason: string;
  goal_impact?: ProposalDraft["goal_impact"];
  /** Either full Days (engine-built) or DaySpecs (model/user intent; rebuilt here). */
  changes: { local_date: string; after?: Day; spec?: DaySpec }[];
  deviation_reason?: string | null;
  dedupe_key?: string | null;
  plan_patch?: { pace_factor?: number; vdot?: number } | null;
  ai_call_id?: string | null;
  created_by?: string | null;
}

/** Validate + store a PENDING proposal. Never touches plan days. */
async function createProposalInState(st: PlanState, input: ProposalInput): Promise<ServedProposal | null> {
  if (!input.changes.length || input.changes.length > 31) throw new RunPlanError("invalid_day_spec", 400, { reason: "changes must have 1–31 entries" });
  const seen = new Set<string>();
  const changes: ProposedChange[] = input.changes.map((c) => {
    if (!isIsoDate(c.local_date)) throw new RunPlanError("invalid_day_spec", 400, { field: "local_date" });
    if (seen.has(c.local_date)) throw new RunPlanError("invalid_day_spec", 400, { reason: "duplicate date" });
    seen.add(c.local_date);
    if (c.local_date < st.today) throw new RunPlanError("past_date", 400, { local_date: c.local_date });
    const cur = st.days.get(c.local_date);
    if (!cur) throw new RunPlanError("date_outside_plan", 400, { local_date: c.local_date });
    if (c.after) return { local_date: c.local_date, after: c.after };
    try {
      return { local_date: c.local_date, after: buildDay(c.spec!, st.bctx, { phase: cur.phase, week_index: cur.week_index, flex: cur.flex && c.spec!.kind !== "walk" ? cur.flex : cur.flex }) };
    } catch (e) {
      if (e instanceof EngineError) throw new RunPlanError(e.code, 400, e.extra);
      throw e;
    }
  });
  const v = validateChanges(adaptContext(st), changes);
  if (!v.ok) throw new RunPlanError("hard_rule_violation", 422, { violations: v.violations });
  const reason = input.deviation_reason?.trim() || null;
  if (v.deviations.length && !reason) throw new RunPlanError("deviation_reason_required", 422, { deviations: v.deviations });
  const stored: StoredChange[] = changes
    .sort((a, b) => a.local_date.localeCompare(b.local_date))
    .map((c) => ({ local_date: c.local_date, before: st.days.get(c.local_date) ?? null, after: c.after, before_version: st.dayRows.get(c.local_date)?.version ?? null }));
  const checks = { ...v.checks, deviation_reason: v.deviations.length ? reason : null, plan_patch: input.plan_patch ?? null };
  const dates = stored.map((c) => c.local_date);
  return inTransaction(async (client) => {
    const ins = await client.query<ProposalRow>(
      `INSERT INTO run_plan_proposals (plan_id, user_id, source, kind, title, reason, goal_impact, changes, checks, first_date, dedupe_key, ai_call_id, created_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8::jsonb, $9::jsonb, $10::date, $11, $12, $13)
       ON CONFLICT (plan_id, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING
       RETURNING ${PROPOSAL_COLS}`,
      [st.plan.plan_id, st.plan.user_id, input.source, input.kind, input.title.slice(0, 200), input.reason.slice(0, 600), input.goal_impact ? JSON.stringify(input.goal_impact) : null, JSON.stringify(stored), JSON.stringify(checks), dates[0], input.dedupe_key ?? null, input.ai_call_id ?? null, input.created_by ?? null],
    );
    const row = ins.rows[0];
    if (!row) return null; // formula dedupe: already proposed
    // The newest proposal for a date replaces an unanswered older one.
    const sup = await client.query<{ id: string }>(
      `UPDATE run_plan_proposals SET status = 'superseded', decided_at = now()
        WHERE plan_id = $1 AND id <> $2 AND status IN ('pending', 'scheduled')
          AND EXISTS (SELECT 1 FROM jsonb_array_elements(changes) c WHERE c->>'local_date' = ANY($3::text[]))
        RETURNING id`,
      [st.plan.plan_id, row.id, dates],
    );
    for (const s of sup.rows) await history(client, st.plan.plan_id, st.plan.user_id, "proposal_superseded", null, s.id, `Replaced by a newer suggestion`, dates);
    await history(client, st.plan.plan_id, st.plan.user_id, "proposal_created", input.source, row.id, input.title, dates);
    st.pending = [row, ...st.pending.filter((p) => !sup.rows.some((s) => s.id === p.id))];
    return serveProposal(row, nextRunDate(st));
  });
}

export async function createProposal(userId: string, input: ProposalInput, today: string): Promise<ServedProposal> {
  if (!PROPOSAL_KINDS.includes(input.kind)) throw new RunPlanError("invalid_source", 400, { field: "kind" });
  if (!input.title?.trim() || !input.reason?.trim()) throw new RunPlanError("invalid_day_spec", 400, { reason: "title and reason are required" });
  const st = await loadState(userId, today);
  const p = await createProposalInState(st, { ...input, dedupe_key: null });
  return p!;
}

async function lockProposal(client: PoolClient, userId: string, id: string): Promise<ProposalRow> {
  if (!/^[0-9a-f-]{36}$/i.test(id)) throw new RunPlanError("proposal_not_found", 404);
  const r = await client.query<ProposalRow>(`SELECT ${PROPOSAL_COLS} FROM run_plan_proposals WHERE id = $1 AND user_id = $2 FOR UPDATE`, [id, userId]);
  if (!r.rows[0]) throw new RunPlanError("proposal_not_found", 404);
  return r.rows[0];
}

/** Write a proposal's `after` days, version-checked. Throws stale_proposal if any day moved on. */
async function writeAfter(client: PoolClient, p: ProposalRow): Promise<void> {
  for (const c of p.changes) {
    const r = await client.query(
      `UPDATE run_plan_days SET kind = $3, day = $4::jsonb, note = $5, note_source = $6, version = version + 1, source = $7, updated_at = now()
        WHERE plan_id = $1 AND local_date = $2::date AND ($8::int IS NULL OR version = $8::int)`,
      [p.plan_id, c.local_date, c.after.kind, JSON.stringify(c.after), c.after.note, noteSourceFor(p.source, c), p.source, c.before_version],
    );
    if (r.rowCount === 0) {
      throw new RunPlanError("stale_proposal", 409, { local_date: c.local_date });
    }
  }
  const patch = p.checks?.plan_patch;
  if (patch && (patch.pace_factor != null || patch.vdot != null)) {
    await client.query(
      `UPDATE run_plans SET baseline = baseline || $2::jsonb, updated_at = now() WHERE plan_id = $1`,
      [p.plan_id, JSON.stringify({ ...(patch.pace_factor != null ? { pace_factor: patch.pace_factor } : {}), ...(patch.vdot != null ? { vdot: patch.vdot } : {}) })],
    );
  }
}
const noteSourceFor = (src: string, c: StoredChange) =>
  c.after.note && c.after.note !== c.before?.note && ["apple", "anthropic", "overseer", "user_claude"].includes(src) ? src : "template";

async function supersedeOverlapping(client: PoolClient, p: ProposalRow) {
  const dates = p.changes.map((c) => c.local_date);
  const sup = await client.query<{ id: string }>(
    `UPDATE run_plan_proposals SET status = 'superseded', decided_at = now()
      WHERE plan_id = $1 AND id <> $2 AND status IN ('pending', 'scheduled')
        AND EXISTS (SELECT 1 FROM jsonb_array_elements(changes) c WHERE c->>'local_date' = ANY($3::text[]))
      RETURNING id`,
    [p.plan_id, p.id, dates],
  );
  for (const s of sup.rows) await history(client, p.plan_id, p.user_id, "proposal_superseded", null, s.id, "The plan changed on these days", dates);
}

/** Serializes every change to one plan's days: apply / undo take this before the proposal lock. */
async function lockPlan(client: PoolClient, planId: string): Promise<void> {
  await client.query(`SELECT 1 FROM run_plans WHERE plan_id = $1 FOR UPDATE`, [planId]);
}

/** Plan row lock first, then the proposal row (same order as updatePlan: plan, then proposals). */
async function lockPlanAndProposal(client: PoolClient, userId: string, id: string): Promise<ProposalRow> {
  if (!/^[0-9a-f-]{36}$/i.test(id)) throw new RunPlanError("proposal_not_found", 404);
  const r = await client.query<{ plan_id: string }>(`SELECT plan_id FROM run_plan_proposals WHERE id = $1 AND user_id = $2`, [id, userId]);
  if (!r.rows[0]) throw new RunPlanError("proposal_not_found", 404);
  await lockPlan(client, r.rows[0].plan_id);
  return lockProposal(client, userId, id);
}

/** The plan as it is NOW (read under the plan lock), for re-running the HARD rules at apply time. */
async function currentValidationContext(client: PoolClient, p: ProposalRow, today: string, dates: string[]) {
  const rows = await loadDays(p.plan_id, addDays(today, -1), addDays(dates[dates.length - 1], 40), client);
  const [runs, prof] = await Promise.all([loadRuns(p.user_id, addDays(today, -35), addDays(today, -1)), getProfile(p.user_id)]);
  return {
    today,
    days: new Map([...rows].map(([k, v]) => [k, v.day])),
    actual: [...runs.map((r) => ({ local_date: r.local_date, distance_mi: r.distance_mi })), ...profileHistory(prof.profile, prof.updated_at, today)],
  };
}

type ApplyOutcome = { ok: true } | { ok: false; error: RunPlanError };

/**
 * The one apply path (apply now, scheduled apply-after-run). Must run under
 * `lockPlan`. Drops days already past (`today`, and for after-run the run day
 * itself), re-checks the HARD rules against the CURRENT plan, then writes.
 * A refusal is recorded on the proposal (expired / superseded) in this same
 * transaction and returned, so the caller commits it before surfacing it.
 * The proposal's `changes` become exactly what was written, so Undo reverts
 * only those days.
 */
async function applyChecked(client: PoolClient, p: ProposalRow, today: string, via: "now" | "after_run"): Promise<ApplyOutcome> {
  const afterRun = via === "after_run" && p.apply_after_date ? addDays(p.apply_after_date, 1) : today;
  const floor = afterRun > today ? afterRun : today;
  const remaining = p.changes.filter((c) => c.local_date >= floor);
  const skipped = p.changes.filter((c) => c.local_date < floor).map((c) => c.local_date);
  if (!remaining.length) {
    await client.query(`UPDATE run_plan_proposals SET status = 'expired', decided_at = COALESCE(decided_at, now()) WHERE id = $1`, [p.id]);
    await history(client, p.plan_id, p.user_id, "proposal_expired", p.source, p.id, `${p.title} (its days passed)`, [], { skipped_dates: skipped });
    return { ok: false, error: new RunPlanError("proposal_not_pending", 409, { status: "expired" }) };
  }
  const dates = remaining.map((c) => c.local_date);
  const v = validateChanges(await currentValidationContext(client, p, today, dates), remaining.map((c) => ({ local_date: c.local_date, after: c.after })));
  if (!v.ok) {
    await client.query(`UPDATE run_plan_proposals SET status = 'superseded', decided_at = now() WHERE id = $1`, [p.id]);
    await history(client, p.plan_id, p.user_id, "proposal_superseded", null, p.id, "The plan changed since this was suggested", dates, { violations: v.violations });
    return { ok: false, error: new RunPlanError("stale_proposal", 409, { local_date: v.violations[0].local_date, violations: v.violations }) };
  }
  const row: ProposalRow = { ...p, changes: remaining, first_date: dates[0] };
  try {
    await client.query("SAVEPOINT apply_p");
    await writeAfter(client, row);
    await client.query("RELEASE SAVEPOINT apply_p");
  } catch (e) {
    await client.query("ROLLBACK TO SAVEPOINT apply_p");
    if (e instanceof RunPlanError && e.code === "stale_proposal") {
      await client.query(`UPDATE run_plan_proposals SET status = 'superseded', decided_at = now() WHERE id = $1`, [p.id]);
      await history(client, p.plan_id, p.user_id, "proposal_superseded", null, p.id, "The day changed since this was suggested", dates);
      return { ok: false, error: e };
    }
    throw e;
  }
  await client.query(
    `UPDATE run_plan_proposals SET status = 'applied', changes = $3::jsonb, first_date = $4::date, decided_at = COALESCE(decided_at, now()), applied_at = now(), undo_until = now() + make_interval(hours => $2) WHERE id = $1`,
    [p.id, UNDO_HOURS, JSON.stringify(remaining), dates[0]],
  );
  await supersedeOverlapping(client, row);
  await history(client, p.plan_id, p.user_id, "proposal_applied", p.source, p.id, via === "after_run" ? `${p.title} (after the run)` : p.title, dates, skipped.length ? { skipped_dates: skipped } : null);
  return { ok: true };
}

async function proposalResponse(userId: string, id: string, today: string) {
  const st = await loadState(userId, today);
  const row = (await db.query<ProposalRow>(`SELECT ${PROPOSAL_COLS} FROM run_plan_proposals WHERE id = $1`, [id]))[0];
  const days = await serveDays(st, st.today, addDays(st.today, DAYS_AHEAD));
  const dates = new Set(row.changes.map((c) => c.local_date));
  return { proposal: serveProposal(row, nextRunDate(st)), days: days.filter((d) => dates.has(d.local_date)) };
}

export async function applyProposal(userId: string, id: string, today: string) {
  // A refused proposal is marked expired / superseded (committed) before the 409 is returned.
  const out = await inTransaction(async (client) => {
    const p = await lockPlanAndProposal(client, userId, id);
    if (p.status !== "pending" && p.status !== "scheduled") throw new RunPlanError("proposal_not_pending", 409, { status: p.status });
    return applyChecked(client, p, today, "now");
  });
  if (!out.ok) throw out.error;
  return proposalResponse(userId, id, today);
}

export async function applyAfterRun(userId: string, id: string, today: string) {
  await inTransaction(async (client) => {
    const p = await lockProposal(client, userId, id);
    if (p.status !== "pending") throw new RunPlanError("proposal_not_pending", 409, { status: p.status });
    if (!p.changes.some((c) => c.local_date === today)) throw new RunPlanError("not_for_today", 400);
    await client.query(`UPDATE run_plan_proposals SET status = 'scheduled', apply_after_date = $2::date, decided_at = now() WHERE id = $1`, [id, today]);
    await history(client, p.plan_id, p.user_id, "proposal_scheduled", p.source, p.id, `${p.title} (after today's run)`, p.changes.map((c) => c.local_date));
  });
  return proposalResponse(userId, id, today);
}

export async function declineProposal(userId: string, id: string, today: string) {
  await inTransaction(async (client) => {
    const p = await lockProposal(client, userId, id);
    if (p.status !== "pending" && p.status !== "scheduled") throw new RunPlanError("proposal_not_pending", 409, { status: p.status });
    await client.query(`UPDATE run_plan_proposals SET status = 'declined', decided_at = now() WHERE id = $1`, [id]);
    await history(client, p.plan_id, p.user_id, "proposal_declined", p.source, p.id, `Kept the plan: ${p.title}`, p.changes.map((c) => c.local_date));
  });
  return proposalResponse(userId, id, today);
}

export async function undoProposal(userId: string, id: string, today: string) {
  await inTransaction(async (client) => {
    const p = await lockPlanAndProposal(client, userId, id);
    if (p.status !== "applied") throw new RunPlanError("proposal_not_pending", 409, { status: p.status });
    if (!p.undo_until || Date.parse(p.undo_until) < Date.now()) throw new RunPlanError("undo_expired", 409);
    // Restoring the old days must still pass the HARD rules against the plan as it is now
    // (e.g. A eased Tue, B then made Wed hard: undoing A would put two hard days in a row).
    const restore = p.changes.filter((c) => c.before && c.local_date >= today).map((c) => ({ local_date: c.local_date, after: c.before! }));
    if (restore.length) {
      const v = validateChanges(await currentValidationContext(client, p, today, restore.map((c) => c.local_date)), restore);
      if (!v.ok) throw new RunPlanError("undo_conflicts_with_plan", 409, { local_date: v.violations[0].local_date, violations: v.violations });
    }
    // `changes` holds exactly the days the apply wrote (past days were dropped then).
    for (const c of p.changes) {
      if (!c.before) continue;
      const r = await client.query(
        `UPDATE run_plan_days SET kind = $3, day = $4::jsonb, note = $5, note_source = 'template', version = version + 1, source = 'user', updated_at = now()
          WHERE plan_id = $1 AND local_date = $2::date AND version = $6::int`,
        [p.plan_id, c.local_date, c.before.kind, JSON.stringify(c.before), c.before.note, (c.before_version ?? 0) + 1],
      );
      if (r.rowCount === 0) throw new RunPlanError("undo_conflict", 409, { local_date: c.local_date });
    }
    const prev = p.checks?.plan_patch?.prev;
    if (prev) await client.query(`UPDATE run_plans SET baseline = baseline || $2::jsonb, updated_at = now() WHERE plan_id = $1`, [p.plan_id, JSON.stringify(prev)]);
    await client.query(`UPDATE run_plan_proposals SET status = 'undone', undo_until = NULL WHERE id = $1`, [id]);
    await history(client, p.plan_id, p.user_id, "proposal_undone", p.source, p.id, `Undid: ${p.title}`, p.changes.map((c) => c.local_date));
  });
  return proposalResponse(userId, id, today);
}

/**
 * "Apply after today's run": apply scheduled proposals for `dates` (a run
 * synced, or the day passed). `today` is the user's local today: days before
 * it (and the run day itself) are never written.
 */
async function applyScheduledFor(planId: string, dates: string[], today: string): Promise<number> {
  if (!dates.length) return 0;
  const rows = await db.query<{ id: string; user_id: string }>(
    `SELECT id, user_id FROM run_plan_proposals WHERE plan_id = $1 AND status = 'scheduled' AND apply_after_date = ANY($2::date[])`,
    [planId, dates],
  );
  let n = 0;
  for (const r of rows) {
    try {
      const out = await inTransaction(async (client) => {
        await lockPlan(client, planId);
        const p = await lockProposal(client, r.user_id, r.id);
        if (p.status !== "scheduled") return null;
        return applyChecked(client, p, today, "after_run");
      });
      if (out?.ok) n++;
    } catch (e) {
      if (!(e instanceof RunPlanError)) throw e;
    }
  }
  return n;
}

/** Pending proposals whose every day has passed are expired (they can't apply any more). */
async function expirePast(planId: string, userId: string, today: string): Promise<void> {
  const rows = await db.query<{ id: string; title: string }>(
    `UPDATE run_plan_proposals p SET status = 'expired', decided_at = now()
      WHERE plan_id = $1 AND status = 'pending'
        AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(p.changes) c WHERE (c->>'local_date')::date >= $2::date)
      RETURNING id, title`,
    [planId, today],
  );
  for (const r of rows) await history(db, planId, userId, "proposal_expired", null, r.id, `${r.title} (its days passed)`, []);
}

export async function listProposals(userId: string, status: string, limit: number, today: string): Promise<ServedProposal[]> {
  const plan = await requirePlan(userId);
  const statuses = status === "all" ? null : status === "scheduled" ? ["scheduled"] : ["pending"];
  const st = await loadState(userId, today, { plan });
  return (await listProposalRows(plan.plan_id, statuses, Math.min(200, Math.max(1, limit)))).map((p) => serveProposal(p, nextRunDate(st)));
}
export async function getProposal(userId: string, id: string, today: string): Promise<ServedProposal> {
  if (!/^[0-9a-f-]{36}$/i.test(id)) throw new RunPlanError("proposal_not_found", 404);
  const rows = await db.query<ProposalRow>(`SELECT ${PROPOSAL_COLS} FROM run_plan_proposals WHERE id = $1 AND user_id = $2`, [id, userId]);
  if (!rows[0]) throw new RunPlanError("proposal_not_found", 404);
  const plan = await activePlan(userId);
  const st = plan ? await loadState(userId, today, { plan }) : null;
  return serveProposal(rows[0], st ? nextRunDate(st) : null);
}

// ─── Create / read / settings ────────────────────────────────────────────

export interface CreatePlanInput {
  goals: unknown;
  target_date?: unknown;
  runs_per_week: unknown;
  difficulty: unknown;
  walk_mode: unknown;
  fixed_walk_days?: unknown;
  coach_notes?: unknown;
  shoe_assignments?: unknown;
  start_date?: unknown;
  initial_days?: unknown;
  source?: unknown;
}
interface CleanSettings {
  goals: Goal[];
  target_date: string | null;
  runs_per_week: number;
  difficulty: Difficulty;
  walk_mode: WalkMode;
  fixed_walk_days: number[];
  coach_notes: string;
  start_date: string;
}

function cleanSettings(input: Partial<CreatePlanInput>, today: string, base?: CleanSettings): CleanSettings {
  let goals: Goal[];
  try {
    goals = input.goals !== undefined ? validateGoals(input.goals) : base!.goals;
  } catch (e) {
    if (e instanceof EngineError) throw new RunPlanError(e.code, 400, e.extra);
    throw e;
  }
  const start = input.start_date !== undefined && input.start_date !== null ? input.start_date : base?.start_date ?? today;
  if (!isIsoDate(start) || (!base && (start < today || start > addDays(today, 60)))) throw new RunPlanError("invalid_today", 400, { field: "start_date" });
  const rpw = input.runs_per_week !== undefined ? Number(input.runs_per_week) : base!.runs_per_week;
  if (!Number.isInteger(rpw) || rpw < 1 || rpw > 7) throw new RunPlanError("invalid_runs_per_week", 400);
  const diff = input.difficulty !== undefined ? Number(input.difficulty) : base!.difficulty;
  if (!Number.isInteger(diff) || diff < 1 || diff > 4) throw new RunPlanError("invalid_difficulty", 400);
  const mode = (input.walk_mode !== undefined ? input.walk_mode : base!.walk_mode) as WalkMode;
  if (!WALK_MODES.includes(mode)) throw new RunPlanError("invalid_walk_mode", 400);
  let fixed: number[] = [];
  if (mode === "fixed") {
    const raw = input.fixed_walk_days !== undefined ? input.fixed_walk_days : base?.fixed_walk_days;
    if (!Array.isArray(raw) || raw.some((d) => !Number.isInteger(d) || d < 0 || d > 6) || new Set(raw).size !== raw.length) throw new RunPlanError("fixed_walk_days_mismatch", 400);
    if (raw.length !== 7 - rpw) throw new RunPlanError("fixed_walk_days_mismatch", 400, { expected: 7 - rpw });
    fixed = [...raw].sort();
  }
  let target: string | null = input.target_date !== undefined ? (input.target_date as string | null) : base?.target_date ?? null;
  if (target != null) {
    if (!isIsoDate(target) || target < addDays(start, 14) || target > addDays(start, 364)) throw new RunPlanError("invalid_target_date", 400);
  }
  const notes = input.coach_notes !== undefined ? input.coach_notes : base?.coach_notes ?? "";
  if (notes != null && typeof notes !== "string") throw new RunPlanError("invalid_goals", 400, { field: "coach_notes" });
  return { goals, target_date: target, runs_per_week: rpw, difficulty: diff as Difficulty, walk_mode: mode, fixed_walk_days: fixed, coach_notes: ((notes as string) ?? "").slice(0, 2000), start_date: start };
}

async function cleanShoes(userId: string, raw: unknown, fallback?: Partial<Record<ShoeRunType, string | null>>): Promise<Partial<Record<ShoeRunType, string | null>>> {
  if (raw === undefined || raw === null) {
    if (fallback) return fallback;
    // Default: the running default on runs, the walking default on walk days.
    const shoes = (await listShoes(userId)).filter((x) => !x.retired_at);
    const run = shoes.find((x) => x.default_for.includes("running"))?.shoe_id ?? null;
    const walk = shoes.find((x) => x.default_for.includes("walking"))?.shoe_id ?? null;
    return { easy: run, long: run, tempo: run, intervals: run, race: run, walk };
  }
  if (typeof raw !== "object" || Array.isArray(raw)) throw new RunPlanError("invalid_shoe", 400);
  const out: Partial<Record<ShoeRunType, string | null>> = { ...(fallback ?? {}) };
  const ids: string[] = [];
  for (const [k, v] of Object.entries(raw as Record<string, unknown>)) {
    if (!SHOE_RUN_TYPES.includes(k as ShoeRunType)) throw new RunPlanError("invalid_shoe", 400, { field: k });
    if (v !== null && typeof v !== "string") throw new RunPlanError("invalid_shoe", 400, { field: k });
    out[k as ShoeRunType] = v as string | null;
    if (v) ids.push(v as string);
  }
  if (ids.length) {
    const ok = await shoesFor(userId, [...new Set(ids)]);
    if (ids.some((i) => !ok.has(i))) throw new RunPlanError("invalid_shoe", 400);
  }
  return out;
}

function baselineFor(profile: FitnessProfile | null): Baseline {
  const v = resolveVdot(profile);
  return { vdot: Math.round(v.vdot * 10) / 10, vdot_source: v.source, pace_factor: 1, experience: profile?.experience ?? null, profile_at: (profile?.computed_at as string) ?? null };
}

function draftPlanRow(userId: string, s: CleanSettings, shoes: Partial<Record<ShoeRunType, string | null>>, baseline: Baseline): PlanRow {
  const now = new Date().toISOString();
  return { plan_id: "00000000-0000-0000-0000-000000000000", user_id: userId, status: "draft", goals: s.goals, target_date: s.target_date, runs_per_week: s.runs_per_week, difficulty: s.difficulty, walk_mode: s.walk_mode, fixed_walk_days: s.fixed_walk_days, coach_notes: s.coach_notes, shoe_assignments: shoes, start_date: s.start_date, baseline, source: "formula", last_open_date: null, last_nightly_date: null, created_at: now, updated_at: now };
}

async function draftDays(ctx: PlanContext, userId: string, today: string): Promise<{ local_date: string; day: Day }[]> {
  const runs = await loadRuns(userId, addDays(today, -60), today);
  const hist = runs.filter((r) => r.local_date < today).map((r) => ({ local_date: r.local_date, distance_mi: r.distance_mi }));
  const from = ctx.plan.start_date;
  const to = ctx.plan.target_date && ctx.plan.target_date < addDays(from, DAYS_AHEAD - 1) ? addDays(weekStart(ctx.plan.target_date), 6) : addDays(from, DAYS_AHEAD - 1);
  // Profile-reported longest run counts as history (same point loadState uses).
  const { updated_at } = await getProfile(userId);
  hist.push(...profileHistory(ctx.profile, updated_at ?? new Date().toISOString(), today));
  return generateDays(ctx.gen, from, to, hist);
}

export async function previewPlan(userId: string, input: CreatePlanInput, today: string) {
  const s = cleanSettings(input, today);
  const shoes = await cleanShoes(userId, input.shoe_assignments);
  const { profile } = await getProfile(userId);
  const ctx = contextFor(draftPlanRow(userId, s, shoes, baselineFor(profile)), profile);
  const days = await draftDays(ctx, userId, today);
  const warnings: string[] = [];
  if (!profile) warnings.push("No fitness profile yet: paces use a conservative default until the phone uploads one.");
  if (profile?.calibration_needed) warnings.push("History is thin: the first run is a calibration run.");
  const shoeMap = await shoesFor(userId, Object.values(shoes).filter((x): x is string => !!x));
  return {
    plan: servePlan(ctx, today),
    days: days.map((d) => ({ ...d.day, local_date: d.local_date, weekday: weekdayIndex(d.local_date), note_source: "template", shoe: shoes[shoeRunTypeFor(d.day.kind)] ? shoeMap.get(shoes[shoeRunTypeFor(d.day.kind)]!) ?? null : null, status: "planned", completed: null, grade: null, pending_proposal_ids: [], version: 1 })),
    warnings,
  };
}

export async function createPlan(userId: string, input: CreatePlanInput, today: string) {
  const s = cleanSettings(input, today);
  const shoes = await cleanShoes(userId, input.shoe_assignments);
  const source = input.source == null ? "formula" : String(input.source);
  if (!["formula", "apple", "anthropic"].includes(source)) throw new RunPlanError("invalid_source", 400);
  const { profile } = await getProfile(userId);
  const baseline = baselineFor(profile);
  const ctx = contextFor(draftPlanRow(userId, s, shoes, baseline), profile);
  let days = await draftDays(ctx, userId, today);
  // AI Coach plan build: the model's days, validated against the HARD rules.
  if (input.initial_days != null) {
    if (!Array.isArray(input.initial_days) || input.initial_days.length > 120) throw new RunPlanError("invalid_day_spec", 400);
    const byDate = new Map(days.map((d) => [d.local_date, d.day]));
    const changes: ProposedChange[] = (input.initial_days as any[]).map((x) => {
      if (!isIsoDate(x?.local_date) || !byDate.has(x.local_date)) throw new RunPlanError("date_outside_plan", 400, { local_date: x?.local_date });
      const cur = byDate.get(x.local_date)!;
      try {
        return { local_date: x.local_date, after: buildDay(x.day, ctx.bctx, { phase: cur.phase, week_index: cur.week_index, flex: cur.flex }) };
      } catch (e) {
        if (e instanceof EngineError) throw new RunPlanError(e.code, 400, e.extra);
        throw e;
      }
    });
    const runs = await loadRuns(userId, addDays(today, -60), today);
    const prof = await getProfile(userId);
    const v = validateChanges({ today, days: byDate, actual: [...runs.map((r) => ({ local_date: r.local_date, distance_mi: r.distance_mi })), ...profileHistory(prof.profile, prof.updated_at ?? new Date().toISOString(), today)] }, changes);
    if (!v.ok) throw new RunPlanError("hard_rule_violation", 422, { violations: v.violations });
    for (const c of changes) byDate.set(c.local_date, c.after);
    days = [...byDate].map(([local_date, day]) => ({ local_date, day }));
  }
  const planId = await inTransaction(async (client) => {
    let r;
    try {
      r = await client.query<{ plan_id: string }>(
        `INSERT INTO run_plans (user_id, goals, target_date, runs_per_week, difficulty, walk_mode, fixed_walk_days, coach_notes, shoe_assignments, start_date, baseline, source)
         VALUES ($1, $2::jsonb, $3::date, $4, $5, $6, $7::jsonb, $8, $9::jsonb, $10::date, $11::jsonb, $12) RETURNING plan_id`,
        [userId, JSON.stringify(s.goals), s.target_date, s.runs_per_week, s.difficulty, s.walk_mode, JSON.stringify(s.fixed_walk_days), s.coach_notes, JSON.stringify(shoes), s.start_date, JSON.stringify(baseline), source],
      );
    } catch (e: any) {
      if (e?.code === "23505") throw new RunPlanError("plan_exists", 409);
      throw e;
    }
    const id = r.rows[0].plan_id;
    await insertDays(client, id, days, source);
    await history(client, id, userId, "plan_created", source, null, `Plan created: ${s.goals.map((g) => g.type === "distance_time" ? g.distance : g.type).join(", ")}`, []);
    return id;
  });
  void planId;
  return getCurrent(userId, today);
}

export async function getCurrent(userId: string, today: string) {
  const plan = await requirePlan(userId);
  const st = await loadState(userId, today, { plan });
  const week = await serveDays(st, weekStart(today), addDays(weekStart(today), 6));
  const nr = nextRunDate(st);
  const ahead = nr ? await serveDays(st, nr, nr) : [];
  const pending = st.pending.filter((p) => p.status === "pending" || p.status === "scheduled").map((p) => serveProposal(p, nr));
  const [ai, profile] = await Promise.all([getAiStatus(userId, true), getProfile(userId)]);
  return {
    plan: servePlan(st, today),
    today: week.find((d) => d.local_date === today) ?? null,
    week,
    next_run: ahead[0] ?? null,
    pending_proposals: pending.filter((p) => p.kind !== "walk_day_earned" && p.kind !== "walk_day_needed"),
    suggestions: pending.filter((p) => p.kind === "walk_day_earned" || p.kind === "walk_day_needed"),
    fitness_profile_at: profile.updated_at,
    ai,
  };
}

export async function getDays(userId: string, from: string, to: string, today: string) {
  if (from > to) [from, to] = [to, from];
  if ((Date.parse(to) - Date.parse(from)) / 86_400_000 > MAX_RANGE_DAYS) throw new RunPlanError("range_too_large", 400, { max_days: MAX_RANGE_DAYS });
  const plan = await requirePlan(userId);
  const back = Math.max(0, Math.round((Date.parse(today) - Date.parse(from)) / 86_400_000));
  const ahead = Math.max(DAYS_AHEAD, Math.round((Date.parse(to) - Date.parse(today)) / 86_400_000));
  const st = await loadState(userId, today, { plan, back, ahead: Math.min(ahead, MAX_RANGE_DAYS) });
  return serveDays(st, from, to);
}

const STRUCTURAL = ["goals", "target_date", "runs_per_week", "difficulty", "walk_mode", "fixed_walk_days"] as const;

/** The user's own edit: applies directly (their decision), recorded as source 'user'. */
export async function updatePlan(userId: string, patch: Record<string, unknown>, today: string) {
  const plan = await requirePlan(userId);
  const base: CleanSettings = { goals: plan.goals, target_date: plan.target_date, runs_per_week: plan.runs_per_week, difficulty: plan.difficulty, walk_mode: plan.walk_mode, fixed_walk_days: plan.fixed_walk_days, coach_notes: plan.coach_notes, start_date: plan.start_date };
  const s = cleanSettings({ ...patch, start_date: undefined } as Partial<CreatePlanInput>, today, base);
  const shoes = patch.shoe_assignments !== undefined ? await cleanShoes(userId, patch.shoe_assignments, plan.shoe_assignments) : plan.shoe_assignments;
  const structural = STRUCTURAL.some((k) => patch[k] !== undefined);
  await inTransaction(async (client) => {
    await client.query(
      `UPDATE run_plans SET goals = $2::jsonb, target_date = $3::date, runs_per_week = $4, difficulty = $5, walk_mode = $6, fixed_walk_days = $7::jsonb,
         coach_notes = $8, shoe_assignments = $9::jsonb, updated_at = now() WHERE plan_id = $1`,
      [plan.plan_id, JSON.stringify(s.goals), s.target_date, s.runs_per_week, s.difficulty, s.walk_mode, JSON.stringify(s.fixed_walk_days), s.coach_notes, JSON.stringify(shoes)],
    );
    if (structural) {
      const tomorrow = addDays(today, 1);
      await client.query(`DELETE FROM run_plan_days WHERE plan_id = $1 AND local_date >= $2::date`, [plan.plan_id, tomorrow]);
      const sup = await client.query<{ id: string }>(
        `UPDATE run_plan_proposals p SET status = 'superseded', decided_at = now()
          WHERE plan_id = $1 AND status IN ('pending', 'scheduled')
            AND EXISTS (SELECT 1 FROM jsonb_array_elements(p.changes) c WHERE (c->>'local_date')::date >= $2::date)
          RETURNING id`,
        [plan.plan_id, tomorrow],
      );
      for (const r of sup.rows) await history(client, plan.plan_id, userId, "proposal_superseded", null, r.id, "Plan settings changed", []);
    }
    await history(client, plan.plan_id, userId, "settings_changed", "user", null, `Settings changed: ${Object.keys(patch).filter((k) => k !== "today").join(", ")}`, [], structural ? { regenerated_from: addDays(today, 1) } : null);
  });
  return getCurrent(userId, today);
}

export async function archivePlan(userId: string) {
  const plan = await activePlan(userId);
  if (!plan) return { ok: true as const, archived: false };
  await inTransaction(async (client) => {
    await client.query(`UPDATE run_plans SET status = 'archived', archived_at = now(), updated_at = now() WHERE plan_id = $1`, [plan.plan_id]);
    await client.query(`UPDATE run_plan_proposals SET status = 'expired', decided_at = now() WHERE plan_id = $1 AND status IN ('pending', 'scheduled')`, [plan.plan_id]);
    await history(client, plan.plan_id, userId, "plan_archived", "user", null, "Plan archived", []);
  });
  return { ok: true as const, archived: true };
}

export async function getHistory(userId: string, limit: number, before: string | null) {
  const plan = await requirePlan(userId);
  const rows = await db.query(
    `SELECT id::text AS id, at, event, source, proposal_id, summary, dates FROM run_plan_history
      WHERE plan_id = $1 AND ($2::timestamptz IS NULL OR at < $2::timestamptz) ORDER BY at DESC, id DESC LIMIT $3`,
    [plan.plan_id, before, Math.min(200, Math.max(1, limit))],
  );
  return { entries: rows };
}

// ─── Grades ───────────────────────────────────────────────────────────────

interface GradeRow {
  local_date: string; score: number; completion: number; on_target: number; consistency: number; source: string;
  summary: string | null; summary_source: string; workout_id: string | null; graded_at: string; inputs: (GradeInputs & { kind?: string; pace_delta?: number | null; hr_delta?: number | null }) | null; kind?: string;
}
async function loadGrades(planId: string, from: string, to: string): Promise<Map<string, GradeRow>> {
  const rows = await db.query<GradeRow>(
    `SELECT g.local_date::text AS local_date, g.score, g.completion, g.on_target, g.consistency, g.source, g.summary, g.summary_source, g.workout_id, g.graded_at, g.inputs, d.kind
       FROM run_plan_grades g LEFT JOIN run_plan_days d ON d.plan_id = g.plan_id AND d.local_date = g.local_date
      WHERE g.plan_id = $1 AND g.local_date BETWEEN $2::date AND $3::date`,
    [planId, from, to],
  );
  return new Map(rows.map((r) => [r.local_date, r]));
}
function gradeRecord(g: GradeRow): GradeRecord {
  return { local_date: g.local_date, kind: (g.kind ?? "easy") as GradeRecord["kind"], score: g.score, on_target: g.on_target, pace_delta: g.inputs?.pace_delta ?? null, hr_delta: g.inputs?.hr_delta ?? null };
}

async function storeGrade(st: PlanState, date: string, workoutId: string | null, inputs: GradeInputs, source: "phone" | "server"): Promise<ServedGrade> {
  const day = st.days.get(date)!;
  const g = gradeSession(day, inputs);
  const summary = gradeSummaryTemplate(day, g);
  const rows = await db.query<GradeRow>(
    `INSERT INTO run_plan_grades (plan_id, local_date, user_id, workout_id, score, completion, on_target, consistency, source, summary, summary_source, inputs, graded_at)
     VALUES ($1, $2::date, $3, $4, $5, $6, $7, $8, $9, $10, 'template', $11::jsonb, now())
     ON CONFLICT (plan_id, local_date) DO UPDATE SET workout_id = EXCLUDED.workout_id, score = EXCLUDED.score, completion = EXCLUDED.completion,
       on_target = EXCLUDED.on_target, consistency = EXCLUDED.consistency, source = EXCLUDED.source,
       summary = CASE WHEN run_plan_grades.summary_source = 'template' THEN EXCLUDED.summary ELSE run_plan_grades.summary END,
       inputs = EXCLUDED.inputs, graded_at = now()
     WHERE EXCLUDED.source = 'phone' OR run_plan_grades.source = 'server'
     RETURNING local_date::text AS local_date, score, completion, on_target, consistency, source, summary, summary_source, workout_id, graded_at, inputs`,
    [st.plan.plan_id, date, st.plan.user_id, workoutId, g.score, g.completion, g.on_target, g.consistency, source, summary, JSON.stringify({ ...inputs, pace_delta: g.pace_delta, hr_delta: g.hr_delta })],
  );
  const r = rows[0] ?? st.grades.get(date)!;
  if (rows[0]) st.grades.set(date, { ...rows[0], kind: day.kind });
  return { score: r.score, completion: r.completion, on_target: r.on_target, consistency: r.consistency, source: r.source, summary: r.summary, summary_source: r.summary_source, workout_id: r.workout_id, graded_at: r.graded_at };
}

export async function submitGrade(userId: string, body: any, today: string) {
  const date = body?.local_date;
  if (!isIsoDate(date) || date > today || date < addDays(today, -7)) throw new RunPlanError("invalid_today", 400, { field: "local_date" });
  const st = await loadState(userId, today);
  const day = st.days.get(date);
  if (!day || day.kind === "walk") throw new RunPlanError("day_not_found", 404);
  const n = (v: unknown, lo: number, hi: number) => (v == null ? null : Number.isFinite(Number(v)) && Number(v) >= lo && Number(v) <= hi ? Number(v) : (() => { throw new RunPlanError("invalid_checkin", 400); })());
  const segs = Array.isArray(body.segments) ? body.segments.slice(0, 100).map((s: any) => ({ index: n(s.index, 0, 200)!, scored_s: n(s.scored_s, 0, 36000)!, in_band_s: n(s.in_band_s, 0, 36000)!, too_fast_s: n(s.too_fast_s, 0, 36000) ?? 0, too_slow_s: n(s.too_slow_s, 0, 36000) ?? 0, avg_pace_s: n(s.avg_pace_s, 120, 2400), avg_hr: n(s.avg_hr, 40, 230) })) : undefined;
  const inputs: GradeInputs = {
    actual_distance_mi: n(body.actual_distance_mi, 0, 100) ?? st.runs.filter((r) => r.local_date === date).reduce((a, r) => a + r.distance_mi, 0),
    segments: segs,
    rep_paces_s: Array.isArray(body.rep_paces_s) ? body.rep_paces_s.slice(0, 40).map((x: unknown) => n(x, 60, 2400)!) : undefined,
    easy_hr_drift_pct: n(body.easy_hr_drift_pct, -50, 100),
    avg_hr: n(body.avg_hr, 40, 230),
  };
  const grade = await storeGrade(st, date, typeof body.workout_id === "string" ? body.workout_id.slice(0, 255) : null, inputs, "phone");
  const proposals = await runFormulaPassInState(st, "after_run");
  return { grade, proposals };
}

/** Server fallback grade from distance, average pace and splits. */
async function serverGrade(st: PlanState, date: string): Promise<void> {
  const day = st.days.get(date);
  if (!day || day.kind === "walk") return;
  const existing = st.grades.get(date);
  if (existing?.source === "phone") return;
  const runs = st.runs.filter((r) => r.local_date === date);
  if (!runs.length) return;
  const mi = runs.reduce((a, r) => a + r.distance_mi, 0);
  const secs = runs.reduce((a, r) => a + (r.moving_s ?? r.duration_s), 0);
  const splits = runs.flatMap((r) => r.splits ?? []).filter((s) => (s.distance_mi ?? 0) >= 0.9 && s.pace_s).map((s) => s.pace_s!);
  await storeGrade(st, date, runs[runs.length - 1].workout_id, { actual_distance_mi: mi, avg_pace_s: mi > 0 ? secs / mi : null, split_paces_s: splits }, "server");
}

// ─── Check-ins ────────────────────────────────────────────────────────────

export async function recordCheckin(userId: string, body: any, today: string) {
  const date = body?.local_date ?? today;
  if (!isIsoDate(date) || date < addDays(today, -1) || date > addDays(today, 1)) throw new RunPlanError("invalid_checkin", 400, { field: "local_date" });
  const int = (v: unknown, lo: number, hi: number) => {
    if (v == null) return null;
    const x = Number(v);
    if (!Number.isFinite(x) || x < lo || x > hi) throw new RunPlanError("invalid_checkin", 400);
    return Math.round(x);
  };
  const energy = int(body.energy, 0, 10);
  const soreness = int(body.soreness, 0, 10);
  const time = int(body.time_available_min, 10, 240);
  const further = body.go_further_mi == null ? null : Number(body.go_further_mi);
  if (further != null && (!Number.isFinite(further) || further <= 0 || further > 60)) throw new RunPlanError("invalid_checkin", 400);
  if (body.text != null && (typeof body.text !== "string" || body.text.length > 1000)) throw new RunPlanError("invalid_checkin", 400);
  const st = await loadState(userId, today);
  const day = st.days.get(date);
  if (further != null && day && further > Math.max(2, day.distance_mi * 2)) throw new RunPlanError("invalid_checkin", 400, { field: "go_further_mi" });
  const ins = await db.query<{ id: string; created_at: string }>(
    `INSERT INTO run_plan_checkins (user_id, plan_id, local_date, time_available_min, energy, soreness, go_further_mi, text, coach_mode)
     VALUES ($1, $2, $3::date, $4, $5, $6, $7, $8, $9) RETURNING id, created_at`,
    [userId, st.plan.plan_id, date, time, energy, soreness, further, body.text ?? null, body.coach_mode == null ? null : Boolean(body.coach_mode)],
  );
  // Low energy several days running → a lighter few days.
  const recent = await db.query<{ local_date: string; low: boolean }>(
    `SELECT local_date::text AS local_date, bool_or(energy <= 3 OR soreness >= 7) AS low FROM run_plan_checkins
      WHERE user_id = $1 AND local_date BETWEEN $2::date - 6 AND $2::date GROUP BY local_date`,
    [userId, date],
  );
  const lowDays = new Map(recent.map((r) => [r.local_date, r.low]));
  let streak = 0;
  for (let d = date; lowDays.get(d); d = addDays(d, -1)) streak++;
  let proposal: ServedProposal | null = null;
  const draft = checkinProposal(adaptContext({ ...st, pending: [] }), { local_date: date, time_available_min: time, energy, soreness, go_further_mi: further }, streak);
  if (draft) {
    try {
      proposal = await createProposalInState(st, { source: "formula", ...draft, dedupe_key: null });
    } catch (e) {
      if (!(e instanceof RunPlanError)) throw e;
      console.warn("[runPlans] check-in proposal refused:", e.code, e.extra);
    }
  }
  if (proposal) await db.query(`UPDATE run_plan_checkins SET proposal_id = $2 WHERE id = $1`, [ins[0].id, proposal.id]);
  return {
    checkin: { id: ins[0].id, created_at: ins[0].created_at, local_date: date, time_available_min: time, energy, soreness, go_further_mi: further, text: body.text ?? null, coach_mode: body.coach_mode ?? null, proposal_id: proposal?.id ?? null },
    proposal,
  };
}

/** Counted runs (and optionally walks) in [from, to], ≤ 120 days, with splits. User-facing coach MCP `get_runs`. */
export async function getRuns(userId: string, from: string, to: string, includeWalks = false): Promise<ActualRun[]> {
  if (!isIsoDate(from) || !isIsoDate(to)) throw new RunPlanError("invalid_today", 400, { field: "from/to" });
  if (from > to) [from, to] = [to, from];
  if ((Date.parse(to) - Date.parse(from)) / 86_400_000 > MAX_RANGE_DAYS) throw new RunPlanError("range_too_large", 400, { max_days: MAX_RANGE_DAYS });
  return loadRuns(userId, from, to, includeWalks);
}

export async function listCheckins(userId: string, from: string, to: string) {
  return db.query(
    `SELECT id, local_date::text AS local_date, time_available_min, energy, soreness, go_further_mi, text, coach_mode, proposal_id, created_at
       FROM run_plan_checkins WHERE user_id = $1 AND local_date BETWEEN $2::date AND $3::date ORDER BY created_at DESC LIMIT 200`,
    [userId, from, to],
  );
}

// ─── Formula pass (after upload, first open, nightly) ────────────────────

export type Trigger = "after_run" | "first_open" | "nightly" | "checkin" | "profile";

async function runFormulaPassInState(st: PlanState, _trigger: Trigger): Promise<ServedProposal[]> {
  await expirePast(st.plan.plan_id, st.plan.user_id, st.today);
  const ctx = adaptContext(st);
  const drafts: ProposalDraft[] = [];
  const ret = returnFromBreakProposal(ctx);
  if (ret) drafts.push(ret);
  else {
    drafts.push(...missedRunProposals(ctx));
    const pace = paceUpdateProposal(ctx);
    if (pace) drafts.push(pace);
    drafts.push(...walkDayProposals(ctx));
  }
  const out: ServedProposal[] = [];
  for (const d of drafts) {
    // Each draft is built on the plan as it stands; skip any that now overlap a newer pending one.
    const busy = new Set(st.pending.flatMap((p) => p.changes.map((c) => c.local_date)));
    if (d.changes.some((c) => busy.has(c.local_date))) continue;
    try {
      const patch = d.plan_patch ? { ...d.plan_patch, prev: { pace_factor: st.plan.baseline.pace_factor ?? 1 } } : null;
      const p = await createProposalInState(st, { source: "formula", kind: d.kind, title: d.title, reason: d.reason, goal_impact: d.goal_impact, changes: d.changes, deviation_reason: d.deviation_reason ?? (d.kind === "pace_update" ? "Pace update (research rule 20)." : "Formula adjustment."), dedupe_key: d.dedupe_key, plan_patch: patch as any });
      if (p) out.push(p);
    } catch (e) {
      if (!(e instanceof RunPlanError)) throw e;
      console.warn("[runPlans] formula proposal refused:", e.code, JSON.stringify(e.extra));
    }
  }
  return out;
}

/** A new fitness profile VDOT differing ≥ 2% from the plan's → pace_update proposal. */
async function profilePaceProposal(userId: string, today: string): Promise<ServedProposal[]> {
  const st = await loadState(userId, today);
  const v = st.profile?.vdot;
  if (!v) return [];
  const eff = st.plan.baseline.vdot / (st.plan.baseline.pace_factor ?? 1);
  if (Math.abs(v / eff - 1) < 0.02) return [];
  const paces = pacesFor(v, "vdot");
  const bctx = { ...st.bctx, paces };
  const changes: ProposedChange[] = [];
  for (const d of dateRange(today, addDays(today, 14))) {
    const day = st.days.get(d);
    if (!day || day.kind === "walk" || day.kind === "race") continue;
    changes.push({ local_date: d, after: rebuild(day, { pace_factor: null }, bctx) });
  }
  if (!changes.length) return [];
  const faster = v > eff;
  const p = await createProposalInState(st, {
    source: "formula",
    kind: "pace_update",
    title: faster ? "Your fitness went up: faster paces" : "Gentler paces for now",
    reason: faster ? "Your latest runs show a higher fitness estimate." : "Your latest runs show a lower fitness estimate.",
    goal_impact: { label: "5K estimate", before_s: estimateFor(eff, 3.10686), after_s: estimateFor(v, 3.10686) },
    changes,
    deviation_reason: "New fitness estimate (research rule 20).",
    dedupe_key: `vdot:${Math.round(v * 10)}:${st.profile?.computed_at ?? today}`,
    plan_patch: { vdot: v, pace_factor: 1, prev: { vdot: st.plan.baseline.vdot, pace_factor: st.plan.baseline.pace_factor ?? 1 } } as any,
  });
  return p ? [p] : [];
}

export async function runFormulaPass(userId: string, today: string, trigger: Trigger): Promise<ServedProposal[]> {
  const plan = await activePlan(userId);
  if (!plan) return [];
  await applyScheduledFor(plan.plan_id, dateRange(addDays(today, -7), addDays(today, -1)), today);
  const st = await loadState(userId, today, { plan });
  return runFormulaPassInState(st, trigger);
}

/** First app open of the day: once per local day. */
export async function openPlan(userId: string, today: string) {
  const plan = await requirePlan(userId);
  const claimed = await db.query(`UPDATE run_plans SET last_open_date = $2::date WHERE plan_id = $1 AND (last_open_date IS NULL OR last_open_date < $2::date) RETURNING 1`, [plan.plan_id, today]);
  const fresh = claimed.length ? await runFormulaPass(userId, today, "first_open") : [];
  const st = await loadState(userId, today);
  const nr = nextRunDate(st);
  return { ran: claimed.length > 0, new_proposals: fresh, pending_proposals: st.pending.map((p) => serveProposal(p, nr)), ai: await getAiStatus(userId, true) };
}

/** Hook from the workout upload (fire-and-forget): apply after-run proposals, grade, formula pass. */
export async function onWorkoutsUploaded(userId: string, workoutIds: string[]): Promise<void> {
  if (!workoutIds.length) return;
  const plan = await activePlan(userId);
  if (!plan) return;
  const rows = await db.query<{ local_date: string }>(
    `SELECT DISTINCT local_date::text AS local_date FROM workouts WHERE user_id = $1 AND workout_id = ANY($2) AND workout_type = 'running' AND ${countedWorkoutSql("workouts")}
       AND local_date >= CURRENT_DATE - 7`,
    [userId, workoutIds],
  );
  if (!rows.length) return;
  const dates = rows.map((r) => r.local_date).sort();
  const lt = await db.query<{ today: string }>(`SELECT ((now() AT TIME ZONE 'UTC') + ${userOffsetMinutesSql("$1")} * INTERVAL '1 minute')::date::text AS today`, [userId]);
  const today = lt[0].today > dates[dates.length - 1] ? lt[0].today : dates[dates.length - 1];
  await applyScheduledFor(plan.plan_id, dates, today);
  const st = await loadState(userId, today, { plan });
  for (const d of dates) await serverGrade(st, d);
  await runFormulaPassInState(st, "after_run");
}

/** Nightly pass for one plan (cron decides who is due). */
export async function nightlyPass(userId: string, localToday: string): Promise<boolean> {
  const plan = await activePlan(userId);
  if (!plan) return false;
  const claimed = await db.query(`UPDATE run_plans SET last_nightly_date = $2::date WHERE plan_id = $1 AND (last_nightly_date IS NULL OR last_nightly_date < $2::date) RETURNING 1`, [plan.plan_id, localToday]);
  if (!claimed.length) return false;
  await runFormulaPass(userId, localToday, "nightly");
  return true;
}

// ─── Coach tools (phone's Apple model; server Anthropic loop) ────────────

export async function getCoachContext(userId: string, today: string, back = 14, ahead = 14) {
  back = Math.min(28, Math.max(0, back));
  ahead = Math.min(28, Math.max(1, ahead));
  const st = await loadState(userId, today, { back: Math.max(back, 35) });
  const actx = adaptContext(st);
  const hist = [...st.runs.filter((r) => r.local_date < today).map((r) => ({ local_date: r.local_date, distance_mi: r.distance_mi })), ...st.profileRun];
  for (const [d, day] of st.days) if (d >= today && day.kind !== "walk") hist.push({ local_date: d, distance_mi: day.distance_mi });
  const limits: Record<string, number> = {};
  for (const d of dateRange(today, addDays(today, ahead))) limits[d] = spikeLimit(d, hist);
  const sig = fatigueSignals(actx);
  const past = await serveDays(st, addDays(today, -back), addDays(today, -1));
  const aheadDays = await serveDays(st, today, addDays(today, ahead));
  const missed = past.filter((d) => d.is_key && d.status === "missed").map((d) => d.local_date);
  const last = st.runs.filter((r) => r.local_date < today).map((r) => r.local_date).sort().pop();
  const [checkins, decisions] = await Promise.all([
    listCheckins(userId, addDays(today, -back), today),
    db.query(`SELECT id AS proposal_id, kind, status, source, decided_at FROM run_plan_proposals WHERE plan_id = $1 AND status IN ('applied','declined','undone') ORDER BY decided_at DESC NULLS LAST LIMIT 10`, [st.plan.plan_id]),
  ]);
  const slim = (d: ServedDay) => ({ ...d, segments: d.segments.map(({ feel: _f, ...s }) => s) });
  const lowStreak = (() => {
    let n = 0;
    const byDate = new Map((checkins as any[]).map((c) => [c.local_date, (c.energy ?? 10) <= 3 || (c.soreness ?? 0) >= 7]));
    for (let d = today; byDate.get(d); d = addDays(d, -1)) n++;
    return n;
  })();
  const weekDone = dateRange(weekStart(today), addDays(today, -1)).filter((d) => past.find((x) => x.local_date === d)?.status === "done").length;
  return {
    today,
    plan: servePlan(st, today),
    fitness_profile: st.profile,
    paces: st.bctx.paces,
    hr: { easy_ceiling: st.bctx.hr.easy_ceiling, tempo: st.bctx.hr.tempo, zones: st.bctx.hr.zones },
    limits: { spike_limit_mi_by_date: limits, longest_run_30d_mi: Math.max(0, ...hist.filter((h) => h.local_date >= addDays(today, -30) && h.local_date < today).map((h) => h.distance_mi)), hard_sessions_per_week: hardSessionsFor(st.plan.runs_per_week, st.plan.difficulty, st.gen.profile?.experience ?? null, st.plan.goals) },
    past: past.map(slim),
    ahead: aheadDays.map(slim),
    checkins,
    pending_proposals: st.pending.map((p) => serveProposal(p, nextRunDate(st))),
    recent_decisions: decisions,
    signals: { days_since_last_run: last ? Math.round((Date.parse(today) - Date.parse(last)) / 86_400_000) : null, missed_key_sessions: missed, fatigue_flag: sig.fatigue_flag, resting_hr_delta: sig.resting_hr_delta, hrv_below_baseline: sig.hrv_below_baseline, acwr: sig.acwr, hard_efforts_last_6d: sig.hard_efforts_last_6d, low_energy_streak: lowStreak, runs_done_this_week: weekDone, walk_day_earned: st.pending.some((p) => p.kind === "walk_day_earned"), overdoing_it: sig.hard_efforts_last_6d >= 4 || sig.fatigue_flag },
    coach_notes: st.plan.coach_notes,
    focus: focusOf(st.plan.goals),
    rules: COACH_RULES_TEXT,
    formula_proposals: st.pending.filter((p) => p.source === "formula").map((p) => serveProposal(p)),
  };
}

export async function coachBuildDay(userId: string, today: string, date: string, spec: DaySpec) {
  const st = await loadState(userId, today);
  const cur = st.days.get(date);
  if (!cur) throw new RunPlanError("date_outside_plan", 400);
  let day: Day;
  try {
    day = buildDay(spec, st.bctx, { phase: cur.phase, week_index: cur.week_index, flex: cur.flex });
  } catch (e) {
    if (e instanceof EngineError) throw new RunPlanError(e.code, 400, e.extra);
    throw e;
  }
  const v = date >= today ? validateChanges(adaptContext(st), [{ local_date: date, after: day }]) : { violations: [], deviations: [] };
  return { day, violations: v.violations, deviations: v.deviations };
}

export async function coachValidate(userId: string, today: string, changes: { local_date: string; after: DaySpec }[]) {
  if (!Array.isArray(changes) || !changes.length || changes.length > 31) throw new RunPlanError("invalid_day_spec", 400);
  const st = await loadState(userId, today);
  const built: ProposedChange[] = changes.map((c) => {
    const cur = st.days.get(c.local_date);
    if (!cur) throw new RunPlanError("date_outside_plan", 400, { local_date: c.local_date });
    if (c.local_date < today) throw new RunPlanError("past_date", 400);
    try {
      return { local_date: c.local_date, after: buildDay(c.after, st.bctx, { phase: cur.phase, week_index: cur.week_index, flex: cur.flex }) };
    } catch (e) {
      if (e instanceof EngineError) throw new RunPlanError(e.code, 400, e.extra);
      throw e;
    }
  });
  const v = validateChanges(adaptContext(st), built);
  return { ok: v.ok, violations: v.violations, deviations: v.deviations, checks: v.checks, days: built.map((b) => ({ local_date: b.local_date, ...b.after })) };
}

export async function coachOptions(userId: string, today: string, date: string, intent: OptionIntent, extra: { minutes?: number; to_date?: string }) {
  const st = await loadState(userId, today);
  if (!st.days.has(date)) throw new RunPlanError("date_outside_plan", 400);
  if (date < today) throw new RunPlanError("past_date", 400);
  const ctx = adaptContext(st);
  return {
    options: optionsFor(ctx, date, intent, extra).map((o) => {
      const v = validateChanges(ctx, o.changes);
      return { label: o.label, changes: o.changes.map((c) => ({ local_date: c.local_date, after: c.after.spec, day: c.after })), checks: v.checks, deviations: v.deviations };
    }),
  };
}

export async function coachEstimate(userId: string, distance: string, distanceMi: number | null) {
  const plan = await activePlan(userId);
  const { profile } = await getProfile(userId);
  const v = plan ? { vdot: plan.baseline.vdot / (plan.baseline.pace_factor ?? 1), source: "vdot" } : resolveVdot(profile);
  const d = distance === "custom" ? distanceMi : goalDistanceMi({ distance: distance as any });
  if (!d || d <= 0 || d > 50) throw new RunPlanError("invalid_goals", 400, { field: "distance" });
  return { distance_mi: Math.round(d * 100) / 100, estimate_s: estimateFor(v.vdot, d), method: v.source };
}

export async function putCoachNotes(userId: string, today: string, source: string, notes: unknown, summaries: unknown) {
  if (!["apple", "anthropic", "overseer", "user_claude"].includes(source)) throw new RunPlanError("invalid_source", 400);
  const plan = await requirePlan(userId);
  const list = (x: unknown) => (x == null ? [] : Array.isArray(x) && x.length <= 31 ? x : (() => { throw new RunPlanError("invalid_day_spec", 400); })());
  let updated = 0;
  for (const n of list(notes) as any[]) {
    if (!isIsoDate(n?.local_date) || typeof n?.note !== "string" || n.note.length > 600 || n.local_date < today) throw new RunPlanError("invalid_day_spec", 400, { field: "notes" });
    const r = await db.query(
      `UPDATE run_plan_days SET note = $3, note_source = $4, day = jsonb_set(day, '{note}', to_jsonb($3::text)), updated_at = now() WHERE plan_id = $1 AND local_date = $2::date RETURNING 1`,
      [plan.plan_id, n.local_date, n.note, source],
    );
    updated += r.length;
  }
  for (const s of list(summaries) as any[]) {
    if (!isIsoDate(s?.local_date) || typeof s?.summary !== "string" || s.summary.length > 600 || s.local_date > today) throw new RunPlanError("invalid_day_spec", 400, { field: "grade_summaries" });
    const r = await db.query(`UPDATE run_plan_grades SET summary = $3, summary_source = $4 WHERE plan_id = $1 AND local_date = $2::date RETURNING 1`, [plan.plan_id, s.local_date, s.summary, source]);
    updated += r.length;
  }
  return { ok: true as const, updated };
}

export async function getStatus(userId: string, plus: boolean) {
  const [plan, ai, profile] = await Promise.all([activePlan(userId), getAiStatus(userId, plus), getProfile(userId)]);
  const pending = plan ? await db.query<{ n: number }>(`SELECT COUNT(*)::int AS n FROM run_plan_proposals WHERE plan_id = $1 AND status = 'pending'`, [plan.plan_id]) : [];
  return { plus, has_plan: !!plan, plan_id: plan?.plan_id ?? null, ai, fitness_profile_at: profile.updated_at, pending_proposals: pending[0]?.n ?? 0 };
}

export type { AiStatus };

// ─── Overseer (admin connector) ───────────────────────────────────────────

async function isAdmin(userId: string): Promise<boolean> {
  const r = await db.query<{ role: string | null }>(`SELECT role FROM users WHERE user_id = $1`, [userId]);
  return r[0]?.role === "admin";
}

export interface OverseerChange {
  title?: string;
  reason?: string;
  changes: { local_date: string; day: DaySpec }[];
  deviation_reason?: string | null;
}

/** Overseer `propose_plan_change`: a pending proposal (source 'overseer') on ANY user's plan; the user decides. */
export async function proposeOverseerChange(adminId: string, targetUserId: string, change: OverseerChange, today: string): Promise<ServedProposal> {
  if (!(await isAdmin(adminId))) throw new RunPlanError("admin_required", 403);
  return createProposal(targetUserId, { source: "overseer", kind: "adjust", title: change.title ?? "Suggested change", reason: change.reason ?? "From the coach review.", changes: change.changes.map((c) => ({ local_date: c.local_date, spec: c.day })), deviation_reason: change.deviation_reason ?? null, created_by: adminId }, today);
}

/**
 * Overseer `set_plan`: applies DIRECTLY, no in-app approval — only for the
 * admin's OWN plan and only after the admin said yes in chat
 * (`confirmed_in_chat: true`, with the summary that was shown). HARD rules
 * still apply. Recorded as an applied 'overseer' proposal (undo works).
 */
export async function applyOverseerChange(
  userId: string,
  change: OverseerChange,
  opts: { confirmed_in_chat: boolean; summary: string; target_user_id?: string; today?: string },
): Promise<{ proposal: ServedProposal; days: ServedDay[] }> {
  if (opts?.confirmed_in_chat !== true) throw new RunPlanError("confirmation_required", 400);
  if (!opts.summary || typeof opts.summary !== "string" || !opts.summary.trim()) throw new RunPlanError("summary_required", 400);
  if (opts.target_user_id && opts.target_user_id !== userId) throw new RunPlanError("own_plan_only", 403);
  if (!(await isAdmin(userId))) throw new RunPlanError("admin_required", 403);
  const today = opts.today ?? new Date().toISOString().slice(0, 10);
  const st = await loadState(userId, today);
  const p = await createProposalInState(st, { source: "overseer", kind: "adjust", title: change.title ?? "Overseer change", reason: change.reason ?? opts.summary, changes: change.changes.map((c) => ({ local_date: c.local_date, spec: c.day })), deviation_reason: change.deviation_reason ?? null, created_by: userId });
  const out = await inTransaction(async (client) => {
    const row = await lockPlanAndProposal(client, userId, p!.id);
    const r = await applyChecked(client, row, today, "now");
    if (r.ok) await history(client, row.plan_id, userId, "overseer_set_plan", "overseer", row.id, opts.summary.slice(0, 500), row.changes.map((c) => c.local_date), { confirmed_in_chat: true, summary: opts.summary });
    return r;
  });
  if (!out.ok) throw out.error;
  return proposalResponse(userId, p!.id, today);
}

/** For the admin connector / Coach tab: plan detail of any user. */
export async function getPlanDetailForAdmin(userId: string, today = new Date().toISOString().slice(0, 10)) {
  const plan = await activePlan(userId);
  const { profile } = await getProfile(userId);
  if (!plan) return { plan: null, days: [], proposals: [], fitness_profile: profile, checkins: [], grades: [], history: [] };
  const st = await loadState(userId, today, { plan, back: 42 });
  const [days, proposals, checkins, hist] = await Promise.all([
    serveDays(st, addDays(today, -42), addDays(today, DAYS_AHEAD)),
    listProposalRows(plan.plan_id, null, 200),
    listCheckins(userId, addDays(today, -42), today),
    db.query(`SELECT id::text AS id, at, event, source, proposal_id, summary, dates, detail FROM run_plan_history WHERE plan_id = $1 ORDER BY at DESC LIMIT 200`, [plan.plan_id]),
  ]);
  return { plan: servePlan(st, today), days, proposals: proposals.map((p) => serveProposal(p, nextRunDate(st))), fitness_profile: profile, checkins, grades: [...st.grades.values()], history: hist };
}

// ─── Notifications (spec §6) ──────────────────────────────────────────────

export interface NotifyCandidate {
  proposal_id: string;
  user_id: string;
  first_date: string;
  title: string;
  reason: string;
  changes: StoredChange[];
  offset_minutes: number;
  typical_hour: number | null;
  plan_id: string;
}
/** Pending, un-notified proposals of active plans, with the user's offset and typical run hour. */
export async function notificationCandidates(): Promise<NotifyCandidate[]> {
  return db.query<NotifyCandidate>(
    `SELECT p.id AS proposal_id, p.user_id, p.first_date::text AS first_date, p.title, p.reason, p.changes, p.plan_id,
            ${userOffsetMinutesSql("p.user_id")} AS offset_minutes,
            COALESCE((fp.profile->>'typical_run_hour')::int, (
              SELECT percentile_disc(0.5) WITHIN GROUP (ORDER BY EXTRACT(HOUR FROM ((w.device_end_date AT TIME ZONE 'UTC') - w.total_duration * INTERVAL '1 second' + w.timezone_offset * INTERVAL '1 minute'))::int)
                FROM (SELECT * FROM workouts w0 WHERE w0.user_id = p.user_id AND w0.workout_type = 'running' AND ${countedWorkoutSql("w0")} ORDER BY w0.device_end_date DESC LIMIT 30) w
            )) AS typical_hour
       FROM run_plan_proposals p
       JOIN run_plans rp ON rp.plan_id = p.plan_id AND rp.status = 'active'
       LEFT JOIN run_fitness_profiles fp ON fp.user_id = p.user_id
      WHERE p.status = 'pending' AND p.notified_at IS NULL AND p.first_date >= CURRENT_DATE - 1
      LIMIT 2000`,
  );
}

/** Next planned, not-yet-done run on or after `today` for a plan (for "affects the next run"). */
export async function nextRunFor(userId: string, today: string): Promise<{ date: string; day: Day } | null> {
  const plan = await activePlan(userId);
  if (!plan) return null;
  const st = await loadState(userId, today, { plan, back: 1 });
  const d = nextRunDate(st);
  return d ? { date: d, day: st.days.get(d)! } : null;
}

export async function claimProposalNotification(id: string): Promise<boolean> {
  const r = await db.query(`UPDATE run_plan_proposals SET notified_at = now() WHERE id = $1 AND notified_at IS NULL AND status = 'pending' RETURNING 1`, [id]);
  return r.length > 0;
}
