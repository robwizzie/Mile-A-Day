/**
 * Run Plans rules engine — PURE. No DB, no clock, no Express.
 *
 * Every number in a plan comes from here: paces, volumes, the week layout,
 * checkpoints, the derived day status, performance adaptation, missed-day
 * moves, and the action set every coach (Flamey, Claude, the user) is limited
 * to, with its caps. The service (`runPlanService.ts`) feeds it rows and
 * persists what it returns; `scripts/run-plans-check.mjs` calls it directly.
 *
 * Dates are the client's LOCAL dates as 'YYYY-MM-DD' strings. Weeks run
 * Monday–Sunday. Distances are miles, paces seconds per mile.
 */

// ─── Dates ────────────────────────────────────────────────────────────────

const DAY_MS = 86_400_000;
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

export function isIsoDate(s: unknown): s is string {
  if (typeof s !== "string" || !ISO_DATE.test(s)) return false;
  const d = new Date(`${s}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
}

function toMs(s: string): number {
  return Date.parse(`${s}T00:00:00Z`);
}

export function addDays(s: string, n: number): string {
  return new Date(toMs(s) + n * DAY_MS).toISOString().slice(0, 10);
}

/** b − a in days. */
export function dayDiff(a: string, b: string): number {
  return Math.round((toMs(b) - toMs(a)) / DAY_MS);
}

/** 0 = Monday … 6 = Sunday. */
export function weekdayIndex(s: string): number {
  return (new Date(toMs(s)).getUTCDay() + 6) % 7;
}

/** The Monday of `s`'s week. */
export function weekStart(s: string): string {
  return addDays(s, -weekdayIndex(s));
}

const WEEKDAY_NAMES = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
export function weekdayName(s: string): string {
  return WEEKDAY_NAMES[weekdayIndex(s)];
}

// ─── Constants ────────────────────────────────────────────────────────────

export const GOAL_TYPES = [
  "faster_mile",
  "5k",
  "10k",
  "half",
  "marathon",
  "first_5k",
  "more_miles",
] as const;
export type GoalType = (typeof GOAL_TYPES)[number];

export interface Goal {
  type: GoalType;
  /** Finish time goal for the race distance (seconds). */
  target_seconds?: number | null;
  /** `more_miles` only: the weekly mileage to build to. */
  distance_mi?: number | null;
}

export const GOAL_DISTANCE_MI: Record<GoalType, number | null> = {
  faster_mile: 1,
  "5k": 3.10686,
  "10k": 6.21371,
  half: 13.1094,
  marathon: 26.2188,
  first_5k: 3.10686,
  more_miles: null,
};

const GOAL_NAME: Record<GoalType, string> = {
  faster_mile: "mile",
  "5k": "5K",
  "10k": "10K",
  half: "half marathon",
  marathon: "marathon",
  first_5k: "5K",
  more_miles: "weekly miles",
};

export const DAY_KINDS = [
  "streak",
  "easy",
  "intervals",
  "tempo",
  "long",
  "race_test",
] as const;
export type DayKind = (typeof DAY_KINDS)[number];
export const HARD_KINDS: ReadonlySet<string> = new Set([
  "intervals",
  "tempo",
  "long",
  "race_test",
]);
export const isHard = (kind: string) => HARD_KINDS.has(kind);

export type Effort = 1 | 2 | 3 | 4;
export const EFFORT: Record<
  Effort,
  {
    label: string;
    hardDays: number;
    growth: number;
    /** × tempo/interval paces: >1 gentler, <1 sharper. */
    hardPaceFactor: number;
    /** × 5K pace for easy runs. */
    easyFactor: number;
    strides: boolean;
    /** × the goal's peak weekly volume. */
    peakFactor: number;
  }
> = {
  1: { label: "Easy does it", hardDays: 1, growth: 0.05, hardPaceFactor: 1.02, easyFactor: 1.3, strides: false, peakFactor: 0.8 },
  2: { label: "Steady", hardDays: 2, growth: 0.07, hardPaceFactor: 1.01, easyFactor: 1.27, strides: false, peakFactor: 0.9 },
  3: { label: "Push", hardDays: 3, growth: 0.08, hardPaceFactor: 1.0, easyFactor: 1.24, strides: false, peakFactor: 1.0 },
  4: { label: "All in", hardDays: 3, growth: 0.1, hardPaceFactor: 0.99, easyFactor: 1.21, strides: true, peakFactor: 1.1 },
};

export const MIN_WEEKLY_MI = 7;
export const MIN_DAY_MI = 1;
export const RECOVERY_WEEK_FACTOR = 0.8;
/** Week total after a swap/move/set may exceed the planned total by this. */
export const WEEK_TOTAL_SLACK_MI = 0.5;
export const HARDER_MAX_REPS = 2;
export const HARDER_MAX_PCT = 0.2;
/** Done thresholds (fraction of planned). Streak days match DAILY_GOAL_TOLERANCE. */
export const DONE_FRACTION = 0.9;
export const STREAK_DONE_FRACTION = 0.95;
/** A split / run slower than this (s/mi) is walking. */
export const WALK_PACE_S = 900;
/** A session with at least this much of its distance walked is walk-heavy. */
export const WALK_HEAVY_FRACTION = 0.3;
export const HARD_DAYS_WARNING_AT = 5;
export const HARD_DAYS_WARNING =
  "5 or more hard days a week is a lot. Most runners improve faster with easy days between hard ones.";
const RIEGEL = 1.06;
const FIVE_K = 3.10686;
const DEFAULT_5K_S = 1980; // 33:00 when we know nothing

export const round2 = (n: number) => Math.round(n * 100) / 100;
const round05 = (n: number) => Math.round(n * 2) / 2;
const floor1 = (n: number) => Math.floor(n * 10 + 1e-9) / 10;

export function riegel(t1: number, d1: number, d2: number): number {
  return t1 * Math.pow(d2 / d1, RIEGEL);
}

export function hardDaysFor(effort: Effort, override: number | null | undefined): number {
  return override ?? EFFORT[effort].hardDays;
}

export function hardDaysWarning(hardDays: number): string | null {
  return hardDays >= HARD_DAYS_WARNING_AT ? HARD_DAYS_WARNING : null;
}

export function formatDuration(seconds: number): string {
  const t = Math.round(seconds);
  const h = Math.floor(t / 3600);
  const m = Math.floor((t % 3600) / 60);
  const s = t % 60;
  const ss = s < 10 ? `0${s}` : `${s}`;
  if (h > 0) return `${h}:${m < 10 ? `0${m}` : m}:${ss}`;
  return `${m}:${ss}`;
}

const fmtMi = (n: number) => `${round2(n)}`.replace(/\.0+$/, "");

// ─── Fitness / baseline ──────────────────────────────────────────────────

export interface RunSample {
  workout_id: string;
  local_date: string;
  workout_type: string;
  distance_mi: number;
  duration_s: number;
  /** Believable moving time (displayMovingSecondsSql), else null. */
  moving_s: number | null;
  is_indoor: boolean | null;
  splits: { n: number; distance_mi: number | null; duration_s: number; pace_s: number | null }[];
}

/** Seconds per mile using believable moving time, else elapsed. */
export function runPace(r: Pick<RunSample, "distance_mi" | "duration_s" | "moving_s">): number | null {
  if (!(r.distance_mi > 0)) return null;
  const t = r.moving_s ?? r.duration_s;
  return t > 0 ? t / r.distance_mi : null;
}

/** Fraction of a workout's distance covered at walking pace. */
export function walkFraction(r: RunSample): number {
  if (r.workout_type === "walking") return 1;
  const withDist = r.splits.filter((s) => (s.distance_mi ?? 0) > 0 && (s.pace_s ?? 0) > 0);
  const total = withDist.reduce((a, s) => a + (s.distance_mi ?? 0), 0);
  if (total > 0) {
    const walked = withDist
      .filter((s) => (s.pace_s ?? 0) > WALK_PACE_S)
      .reduce((a, s) => a + (s.distance_mi ?? 0), 0);
    return round2(walked / total);
  }
  const p = runPace(r);
  return p != null && p > WALK_PACE_S ? 1 : 0;
}

export interface Fitness {
  as_of: string;
  run_count_90d: number;
  best_mile_s: number | null;
  best_mile_90d_s: number | null;
  /** Best ~5K effort (3.0–3.5 mi runs, Riegel-normalized to 5K), last 90 days. */
  best_5k_s: number | null;
  /** Fastest mile split ever: when, and whether that run was indoors. */
  best_mile_date: string | null;
  best_mile_indoor: boolean | null;
  /** Running miles per week, mean of the last 4 weeks (= weekly_miles_4w). */
  weekly_miles: number;
  weekly_miles_4w: number;
  /** The last 4 weeks' running miles, oldest first. */
  weekly_miles_by_week: number[];
  longest_run_8w_mi: number;
  /** = longest_run_8w_mi (the name the app reads). */
  longest_run_mi: number;
  easy_pace_s: number | null;
  walk_fraction_8w: number;
  walk_heavy: boolean;
  /** The 5K time paces are built from, and where it came from. */
  current_5k_s: number;
  current_source: "5k" | "mile" | "easy_pace" | "default";
  predicted: { mile_s: number; "5k_s": number; "10k_s": number; half_s: number; marathon_s: number };
}

export interface FitnessInputs {
  as_of: string;
  best_mile_s: number | null;
  best_mile_date?: string | null;
  best_mile_indoor?: boolean | null;
  best_mile_90d_s: number | null;
  best_5k_s: number | null;
  run_count_90d: number;
  weekly_miles: number[];
  /** Running workouts of the last 8 weeks (with splits). */
  recent_runs: RunSample[];
}

/** The fitness snapshot from raw aggregates (pure). */
export function computeFitness(i: FitnessInputs): Fitness {
  const runs = i.recent_runs.filter((r) => r.distance_mi > 0);
  const longest = runs.reduce((m, r) => Math.max(m, r.distance_mi), 0);
  const paces = runs
    .map((r) => runPace(r))
    .filter((p): p is number => p != null && p >= 241 && p <= 2400)
    .sort((a, b) => a - b);
  const easy = paces.length ? paces[Math.floor(paces.length / 2)] : null;
  const dist = runs.reduce((a, r) => a + r.distance_mi, 0);
  const walked = runs.reduce((a, r) => a + walkFraction(r) * r.distance_mi, 0);
  const wf = dist > 0 ? round2(walked / dist) : 0;

  let current: number;
  let source: Fitness["current_source"];
  if (i.best_5k_s) {
    current = i.best_5k_s;
    source = "5k";
  } else if (i.best_mile_90d_s) {
    current = riegel(i.best_mile_90d_s, 1, FIVE_K);
    source = "mile";
  } else if (easy) {
    current = (easy / 1.25) * FIVE_K;
    source = "easy_pace";
  } else {
    current = DEFAULT_5K_S;
    source = "default";
  }
  current = Math.round(current);
  const weekly = i.weekly_miles.map(round2);
  const weeklyMean = round2(weekly.reduce((a, b) => a + b, 0) / Math.max(1, weekly.length));
  return {
    as_of: i.as_of,
    run_count_90d: i.run_count_90d,
    best_mile_s: i.best_mile_s != null ? Math.round(i.best_mile_s) : null,
    best_mile_date: i.best_mile_date ?? null,
    best_mile_indoor: i.best_mile_s != null ? (i.best_mile_indoor ?? null) : null,
    best_mile_90d_s: i.best_mile_90d_s != null ? Math.round(i.best_mile_90d_s) : null,
    best_5k_s: i.best_5k_s != null ? Math.round(i.best_5k_s) : null,
    weekly_miles: weeklyMean,
    weekly_miles_4w: weeklyMean,
    weekly_miles_by_week: weekly,
    longest_run_8w_mi: round2(longest),
    longest_run_mi: round2(longest),
    easy_pace_s: easy != null ? Math.round(easy) : null,
    walk_fraction_8w: wf,
    walk_heavy: wf >= WALK_HEAVY_FRACTION,
    current_5k_s: current,
    current_source: source,
    predicted: {
      mile_s: Math.round(riegel(current, FIVE_K, 1)),
      "5k_s": current,
      "10k_s": Math.round(riegel(current, FIVE_K, 6.21371)),
      half_s: Math.round(riegel(current, FIVE_K, 13.1094)),
      marathon_s: Math.round(riegel(current, FIVE_K, 26.2188)),
    },
  };
}

/** Current best time for a goal distance: real efforts first, else Riegel. */
export function currentTimeFor(type: GoalType, f: Fitness): number | null {
  const d = GOAL_DISTANCE_MI[type];
  if (d == null) return null;
  if (type === "faster_mile" && f.best_mile_90d_s) return f.best_mile_90d_s;
  if ((type === "5k" || type === "first_5k") && f.best_5k_s) return f.best_5k_s;
  return Math.round(riegel(f.current_5k_s, FIVE_K, d));
}

/** Longest single run the plan may schedule: max(L × 1.25, L + 1). */
export function longRunCap(f: Pick<Fitness, "longest_run_8w_mi">): number {
  const l = Math.max(MIN_DAY_MI, f.longest_run_8w_mi || 0);
  return floor1(Math.max(l * 1.25, l + 1));
}

// ─── Paces ────────────────────────────────────────────────────────────────

export interface Paces {
  easy_s: number;
  long_s: number;
  tempo_s: number;
  interval_s: number;
  mile_s: number;
  /** The 5K time these paces were built from. */
  basis_5k_s: number;
}

export function pacesFor(t5: number, effort: Effort): Paces {
  const p5 = t5 / FIVE_K;
  const e = EFFORT[effort];
  const easy = p5 * e.easyFactor;
  return {
    easy_s: Math.round(easy),
    long_s: Math.round(easy * 1.03),
    tempo_s: Math.round(p5 * 1.07 * e.hardPaceFactor),
    interval_s: Math.round(p5 * 0.97 * e.hardPaceFactor),
    mile_s: Math.round(riegel(t5, FIVE_K, 1)),
    basis_5k_s: Math.round(t5),
  };
}

/** Weekly fitness progression the plan trains toward (fraction of 5K time). */
const weeklyGain = (effort: Effort) => 0.002 + 0.001 * effort;

// ─── Checkpoints ──────────────────────────────────────────────────────────

export interface Checkpoint {
  goal_type: GoalType;
  kind: "time" | "distance" | "weekly_miles";
  label: string;
  target_seconds: number | null;
  distance_mi: number | null;
  weekly_mi: number | null;
  /** Estimated date (finish_by spreads them up to the finish line). */
  eta: string | null;
  /** = eta (the name the app reads). */
  by_date: string | null;
  reached: boolean;
  is_goal: boolean;
}

/** Round a race time to a friendly grid, never up past `below`. */
function niceTime(t: number, below: number): number {
  const grid = t >= 1200 ? 60 : t >= 600 ? 30 : 5;
  let r = Math.round(t / grid) * grid;
  while (r >= below) r -= grid;
  return r;
}

const CHECKPOINT_STEP = 0.92;
const KEEP_IMPROVING_STEP = 0.97;

export interface CheckpointInput {
  goals: Goal[];
  effort: Effort;
  start_date: string;
  finish_by: string | null;
  /** Fitness NOW (checkpoints re-derive on read so "reached" moves). */
  fitness: Fitness;
  baseline: Fitness;
}

export function computeCheckpoints(i: CheckpointInput): Checkpoint[] {
  const out: Omit<Checkpoint, "by_date">[] = [];
  const rate = 0.004 + 0.001 * i.effort;
  for (const g of i.goals) {
    const d = GOAL_DISTANCE_MI[g.type];
    if (g.type === "first_5k") {
      const l = i.fitness.longest_run_8w_mi;
      const base = i.baseline.longest_run_8w_mi;
      for (const m of [1, 2, FIVE_K]) {
        if (m <= base && m < FIVE_K) continue;
        const weeks = Math.max(0, (m - Math.max(l, 0)) / 0.5);
        out.push({
          goal_type: g.type,
          kind: "distance",
          label: m === FIVE_K ? "Run a full 5K" : `Run ${fmtMi(m)} mi`,
          target_seconds: null,
          distance_mi: round2(m),
          weekly_mi: null,
          eta: etaFor(i, weeks, m === FIVE_K),
          reached: l >= m * 0.98,
          is_goal: m === FIVE_K,
        });
      }
      continue;
    }
    if (g.type === "more_miles") {
      const now = i.fitness.weekly_miles_4w;
      const from = Math.max(MIN_WEEKLY_MI, i.baseline.weekly_miles_4w);
      const target = g.distance_mi ?? Math.round(from * 1.5);
      const steps: number[] = [];
      for (let v = from * 1.25; v < target * 0.95; v *= 1.25) steps.push(Math.round(v));
      steps.push(Math.round(target));
      const growth = EFFORT[i.effort].growth;
      for (const s of steps) {
        const weeks = s > now && now > 0 ? Math.log(s / Math.max(now, MIN_WEEKLY_MI)) / Math.log(1 + growth) * 1.33 : 0;
        out.push({
          goal_type: g.type,
          kind: "weekly_miles",
          label: `${s} mi a week`,
          target_seconds: null,
          distance_mi: null,
          weekly_mi: s,
          eta: etaFor(i, Math.max(0, weeks), s === Math.round(target)),
          reached: now >= s,
          is_goal: s === Math.round(target),
        });
      }
      continue;
    }
    if (d == null) continue;
    const now = currentTimeFor(g.type, i.fitness)!;
    const startT = currentTimeFor(g.type, i.baseline)!;
    const target = g.target_seconds ?? null;
    const label = (t: number) => `Sub-${formatDuration(t)} ${GOAL_NAME[g.type]}`;
    const totalLn = target ? Math.log(startT / target) : 0;
    const cpEta = (t: number, isGoal: boolean) => {
      const ln = Math.log(Math.max(now, 1) / t);
      if (i.finish_by && target && totalLn > 0 && t >= target) {
        const frac = Math.min(1, Math.max(0, Math.log(startT / t) / totalLn));
        return addDays(i.start_date, Math.round(frac * dayDiff(i.start_date, i.finish_by)));
      }
      return etaFor(i, Math.max(0, ln / rate), isGoal);
    };
    if (target && now > target) {
      // Stepped checkpoints toward a far goal: ≤ 8% faster each.
      let prev = startT;
      const times: number[] = [];
      for (let k = 0; k < 20; k++) {
        const next = prev * CHECKPOINT_STEP;
        if (next <= target * 1.04) break;
        const t = niceTime(next, prev);
        if (t <= target) break;
        times.push(t);
        prev = t;
      }
      for (const t of times) {
        out.push({ goal_type: g.type, kind: "time", label: label(t), target_seconds: t, distance_mi: round2(d), weekly_mi: null, eta: cpEta(t, false), reached: now <= t, is_goal: false });
      }
      out.push({ goal_type: g.type, kind: "time", label: label(target), target_seconds: target, distance_mi: round2(d), weekly_mi: null, eta: cpEta(target, true), reached: false, is_goal: true });
      continue;
    }
    // No target, or already there: keep improving from where they are now.
    if (target) {
      out.push({ goal_type: g.type, kind: "time", label: label(target), target_seconds: target, distance_mi: round2(d), weekly_mi: null, eta: null, reached: true, is_goal: true });
    }
    let prev = now;
    for (let k = 0; k < 3; k++) {
      const t = niceTime(prev * KEEP_IMPROVING_STEP, prev);
      out.push({ goal_type: g.type, kind: "time", label: label(t), target_seconds: t, distance_mi: round2(d), weekly_mi: null, eta: etaFor(i, Math.log(now / t) / rate, false), reached: false, is_goal: false });
      prev = t;
    }
  }
  return out.map((c) => ({ ...c, by_date: c.eta }));
}

function etaFor(i: CheckpointInput, weeks: number, isGoal: boolean): string | null {
  if (isGoal && i.finish_by) return i.finish_by;
  if (!Number.isFinite(weeks)) return null;
  const eta = addDays(i.fitness.as_of, Math.ceil(weeks * 7));
  return i.finish_by && eta > i.finish_by ? i.finish_by : eta;
}

/**
 * The fastest 5K-equivalent training may aim at right now: the least
 * ambitious NEXT unreached time checkpoint (never train past it).
 */
export function trainingFloor5k(cps: Checkpoint[], fallback: number): number {
  const next = new Map<GoalType, number>();
  for (const c of cps) {
    if (c.kind !== "time" || c.reached || c.target_seconds == null || c.distance_mi == null) continue;
    if (next.has(c.goal_type)) continue;
    next.set(c.goal_type, riegel(c.target_seconds, c.distance_mi, FIVE_K));
  }
  if (!next.size) return fallback;
  return Math.max(...next.values());
}

// ─── Segments / days ─────────────────────────────────────────────────────

export interface Segment {
  kind: "warmup" | "work" | "recover" | "cooldown" | "steady";
  distance_mi?: number;
  duration_s?: number;
  target_pace_s?: number | null;
  rep?: number;
  reps?: number;
}

/** A day as the engine thinks about it (what proposals diff). */
export interface DaySummary {
  kind: DayKind;
  title: string;
  distance_mi: number;
  segments: Segment[];
  target_pace_s: number | null;
  note: string | null;
}

export function segmentsDistance(segs: Segment[]): number {
  return round2(segs.reduce((a, s) => a + (s.distance_mi ?? 0), 0));
}

/** The pace a day is "about": the work pace, else the steady pace. */
export function targetPaceOf(segs: Segment[]): number | null {
  const work = segs.find((s) => s.kind === "work" && s.distance_mi && s.target_pace_s);
  if (work) return work.target_pace_s ?? null;
  const steady = segs.find((s) => s.kind === "steady" && s.target_pace_s);
  return steady?.target_pace_s ?? null;
}

/** Distance-weighted target pace over every paced segment (for adaptation). */
export function expectedAvgPace(segs: Segment[]): number | null {
  let d = 0;
  let t = 0;
  for (const s of segs) {
    if (!s.distance_mi || !s.target_pace_s) continue;
    d += s.distance_mi;
    t += s.distance_mi * s.target_pace_s;
  }
  return d > 0 ? t / d : null;
}

const REP_LABEL: Record<string, string> = { "0.25": "400m", "0.5": "800m", "0.75": "1200m", "1": "1 mi" };

export function titleFor(kind: DayKind, segs: Segment[], runDailyMile: boolean, raceLabel?: string): string {
  const dist = segmentsDistance(segs);
  switch (kind) {
    case "streak":
      return runDailyMile ? "Run your daily mile" : "Daily mile";
    case "easy":
      return `Easy ${fmtMi(dist)} mi${segs.some((s) => s.kind === "work") ? " + strides" : ""}`;
    case "long":
      return `Long run ${fmtMi(dist)} mi`;
    case "tempo": {
      const w = segs.find((s) => s.kind === "work");
      return `Tempo ${fmtMi(w?.distance_mi ?? dist)} mi`;
    }
    case "intervals": {
      const w = segs.find((s) => s.kind === "work");
      const rep = w?.distance_mi ?? 0;
      return `Intervals ${w?.reps ?? 0} × ${REP_LABEL[String(rep)] ?? `${fmtMi(rep)} mi`}`;
    }
    case "race_test":
      return `Race test${raceLabel ? `: ${raceLabel}` : ""}`;
  }
}

function summary(kind: DayKind, segs: Segment[], runDailyMile: boolean, note: string | null, raceLabel?: string): DaySummary {
  return {
    kind,
    title: titleFor(kind, segs, runDailyMile, raceLabel),
    distance_mi: Math.max(MIN_DAY_MI, segmentsDistance(segs)),
    segments: segs,
    target_pace_s: targetPaceOf(segs),
    note,
  };
}

export function streakDay(p: Paces, runDailyMile: boolean, note: string | null = null): DaySummary {
  return summary("streak", [{ kind: "steady", distance_mi: 1, target_pace_s: runDailyMile ? p.easy_s : null }], runDailyMile, note);
}

export function easyDay(dist: number, p: Paces, strides: boolean, note: string | null = null): DaySummary {
  const d = Math.max(MIN_DAY_MI, round2(dist));
  const segs: Segment[] = [{ kind: "steady", distance_mi: d, target_pace_s: p.easy_s }];
  if (strides) {
    for (let r = 1; r <= 4; r++) {
      segs.push({ kind: "work", duration_s: 20, target_pace_s: p.mile_s, rep: r, reps: 4 });
      if (r < 4) segs.push({ kind: "recover", duration_s: 60, target_pace_s: null, rep: r, reps: 4 });
    }
  }
  return summary("easy", segs, true, note);
}

export function longDay(dist: number, p: Paces, note: string | null = null): DaySummary {
  return summary("long", [{ kind: "steady", distance_mi: round2(Math.max(MIN_DAY_MI, dist)), target_pace_s: p.long_s }], true, note);
}

export function intervalsDay(o: { reps: number; rep_mi: number; recover_mi: number; wu: number; cd: number; pace: number; easy: number }, note: string | null = null): DaySummary {
  const segs: Segment[] = [];
  if (o.wu > 0) segs.push({ kind: "warmup", distance_mi: o.wu, target_pace_s: o.easy });
  for (let r = 1; r <= o.reps; r++) {
    segs.push({ kind: "work", distance_mi: o.rep_mi, target_pace_s: o.pace, rep: r, reps: o.reps });
    if (r < o.reps) segs.push({ kind: "recover", distance_mi: o.recover_mi, target_pace_s: null, rep: r, reps: o.reps });
  }
  if (o.cd > 0) segs.push({ kind: "cooldown", distance_mi: o.cd, target_pace_s: o.easy });
  return summary("intervals", segs, true, note);
}

export function tempoDay(o: { work_mi: number; wu: number; cd: number; pace: number; easy: number }, note: string | null = null): DaySummary {
  const segs: Segment[] = [];
  if (o.wu > 0) segs.push({ kind: "warmup", distance_mi: o.wu, target_pace_s: o.easy });
  segs.push({ kind: "work", distance_mi: round2(o.work_mi), target_pace_s: o.pace });
  if (o.cd > 0) segs.push({ kind: "cooldown", distance_mi: o.cd, target_pace_s: o.easy });
  return summary("tempo", segs, true, note);
}

export function raceTestDay(o: { dist: number; pace: number; easy: number; label: string }, note: string | null = null): DaySummary {
  const segs: Segment[] = [
    { kind: "warmup", distance_mi: 0.5, target_pace_s: o.easy },
    { kind: "work", distance_mi: round2(o.dist), target_pace_s: o.pace },
    { kind: "cooldown", distance_mi: 0.5, target_pace_s: o.easy },
  ];
  return summary("race_test", segs, true, note, o.label);
}

// ─── Plan settings + week generation ─────────────────────────────────────

export interface PlanSettings {
  goals: Goal[];
  effort: Effort;
  hard_days: number | null;
  run_daily_mile: boolean;
  finish_by: string | null;
  start_date: string;
  baseline: Fitness;
}

const PEAK_MI: Record<GoalType, number> = {
  faster_mile: 15,
  first_5k: 12,
  "5k": 20,
  "10k": 25,
  half: 32,
  marathon: 40,
  more_miles: 0,
};

export function baseWeeklyMi(baseline: Fitness): number {
  return Math.max(MIN_WEEKLY_MI, baseline.weekly_miles_4w || 0);
}

export function peakWeeklyMi(s: PlanSettings): number {
  const base = baseWeeklyMi(s.baseline);
  const f = EFFORT[s.effort].peakFactor;
  let peak = 0;
  for (const g of s.goals) {
    if (g.type === "more_miles") peak = Math.max(peak, g.distance_mi ?? base * 1.5);
    else peak = Math.max(peak, PEAK_MI[g.type] * f);
  }
  return Math.max(base, peak);
}

/** Every 4th week (week index 3, 7, 11 …) is a recovery week. */
export const isRecoveryWeek = (w: number) => w >= 0 && (w + 1) % 4 === 0;

/** Planned weekly miles for week index `w` (0 = the start week). */
export function weekVolume(s: PlanSettings, w: number): number {
  const base = baseWeeklyMi(s.baseline);
  const peak = peakWeeklyMi(s);
  const g = EFFORT[s.effort].growth;
  const vol = (k: number) => Math.min(peak, base * Math.pow(1 + g, k));
  const growthWeeks = (n: number) => n - Math.floor((n + 1) / 4); // non-recovery weeks before n
  if (isRecoveryWeek(w)) return round2(Math.max(MIN_WEEKLY_MI, vol(growthWeeks(w - 1)) * RECOVERY_WEEK_FACTOR));
  return round2(Math.max(MIN_WEEKLY_MI, vol(growthWeeks(w))));
}

/** Which weekdays (0 = Mon) are hard, and as what. */
export function hardLayout(goals: Goal[], hardDays: number): Map<number, DayKind> {
  const focus = goals[0]?.type ?? "5k";
  let kinds: DayKind[];
  if (hardDays <= 1) {
    kinds = focus === "faster_mile" || focus === "5k" ? ["intervals"] : ["long"];
  } else if (hardDays === 2) {
    kinds = focus === "faster_mile" ? ["intervals", "tempo"] : focus === "half" || focus === "marathon" ? ["tempo", "long"] : ["intervals", "long"];
  } else {
    kinds = ["intervals", "tempo", "long"];
    const extra: DayKind[] = ["tempo", "intervals", "tempo", "intervals"];
    for (let i = 3; i < hardDays; i++) kinds.push(extra[i - 3]);
  }
  const hasLong = kinds.includes("long");
  const slots: Record<number, number[]> = {
    1: hasLong ? [6] : [2],
    2: hasLong ? [2, 6] : [1, 4],
    3: [1, 3, 6],
    4: [1, 3, 5, 6],
    5: [1, 2, 3, 5, 6],
    6: [0, 1, 2, 3, 5, 6],
    7: [0, 1, 2, 3, 4, 5, 6],
  };
  const pick = slots[Math.min(7, Math.max(1, hardDays))];
  const out = new Map<number, DayKind>();
  const rest = kinds.filter((k) => k !== "long");
  if (hasLong) out.set(6, "long");
  for (const slot of pick) {
    if (out.has(slot)) continue;
    const k = rest.shift();
    if (k) out.set(slot, k);
  }
  return out;
}

function repConfig(focus: GoalType, effort: Effort): { rep: number; base: number; max: number } {
  switch (focus) {
    case "faster_mile":
      return { rep: 0.25, base: 4 + effort, max: 12 };
    case "half":
    case "marathon":
    case "more_miles":
      return { rep: 1, base: 2 + Math.floor(effort / 2), max: 6 };
    default:
      return { rep: 0.5, base: 2 + effort, max: 8 };
  }
}

const TEMPO_MAX: Record<GoalType, number> = { faster_mile: 2, first_5k: 2, "5k": 3, "10k": 4, half: 6, marathon: 8, more_miles: 4 };

export interface WeekContext {
  settings: PlanSettings;
  /** Fitness now: long-run cap and the current 5K. */
  fitness: Fitness;
  checkpoints: Checkpoint[];
}

/** Week index of `date` relative to the plan's start week. */
export function weekIndex(startDate: string, date: string): number {
  return Math.floor(dayDiff(weekStart(startDate), weekStart(date)) / 7);
}

/** The training 5K for week w: progresses from baseline, never past the next checkpoint. */
export function training5k(ctx: WeekContext, w: number): number {
  const s = ctx.settings;
  const progressed = s.baseline.current_5k_s * (1 - weeklyGain(s.effort) * Math.max(0, w));
  const t = Math.min(progressed, ctx.fitness.current_5k_s);
  const floor = trainingFloor5k(ctx.checkpoints, s.baseline.current_5k_s * 0.9);
  return Math.round(Math.max(floor, t));
}

export function pacesForWeek(ctx: WeekContext, w: number): Paces {
  return pacesFor(training5k(ctx, w), ctx.settings.effort);
}

/** The engine's 7 days for the week starting Monday `monday`. */
export function generateWeek(ctx: WeekContext, monday: string): { local_date: string; day: DaySummary }[] {
  const s = ctx.settings;
  const w = Math.max(0, weekIndex(s.start_date, monday));
  const recovery = isRecoveryWeek(w);
  const V = weekVolume(s, w);
  const H = Math.min(7, Math.max(1, hardDaysFor(s.effort, s.hard_days)));
  const layout = hardLayout(s.goals, H);
  const p = pacesForWeek(ctx, w);
  const cap = longRunCap(ctx.fitness);
  const focus = s.goals[0]?.type ?? "5k";
  const growthWeeks = w - Math.floor((w + 1) / 4);
  const wu = V >= 15 ? 1 : 0.5;
  const recoveryNote = recovery ? "Recovery week: a little lighter on purpose." : null;

  // Hard-day sizes.
  const rc = repConfig(focus, s.effort);
  let reps = Math.min(rc.max, rc.base + Math.floor(growthWeeks / 2) - (recovery ? 1 : 0));
  reps = Math.max(2, reps);
  const recoverMi = Math.min(0.25, rc.rep / 2);
  let tempoWork = Math.min(TEMPO_MAX[focus], 1 + 0.25 * growthWeeks) * (recovery ? 0.8 : 1);
  tempoWork = Math.max(0.5, round2(Math.round(tempoWork * 4) / 4));
  let long = Math.min(cap, Math.max(1.5, round05(V * 0.28)));

  const kindsAt = [...layout.entries()];
  const intervalsMi = () => wu * 2 + reps * rc.rep + (reps - 1) * recoverMi;
  const tempoMi = () => wu * 2 + tempoWork;
  const hardSum = () =>
    kindsAt.reduce((a, [, k]) => a + (k === "long" ? long : k === "tempo" ? tempoMi() : intervalsMi()), 0);
  const E = 7 - layout.size;
  // Leave at least a mile for every other day.
  const has = (k: DayKind) => [...layout.values()].includes(k);
  const cuts: (() => boolean)[] = [
    () => has("intervals") && reps > 2 && (reps--, true),
    () => has("long") && long > 1.5 && ((long -= 0.5), true),
    () => has("tempo") && tempoWork > 0.5 && ((tempoWork -= 0.25), true),
  ];
  for (let guard = 0; guard < 60 && hardSum() > V - E * MIN_DAY_MI; guard++) {
    if (!cuts.some((_, j) => cuts[(guard + j) % cuts.length]())) break;
  }
  // No single run past the long-run cap, quality days included.
  while (has("intervals") && reps > 2 && intervalsMi() > cap) reps--;
  while (has("tempo") && tempoWork > 0.5 && tempoMi() > cap) tempoWork -= 0.25;

  const days: DaySummary[] = [];
  for (let i = 0; i < 7; i++) {
    const k = layout.get(i);
    if (k === "long") days[i] = longDay(long, p, recoveryNote);
    else if (k === "tempo") days[i] = tempoDay({ work_mi: tempoWork, wu, cd: wu, pace: p.tempo_s, easy: p.easy_s }, recoveryNote);
    else if (k === "intervals") days[i] = intervalsDay({ reps, rep_mi: rc.rep, recover_mi: recoverMi, wu, cd: wu, pace: p.interval_s, easy: p.easy_s }, recoveryNote);
  }

  // Easy fill.
  const easySlots = [...Array(7).keys()].filter((i) => !layout.has(i));
  let rest = Math.max(easySlots.length * MIN_DAY_MI, V - hardSum());
  const streakSlots = new Set<number>();
  // The day after the long run (Monday) is a streak mile when there's room.
  if (layout.get(6) === "long" && easySlots.includes(0) && easySlots.length >= 3) {
    streakSlots.add(0);
    rest -= MIN_DAY_MI;
  }
  // Every fill day starts at the mile; the rest goes out in half miles,
  // weekend and mid-week days first.
  const fill = easySlots.filter((i) => !streakSlots.has(i));
  const miles = new Map(fill.map((i) => [i, MIN_DAY_MI]));
  const order = [5, 3, 1, 4, 2, 0, 6].filter((i) => miles.has(i));
  let extra = rest - fill.length * MIN_DAY_MI;
  for (let k = 0; extra >= 0.25 && order.length && k < 400; k++) {
    const room = order.filter((i) => miles.get(i)! + 0.5 <= cap);
    if (!room.length) break;
    const i = room[k % room.length];
    miles.set(i, miles.get(i)! + 0.5);
    extra -= 0.5;
  }
  for (const i of easySlots) {
    const m = miles.get(i) ?? MIN_DAY_MI;
    days[i] = m <= MIN_DAY_MI ? streakDay(p, s.run_daily_mile) : easyDay(m, p, EFFORT[s.effort].strides);
  }

  const out = days.map((day, i) => ({ local_date: addDays(monday, i), day }));

  // The finish line: a race test on finish_by (race goals only).
  if (s.finish_by && s.finish_by >= monday && s.finish_by <= addDays(monday, 6)) {
    const race = s.goals.find((g) => GOAL_DISTANCE_MI[g.type] != null);
    if (race) {
      const d = GOAL_DISTANCE_MI[race.type]!;
      const dist = Math.min(d, cap);
      const t = race.target_seconds ?? currentTimeFor(race.type, ctx.fitness) ?? riegel(p.basis_5k_s, FIVE_K, d);
      const idx = weekdayIndex(s.finish_by);
      out[idx].day = raceTestDay(
        { dist, pace: Math.round(t / d), easy: p.easy_s, label: `${GOAL_NAME[race.type]}${dist < d ? ` (${fmtMi(dist)} mi)` : ""}` },
        "Finish line. Go see what the training built.",
      );
      // Race week tapers: no other hard days, the rest at 60%, the days
      // either side of the race just the streak mile.
      for (let j = 0; j < 7; j++) {
        if (j === idx) continue;
        const cur = out[j].day;
        const m = round05(cur.distance_mi * 0.6);
        out[j].day = Math.abs(j - idx) === 1 || m <= MIN_DAY_MI
          ? streakDay(p, s.run_daily_mile)
          : easyDay(m, p, false, "Race week: easing off so you show up fresh.");
      }
    }
  }
  return out;
}

// ─── Status + completion ────────────────────────────────────────────────

export type DayStatus = "done" | "partial" | "missed" | "today" | "planned";

export interface Completed {
  workout_ids: string[];
  distance_mi: number;
  avg_pace_s: number | null;
  walk_fraction: number | null;
}

export function completionOf(runs: RunSample[]): Completed | null {
  if (!runs.length) return null;
  const dist = runs.reduce((a, r) => a + r.distance_mi, 0);
  const time = runs.reduce((a, r) => a + (r.moving_s ?? r.duration_s), 0);
  const walked = runs.reduce((a, r) => a + walkFraction(r) * r.distance_mi, 0);
  return {
    workout_ids: runs.map((r) => r.workout_id),
    distance_mi: round2(dist),
    avg_pace_s: dist > 0 && time > 0 ? Math.round(time / dist) : null,
    walk_fraction: dist > 0 ? round2(walked / dist) : null,
  };
}

export function dayStatus(kind: string, planned: number, date: string, today: string, completed: Completed | null): DayStatus {
  const miles = completed?.distance_mi ?? 0;
  const need = planned * (kind === "streak" ? STREAK_DONE_FRACTION : DONE_FRACTION);
  if (date > today) return "planned";
  if (miles > 0 && miles >= need) return "done";
  if (date === today) return "today";
  return miles > 0 ? "partial" : "missed";
}

// ─── Performance adaptation (deterministic, on read) ─────────────────────

export interface HardSession {
  local_date: string;
  segments: Segment[];
  completed: Completed | null;
  status: DayStatus;
}

export interface Adaptation {
  /** Ease the next hard session: volume × 0.9, paces × 1.02. */
  ease: { after: string; note: string } | null;
  /** Tighten upcoming hard paces by this factor (< 1). */
  tighten: { factor: number; note: string } | null;
}

export const EASE_VOLUME = 0.9;
export const EASE_PACE = 1.02;
export const TIGHTEN_PACE = 0.985;

/** `sessions`: completed (done/partial) hard sessions, any order. */
export function computeAdaptation(sessions: HardSession[]): Adaptation {
  const ran = sessions
    .filter((s) => s.completed && (s.status === "done" || s.status === "partial"))
    .sort((a, b) => (a.local_date < b.local_date ? 1 : -1));
  const ratio = (s: HardSession) => {
    const exp = expectedAvgPace(s.segments);
    const act = s.completed?.avg_pace_s;
    return exp && act ? act / exp : null;
  };
  const last = ran[0];
  if (!last) return { ease: null, tighten: null };
  const r0 = ratio(last);
  const walkHeavy = (last.completed?.walk_fraction ?? 0) >= WALK_HEAVY_FRACTION;
  if ((r0 != null && r0 > 1.05) || walkHeavy) {
    return {
      ease: {
        after: last.local_date,
        note: walkHeavy
          ? `Your last hard session (${weekdayName(last.local_date)}) had a lot of walking, so this one is a little shorter and gentler.`
          : `Your last hard session (${weekdayName(last.local_date)}) ran slower than target, so this one is a little shorter and gentler.`,
      },
      tighten: null,
    };
  }
  const r1 = ran[1] ? ratio(ran[1]) : null;
  if (r0 != null && r1 != null && r0 <= 0.97 && r1 <= 0.97) {
    return { ease: null, tighten: { factor: TIGHTEN_PACE, note: "You've beaten your last two hard sessions' targets, so the paces tighten a touch." } };
  }
  return { ease: null, tighten: null };
}

export function scalePaces(day: DaySummary, f: number): DaySummary {
  const segs = day.segments.map((s) => (s.target_pace_s ? { ...s, target_pace_s: Math.round(s.target_pace_s * f) } : s));
  return { ...day, segments: segs, target_pace_s: targetPaceOf(segs) };
}

// ─── Day transforms (used by actions and adaptation) ─────────────────────

function rebuild(day: DaySummary, segs: Segment[], runDailyMile: boolean): DaySummary {
  const raceLabel = day.kind === "race_test" ? day.title.replace(/^Race test:?\s*/, "") || undefined : undefined;
  return summary(day.kind, segs, runDailyMile, day.note, raceLabel);
}

function intervalParts(day: DaySummary) {
  const work = day.segments.find((s) => s.kind === "work" && s.distance_mi);
  const rec = day.segments.find((s) => s.kind === "recover");
  const wu = day.segments.find((s) => s.kind === "warmup");
  const cd = day.segments.find((s) => s.kind === "cooldown");
  return { work, rec, wu, cd, reps: work?.reps ?? day.segments.filter((s) => s.kind === "work").length };
}

function withReps(day: DaySummary, reps: number, runDailyMile: boolean): DaySummary {
  const { work, rec, wu, cd } = intervalParts(day);
  if (!work) return day;
  const d = intervalsDay({
    reps: Math.max(1, reps),
    rep_mi: work.distance_mi!,
    recover_mi: rec?.distance_mi ?? 0,
    wu: wu?.distance_mi ?? 0,
    cd: cd?.distance_mi ?? 0,
    pace: work.target_pace_s ?? 0,
    easy: wu?.target_pace_s ?? cd?.target_pace_s ?? 0,
  }, day.note);
  return rebuild(day, d.segments, runDailyMile);
}

/** Scale a day's distance by f (intervals: by reps). Never below 1 mi. */
export function scaleDistance(day: DaySummary, f: number, runDailyMile: boolean): DaySummary {
  if (day.kind === "intervals") {
    const { reps } = intervalParts(day);
    return withReps(day, Math.max(2, Math.round(reps * f)), runDailyMile);
  }
  const main = day.segments.filter((s) => (s.kind === "steady" || s.kind === "work") && s.distance_mi);
  const fixed = segmentsDistance(day.segments) - segmentsDistance(main);
  const mainTotal = segmentsDistance(main);
  if (!mainTotal) return day;
  const target = Math.max(MIN_DAY_MI, segmentsDistance(day.segments) * f);
  const g = Math.max(0.05, (target - fixed) / mainTotal);
  const segs = day.segments.map((s) =>
    (s.kind === "steady" || s.kind === "work") && s.distance_mi ? { ...s, distance_mi: round2(Math.max(0.25, s.distance_mi * g)) } : s,
  );
  return rebuild(day, segs, runDailyMile);
}

// ─── Actions ─────────────────────────────────────────────────────────────

export const ACTIONS = [
  "easier",
  "shorter",
  "just_mile",
  "harder",
  "swap_hard_today",
  "rest_tomorrow",
  "move",
  "set_day",
] as const;
export type Action = (typeof ACTIONS)[number];
export const ADJUST_ACTIONS: ReadonlySet<string> = new Set(["easier", "shorter", "just_mile"]);

export interface StoredDay extends DaySummary {
  local_date: string;
  source: "engine" | "flamey" | "claude" | "user";
  original: DaySummary | null;
  moved_from: string | null;
  /** Derived status (affects which days may change). */
  status?: DayStatus;
}

export interface Change {
  local_date: string;
  before: DaySummary;
  after: DaySummary;
}

export interface ActionContext {
  today: string;
  days: StoredDay[];
  hard_days: number;
  run_daily_mile: boolean;
  effort: Effort;
  long_cap: number;
  paces: Paces;
  source: "flamey" | "claude" | "engine" | "user";
}

export class ActionError extends Error {
  constructor(public cap_note: string) {
    super(cap_note);
  }
}

export interface ActionResult {
  changes: Change[];
  cap_note: string | null;
  summary: string;
}

export const toSummary = (d: DaySummary): DaySummary => ({
  kind: d.kind,
  title: d.title,
  distance_mi: round2(d.distance_mi),
  segments: d.segments,
  target_pace_s: d.target_pace_s,
  note: d.note,
});

/** Same plan content (what "before still matches" means for a proposal). */
export function sameDay(a: DaySummary, b: DaySummary): boolean {
  return a.kind === b.kind && round2(a.distance_mi) === round2(b.distance_mi) && JSON.stringify(a.segments) === JSON.stringify(b.segments);
}

/**
 * The week's planned total as it stands BEFORE this change (served plan, not
 * the engine's first draft: a missed-day move or an applied change already
 * reshaped it, and that must not lock every later change out).
 */
function weekPlannedTotal(days: StoredDay[], date: string): number {
  const ws = weekStart(date);
  return round2(days.filter((d) => weekStart(d.local_date) === ws).reduce((a, d) => a + d.distance_mi, 0));
}

function weekTotalAfter(days: StoredDay[], changes: Change[], date: string): number {
  const ws = weekStart(date);
  const after = new Map(changes.map((c) => [c.local_date, c.after]));
  return round2(days.filter((d) => weekStart(d.local_date) === ws).reduce((a, d) => a + (after.get(d.local_date)?.distance_mi ?? d.distance_mi), 0));
}

/** Throws if the changes put two hard days back to back (hard_days ≤ 3). */
function assertSpacing(ctx: ActionContext, changes: Change[]) {
  if (ctx.hard_days > 3) return;
  const after = new Map(changes.map((c) => [c.local_date, c.after]));
  const kindAt = (date: string) => {
    const d = ctx.days.find((x) => x.local_date === date);
    if (!d) return null;
    // A past hard day that never happened doesn't crowd its neighbours.
    if (date < ctx.today && d.status === "missed") return "streak";
    return (after.get(date) ?? d).kind;
  };
  for (const c of changes) {
    if (!isHard(c.after.kind)) continue;
    for (const n of [addDays(c.local_date, -1), addDays(c.local_date, 1)]) {
      const k = kindAt(n);
      if (k && isHard(k)) throw new ActionError("That would put two hard days back to back. Keep an easy day between them.");
    }
  }
}

function dayAt(ctx: ActionContext, date: string): StoredDay {
  const d = ctx.days.find((x) => x.local_date === date);
  if (!d) throw new ActionError("That day isn't in your plan yet.");
  if (date < ctx.today) throw new ActionError("That day is already in the past.");
  return d;
}

/** Today, unless today's run is already done, then tomorrow. */
export function defaultTarget(ctx: ActionContext): string {
  const t = ctx.days.find((d) => d.local_date === ctx.today);
  if (t && t.status === "done") return addDays(ctx.today, 1);
  return ctx.today;
}

function nextHard(ctx: ActionContext, after: string, sameWeek: boolean): StoredDay | undefined {
  return ctx.days
    .filter((d) => d.local_date > after && isHard(d.kind) && d.status !== "done" && (!sameWeek || weekStart(d.local_date) === weekStart(after)))
    .sort((a, b) => (a.local_date < b.local_date ? -1 : 1))[0];
}

function soften(day: DaySummary, runDailyMile: boolean, note: string): DaySummary {
  const d = scalePaces(scaleDistance(day, EASE_VOLUME, runDailyMile), EASE_PACE);
  return { ...d, note };
}

function easierOf(day: StoredDay, ctx: ActionContext): { after: DaySummary; cap: string | null } {
  if (day.kind === "streak") return { after: day, cap: "Already at the daily mile. That's as easy as the plan goes." };
  if (isHard(day.kind)) {
    const d = Math.max(MIN_DAY_MI, round05(day.distance_mi * 0.8));
    return { after: d <= 1 ? streakDay(ctx.paces, ctx.run_daily_mile) : easyDay(d, ctx.paces, false, "Swapped for an easy run."), cap: null };
  }
  const d = round05(day.distance_mi * 0.8);
  if (d <= MIN_DAY_MI) return { after: streakDay(ctx.paces, ctx.run_daily_mile), cap: null };
  return { after: scalePaces(scaleDistance(day, d / day.distance_mi, ctx.run_daily_mile), 1.03), cap: null };
}

/**
 * Validate + cap an action against the plan. Returns the changes (before /
 * after per day) and a `cap_note` when the request was clamped. Throws
 * ActionError when nothing allowed is left of the request.
 */
export function planAction(ctx: ActionContext, action: Action, params: Record<string, any> = {}): ActionResult {
  const rdm = ctx.run_daily_mile;
  const target = typeof params.local_date === "string" ? params.local_date : defaultTarget(ctx);
  let cap: string | null = null;
  const changes: Change[] = [];
  const push = (d: StoredDay, after: DaySummary) => {
    if (!sameDay(d, after) || d.title !== after.title || d.note !== after.note) changes.push({ local_date: d.local_date, before: toSummary(d), after: toSummary(after) });
  };
  let label = "";

  switch (action) {
    case "easier": {
      const d = dayAt(ctx, target);
      const r = easierOf(d, ctx);
      cap = r.cap;
      push(d, r.after);
      label = `Make ${dayLabel(ctx, target)} easier`;
      break;
    }
    case "shorter": {
      const d = dayAt(ctx, target);
      if (d.kind === "streak") cap = "Already at the daily mile. Every day is at least a mile.";
      else {
        const after = scaleDistance(d, 0.75, rdm);
        if (after.distance_mi <= MIN_DAY_MI) push(d, streakDay(ctx.paces, rdm));
        else push(d, after);
      }
      label = `Shorten ${dayLabel(ctx, target)}`;
      break;
    }
    case "just_mile": {
      const d = dayAt(ctx, target);
      if (d.kind === "streak") cap = "Already just the daily mile.";
      else push(d, streakDay(ctx.paces, rdm, "Just the mile today."));
      if (params.soften_next_hard) {
        const nh = nextHard(ctx, target, false);
        if (nh) push(nh, soften(nh, rdm, "Softened a little after you said you were sore."));
      }
      label = `Just the daily mile ${dayLabel(ctx, target)}`;
      break;
    }
    case "harder": {
      const d = dayAt(ctx, target);
      if (d.kind === "intervals") {
        const want = Math.max(1, Math.round(Number(params.reps ?? 1)) || 1);
        const add = Math.min(HARDER_MAX_REPS, want);
        if (want > add) cap = `Capped at +${HARDER_MAX_REPS} reps.`;
        const { reps } = intervalParts(d);
        let n = add;
        while (n > 0 && withReps(d, reps + n, rdm).distance_mi > ctx.long_cap) n--;
        if (n === 0) throw new ActionError("Already at your longest-run limit.");
        if (n < add) cap = `Capped at +${n} rep${n === 1 ? "" : "s"}: your longest-run limit is ${fmtMi(ctx.long_cap)} mi.`;
        push(d, withReps(d, reps + n, rdm));
      } else {
        const wantPct = Number(params.percent ?? 10) / 100;
        let pct = Math.min(HARDER_MAX_PCT, Math.max(0.05, Number.isFinite(wantPct) ? wantPct : 0.1));
        if (wantPct > HARDER_MAX_PCT) cap = `Capped at +${HARDER_MAX_PCT * 100}% distance.`;
        let dist = round2(d.distance_mi * (1 + pct));
        if (dist > ctx.long_cap) {
          dist = ctx.long_cap;
          cap = `Capped at ${fmtMi(ctx.long_cap)} mi, your longest-run limit for now.`;
        }
        if (dist <= d.distance_mi) throw new ActionError(cap ?? "Already at the limit for this day.");
        const after = d.kind === "streak" ? easyDay(dist, ctx.paces, false) : scaleDistance(d, dist / d.distance_mi, rdm);
        push(d, after);
      }
      label = `Make ${dayLabel(ctx, target)} harder`;
      break;
    }
    case "swap_hard_today": {
      const today = dayAt(ctx, ctx.today);
      if (today.status === "done") throw new ActionError("Today's run is already done.");
      let other: StoredDay | undefined;
      if (isHard(today.kind)) {
        other = ctx.days
          .filter((d) => d.local_date > ctx.today && !isHard(d.kind) && weekStart(d.local_date) === weekStart(ctx.today))
          .sort((a, b) => (a.local_date < b.local_date ? -1 : 1))
          .find((d) => {
            try {
              assertSpacing(ctx, [
                { local_date: d.local_date, before: d, after: today },
                { local_date: ctx.today, before: today, after: d },
              ]);
              return true;
            } catch {
              return false;
            }
          });
      } else {
        other = nextHard(ctx, ctx.today, true);
      }
      if (!other) throw new ActionError("Nothing left this week to swap with.");
      push(today, { ...toSummary(other), note: `Swapped with ${weekdayName(other.local_date)}.` });
      push(other, { ...toSummary(today), note: `Swapped with ${weekdayName(ctx.today)}.` });
      label = `Swap today with ${weekdayName(other.local_date)}`;
      break;
    }
    case "rest_tomorrow": {
      const tm = addDays(ctx.today, 1);
      const d = dayAt(ctx, tm);
      if (d.kind === "streak") cap = "Tomorrow is already just the daily mile.";
      else push(d, streakDay(ctx.paces, rdm, "Rest day: just the streak mile."));
      label = "Rest tomorrow (still the streak mile)";
      break;
    }
    case "move": {
      const from = params.from;
      const to = params.to;
      if (!isIsoDate(from) || !isIsoDate(to) || from === to) throw new ActionError("Move needs two different days.");
      const a = dayAt(ctx, from);
      const b = dayAt(ctx, to);
      push(a, { ...toSummary(b), note: `Moved from ${weekdayName(to)}.` });
      push(b, { ...toSummary(a), note: `Moved from ${weekdayName(from)}.` });
      label = `Move ${weekdayName(from)} to ${weekdayName(to)}`;
      break;
    }
    case "set_day": {
      if (ctx.source !== "claude") throw new ActionError("Only Claude can set a whole day.");
      const d = dayAt(ctx, String(params.local_date ?? ""));
      const kind = params.kind;
      if (!DAY_KINDS.includes(kind)) throw new ActionError("Unknown day kind.");
      let dist = Number(params.distance_mi);
      if (!Number.isFinite(dist)) throw new ActionError("distance_mi is required.");
      const notes: string[] = [];
      if (dist < MIN_DAY_MI) {
        dist = MIN_DAY_MI;
        notes.push("Every day is at least a mile.");
      }
      const maxUp = round2(Math.max(d.distance_mi * (1 + HARDER_MAX_PCT), d.distance_mi + 0.5));
      if (dist > maxUp) {
        dist = maxUp;
        notes.push(`Capped at +${HARDER_MAX_PCT * 100}% distance.`);
      }
      if (dist > ctx.long_cap) {
        dist = ctx.long_cap;
        notes.push(`Capped at ${fmtMi(ctx.long_cap)} mi, the longest-run limit.`);
      }
      let segs: Segment[] | null = validSegments(params.segments);
      if (segs && Math.abs(segmentsDistance(segs) - dist) > 0.05) segs = null;
      const after = segs ? summary(kind, segs, rdm, typeof params.note === "string" ? params.note.slice(0, 280) : null) : defaultDayOf(kind, dist, ctx);
      push(d, after);
      cap = notes.length ? notes.join(" ") : null;
      label = `Set ${dayLabel(ctx, d.local_date)}`;
      break;
    }
    default:
      throw new ActionError("Unknown action.");
  }

  if (!changes.length) throw new ActionError(cap ?? "Nothing to change.");
  validateChanges(ctx, changes, action);
  return { changes, cap_note: cap, summary: label };
}

/**
 * The plan-wide caps every change set must pass (at proposal time AND again
 * at apply time): no two hard days back to back while hard_days ≤ 3, never
 * below a mile, and a week's total ≤ its planned total + 0.5 mi (harder is
 * capped per day instead).
 */
export function validateChanges(ctx: ActionContext, changes: Change[], action: Action) {
  for (const c of changes) {
    if (c.after.distance_mi < MIN_DAY_MI) throw new ActionError("Every day is at least a mile.");
  }
  assertSpacing(ctx, changes);
  if (action === "harder") return;
  for (const date of new Set(changes.map((c) => weekStart(c.local_date)))) {
    const planned = weekPlannedTotal(ctx.days, date);
    const after = weekTotalAfter(ctx.days, changes, date);
    if (after > planned + WEEK_TOTAL_SLACK_MI) {
      throw new ActionError(`That would push this week past ${fmtMi(planned + WEEK_TOTAL_SLACK_MI)} mi, its planned total plus half a mile.`);
    }
  }
}

function dayLabel(ctx: ActionContext, date: string): string {
  if (date === ctx.today) return "today";
  if (date === addDays(ctx.today, 1)) return "tomorrow";
  return weekdayName(date);
}

function defaultDayOf(kind: DayKind, dist: number, ctx: ActionContext): DaySummary {
  const p = ctx.paces;
  const wu = dist >= 4 ? 1 : 0.5;
  switch (kind) {
    case "streak":
      return streakDay(p, ctx.run_daily_mile);
    case "easy":
      return easyDay(dist, p, false);
    case "long":
      return longDay(dist, p);
    case "tempo":
      return tempoDay({ work_mi: Math.max(0.5, dist - wu * 2), wu: dist - wu * 2 >= 0.5 ? wu : 0, cd: dist - wu * 2 >= 0.5 ? wu : 0, pace: p.tempo_s, easy: p.easy_s });
    case "intervals": {
      const body = Math.max(0.5, dist - wu * 2);
      const reps = Math.max(2, Math.round((body + 0.125) / 0.375));
      return intervalsDay({ reps, rep_mi: 0.25, recover_mi: 0.125, wu, cd: wu, pace: p.interval_s, easy: p.easy_s });
    }
    case "race_test":
      return raceTestDay({ dist: Math.max(0.5, dist - 1), pace: p.interval_s, easy: p.easy_s, label: "" });
  }
}

const SEG_KINDS = new Set(["warmup", "work", "recover", "cooldown", "steady"]);
export function validSegments(raw: unknown): Segment[] | null {
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > 60) return null;
  const out: Segment[] = [];
  for (const s of raw) {
    if (!s || typeof s !== "object" || !SEG_KINDS.has((s as any).kind)) return null;
    const seg: Segment = { kind: (s as any).kind };
    for (const k of ["distance_mi", "duration_s", "target_pace_s", "rep", "reps"] as const) {
      const v = (s as any)[k];
      if (v == null) continue;
      const n = Number(v);
      if (!Number.isFinite(n) || n < 0 || n > 100_000) return null;
      (seg as any)[k] = k === "distance_mi" ? round2(n) : Math.round(n);
    }
    if (seg.target_pace_s != null && (seg.target_pace_s < 180 || seg.target_pace_s > 2400)) return null;
    if (seg.distance_mi == null && seg.duration_s == null) return null;
    out.push(seg);
  }
  return out;
}

// ─── Check-ins ───────────────────────────────────────────────────────────

export const FEELINGS = ["tired", "sore", "normal", "great"] as const;
export type Feeling = (typeof FEELINGS)[number];

/** tired→easier, sore (or pain)→just_mile + soften next hard, great→harder, normal→none. */
export function checkinAction(feeling: Feeling | null, pain: boolean): { action: Action; params: Record<string, any>; rationale: string } | null {
  if (pain || feeling === "sore") {
    return { action: "just_mile", params: { soften_next_hard: true }, rationale: pain ? "You flagged pain: keep the streak with an easy mile, and the next hard day is softened." : "You're sore: just the mile today, and the next hard day is softened." };
  }
  if (feeling === "tired") return { action: "easier", params: {}, rationale: "You're tired: today gets easier." };
  if (feeling === "great") return { action: "harder", params: { reps: 1, percent: 10 }, rationale: "You feel great: a little more today, within the plan's limits." };
  return null;
}

// ─── Missed hard days ────────────────────────────────────────────────────

/**
 * Missed hard day ⇒ moves to the next non-hard day this week (≥ today, not
 * done, engine-owned) if spacing allows, else it's dropped. Returns the moves.
 */
export function planMissedMoves(days: StoredDay[], today: string, hardDays: number): { from: string; to: string }[] {
  const ws = weekStart(today);
  const week = days.filter((d) => weekStart(d.local_date) === ws).sort((a, b) => (a.local_date < b.local_date ? -1 : 1));
  const kinds = new Map(week.map((d) => [d.local_date, d.kind as string]));
  const movedFroms = new Set(days.map((d) => d.moved_from).filter(Boolean));
  const moves: { from: string; to: string }[] = [];
  for (const d of week) {
    if (d.local_date >= today || !isHard(d.kind) || d.status !== "missed" || movedFroms.has(d.local_date)) continue;
    // The missed day didn't happen: it no longer crowds anything.
    kinds.set(d.local_date, "streak");
    const to = week.find((c) => {
      if (c.local_date < today || isHard(kinds.get(c.local_date)!) || c.status === "done" || c.source !== "engine") return false;
      if (hardDays > 3) return true;
      return ![addDays(c.local_date, -1), addDays(c.local_date, 1)].some((n) => isHard(kinds.get(n) ?? "streak"));
    });
    if (to) {
      kinds.set(to.local_date, d.kind);
      moves.push({ from: d.local_date, to: to.local_date });
    }
  }
  return moves;
}

// ─── Goals validation ────────────────────────────────────────────────────

export function validateGoals(raw: unknown): Goal[] | string {
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > GOAL_TYPES.length) return "goals must be a non-empty array";
  const seen = new Set<string>();
  const out: Goal[] = [];
  for (const g of raw) {
    if (!g || typeof g !== "object" || !GOAL_TYPES.includes((g as any).type)) return "unknown goal type";
    const type = (g as any).type as GoalType;
    if (seen.has(type)) return "duplicate goal type";
    seen.add(type);
    const goal: Goal = { type };
    const ts = (g as any).target_seconds;
    if (ts != null) {
      const d = GOAL_DISTANCE_MI[type];
      const n = Number(ts);
      if (d == null || !Number.isInteger(n) || n < d * 241 || n > d * 2400) return "invalid target_seconds";
      goal.target_seconds = n;
    }
    const dm = (g as any).distance_mi;
    if (dm != null) {
      const n = Number(dm);
      if (type !== "more_miles" || !Number.isFinite(n) || n < MIN_WEEKLY_MI || n > 150) return "invalid distance_mi";
      goal.distance_mi = round2(n);
    }
    out.push(goal);
  }
  return out;
}
