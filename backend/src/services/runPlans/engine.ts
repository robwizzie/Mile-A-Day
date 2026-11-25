/**
 * Run Plans v2 engine — PURE. No DB, no clock, no Express.
 *
 * "The coach model decides. Code measures and checks." Every number in a
 * plan comes from here: paces (Daniels VDOT), HR bands, weekly volume and
 * phases, the week layout, each day's segments, the HARD-rule validator every
 * proposal from every source must pass, the formula's own adaptations
 * (missed runs, time off, pace updates, walk-day suggestions, check-in
 * tweaks), the post-run grade and the notification time. The research rules
 * these implement are numbered as in /p/mad-run-plans-research ("rule N").
 *
 * Dates are the phone's LOCAL dates ('YYYY-MM-DD'). Weeks run Mon–Sun.
 * Distances miles, paces seconds per mile, HR bpm.
 */

// ─── Dates ────────────────────────────────────────────────────────────────

const DAY_MS = 86_400_000;
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

export function isIsoDate(s: unknown): s is string {
  if (typeof s !== "string" || !ISO_DATE.test(s)) return false;
  const d = new Date(`${s}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
}
const toMs = (s: string) => Date.parse(`${s}T00:00:00Z`);
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
export function weekStart(s: string): string {
  return addDays(s, -weekdayIndex(s));
}
const WEEKDAY_NAMES = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
export const weekdayName = (s: string) => WEEKDAY_NAMES[weekdayIndex(s)];
export function dateRange(from: string, to: string): string[] {
  const out: string[] = [];
  for (let d = from; d <= to; d = addDays(d, 1)) out.push(d);
  return out;
}

// ─── Small helpers ──────────────────────────────────────────────────────

export const round2 = (n: number) => Math.round(n * 100) / 100;
const round1 = (n: number) => Math.round(n * 10) / 10;
const round05 = (n: number) => Math.round(n * 2) / 2;
const round025 = (n: number) => Math.round(n * 4) / 4;
const clamp = (n: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, n));
const fmtMi = (n: number) => `${round2(n)}`;
export function formatPace(s: number): string {
  const t = Math.round(s);
  const m = Math.floor(t / 60);
  const ss = t % 60;
  return `${m}:${ss < 10 ? "0" : ""}${ss}`;
}
export function formatDuration(seconds: number): string {
  const t = Math.round(seconds);
  const h = Math.floor(t / 3600);
  const m = Math.floor((t % 3600) / 60);
  const s = t % 60;
  const ss = s < 10 ? `0${s}` : `${s}`;
  return h > 0 ? `${h}:${m < 10 ? `0${m}` : m}:${ss}` : `${m}:${ss}`;
}
const median = (xs: number[]) => {
  if (!xs.length) return null;
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.floor(s.length / 2)];
};

export class EngineError extends Error {
  constructor(
    public code: string,
    public extra: Record<string, unknown> = {},
  ) {
    super(code);
  }
}

// ─── Enums ────────────────────────────────────────────────────────────────

export const GOAL_TYPES = ["distance_time", "just_improve", "burn_calories"] as const;
export type GoalType = (typeof GOAL_TYPES)[number];
export const GOAL_DISTANCES = ["mile", "5k", "10k", "half", "marathon", "custom"] as const;
export type GoalDistance = (typeof GOAL_DISTANCES)[number];
export const DISTANCE_MI: Record<Exclude<GoalDistance, "custom">, number> = {
  mile: 1,
  "5k": 3.10686,
  "10k": 6.21371,
  half: 13.1094,
  marathon: 26.2188,
};
const DISTANCE_LABEL: Record<GoalDistance, string> = {
  mile: "mile",
  "5k": "5K",
  "10k": "10K",
  half: "half marathon",
  marathon: "marathon",
  custom: "race",
};

export interface Goal {
  type: GoalType;
  distance?: GoalDistance;
  distance_mi?: number;
  target_s?: number | null;
  weekly_minutes?: number;
}

export const DAY_KINDS = ["easy", "long", "tempo", "intervals", "race", "calibration", "walk"] as const;
export type DayKind = (typeof DAY_KINDS)[number];
export const HARD_KINDS: ReadonlySet<string> = new Set(["tempo", "intervals", "race", "calibration"]);
export const isHard = (k: string) => HARD_KINDS.has(k);
export const isKey = (k: string) => isHard(k) || k === "long";
export const isRun = (k: string) => k !== "walk";

export const WALK_MODES = ["built_in", "fixed", "flexible"] as const;
export type WalkMode = (typeof WALK_MODES)[number];
export type Difficulty = 1 | 2 | 3 | 4;
export const DIFFICULTY_LABEL: Record<Difficulty, string> = {
  1: "Easy does it",
  2: "Steady",
  3: "Push",
  4: "All in",
};
export const PROPOSAL_SOURCES = ["formula", "apple", "anthropic", "overseer", "user_claude", "user"] as const;
export type ProposalSource = (typeof PROPOSAL_SOURCES)[number];
export const PROPOSAL_KINDS = [
  "adjust",
  "missed_run",
  "return_from_break",
  "pace_update",
  "checkin",
  "walk_day_earned",
  "walk_day_needed",
  "post_run",
  "weekly_review",
  "plan_build",
] as const;
export type ProposalKind = (typeof PROPOSAL_KINDS)[number];
export type Phase = "base" | "build" | "peak" | "taper" | "race" | "rolling" | "cutback" | "return";
export const SHOE_RUN_TYPES = ["easy", "long", "tempo", "intervals", "race", "walk"] as const;
export type ShoeRunType = (typeof SHOE_RUN_TYPES)[number];
export const shoeRunTypeFor = (k: DayKind): ShoeRunType =>
  k === "calibration" ? "race" : (k as ShoeRunType);

// ─── Fitness profile (from the phone) ─────────────────────────────────────

export interface Zone {
  zone: number;
  low: number;
  high: number;
}
export interface BestEffort {
  distance: GoalDistance;
  seconds: number;
  date?: string | null;
  indoor?: boolean | null;
  distance_mi?: number;
}
export interface FitnessProfile {
  computed_at?: string | null;
  runs_analyzed?: number | null;
  weekly_miles_4w?: number | null;
  weekly_miles_by_week?: number[] | null;
  longest_run_30d_mi?: number | null;
  longest_run_mi?: number | null;
  treadmill_fraction?: number | null;
  has_hr?: boolean | null;
  max_hr?: number | null;
  max_hr_source?: string | null;
  resting_hr?: number | null;
  resting_hr_7d?: (number | null)[] | null;
  hrv_7d_ms?: (number | null)[] | null;
  hrv_baseline_ms?: number | null;
  lthr?: number | null;
  zones?: Zone[] | null;
  zone_method?: string | null;
  vdot?: number | null;
  critical_speed_mps?: number | null;
  zone2_pace_s?: number | null;
  zone2_hr?: number | null;
  easy_pace_s?: number | null;
  best_efforts?: BestEffort[] | null;
  race_estimates?: Record<string, number> | null;
  steady_segments?: Record<string, unknown> | null;
  run_walk?: Record<string, unknown> | null;
  typical_run_hour?: number | null;
  age?: number | null;
  experience?: "new" | "novice" | "experienced" | null;
  calibration_needed?: boolean | null;
  calibration_kind?: "mile_tt_talk_test" | "3k" | "5k" | "lthr_30min" | null;
  [k: string]: unknown;
}

const num = (v: unknown, lo: number, hi: number): number | null => {
  if (v === null || v === undefined) return null;
  const n = Number(v);
  if (!Number.isFinite(n) || n < lo || n > hi) throw new EngineError("invalid_profile", { value: v, range: [lo, hi] });
  return n;
};
const numArr = (v: unknown, lo: number, hi: number, max = 14): (number | null)[] | null => {
  if (v === null || v === undefined) return null;
  if (!Array.isArray(v) || v.length > max) throw new EngineError("invalid_profile");
  return v.map((x) => (x === null ? null : num(x, lo, hi)));
};

/** Validate the uploaded profile: known fields range-checked, unknown fields kept. */
export function normalizeProfile(raw: unknown): FitnessProfile {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new EngineError("invalid_profile");
  const r = raw as Record<string, unknown>;
  const zones =
    r.zones == null
      ? null
      : Array.isArray(r.zones) && r.zones.length <= 7
        ? r.zones.map((z: any) => ({ zone: num(z?.zone, 1, 7)!, low: num(z?.low, 40, 230)!, high: num(z?.high, 40, 230)! }))
        : (() => {
            throw new EngineError("invalid_profile", { field: "zones" });
          })();
  const exp = r.experience;
  if (exp != null && exp !== "new" && exp !== "novice" && exp !== "experienced") throw new EngineError("invalid_profile", { field: "experience" });
  const ck = r.calibration_kind;
  if (ck != null && !["mile_tt_talk_test", "3k", "5k", "lthr_30min"].includes(ck as string)) throw new EngineError("invalid_profile", { field: "calibration_kind" });
  const efforts = r.best_efforts == null
    ? null
    : Array.isArray(r.best_efforts) && r.best_efforts.length <= 20
      ? r.best_efforts.map((e: any) => {
          if (!GOAL_DISTANCES.includes(e?.distance)) throw new EngineError("invalid_profile", { field: "best_efforts" });
          return { ...e, seconds: num(e.seconds, 120, 36000)! } as BestEffort;
        })
      : (() => {
          throw new EngineError("invalid_profile", { field: "best_efforts" });
        })();
  return {
    ...r,
    weekly_miles_4w: num(r.weekly_miles_4w, 0, 250),
    weekly_miles_by_week: numArr(r.weekly_miles_by_week, 0, 250, 12) as number[] | null,
    longest_run_30d_mi: num(r.longest_run_30d_mi, 0, 120),
    longest_run_mi: num(r.longest_run_mi, 0, 200),
    treadmill_fraction: num(r.treadmill_fraction, 0, 1),
    has_hr: r.has_hr == null ? null : Boolean(r.has_hr),
    max_hr: num(r.max_hr, 120, 230),
    resting_hr: num(r.resting_hr, 30, 110),
    resting_hr_7d: numArr(r.resting_hr_7d, 30, 120),
    hrv_7d_ms: numArr(r.hrv_7d_ms, 5, 300),
    hrv_baseline_ms: num(r.hrv_baseline_ms, 5, 300),
    lthr: num(r.lthr, 100, 220),
    zones,
    vdot: num(r.vdot, 15, 90),
    critical_speed_mps: num(r.critical_speed_mps, 1.5, 7),
    zone2_pace_s: num(r.zone2_pace_s, 240, 1500),
    zone2_hr: num(r.zone2_hr, 60, 220),
    easy_pace_s: num(r.easy_pace_s, 240, 1500),
    best_efforts: efforts,
    typical_run_hour: num(r.typical_run_hour, 0, 23),
    age: num(r.age, 10, 100),
    experience: (exp as FitnessProfile["experience"]) ?? null,
    calibration_needed: r.calibration_needed == null ? null : Boolean(r.calibration_needed),
    calibration_kind: (ck as FitnessProfile["calibration_kind"]) ?? null,
  };
}

// ─── Paces (Daniels VDOT) ─────────────────────────────────────────────────

const M_PER_MI = 1609.344;
/** VO2 cost (ml/kg/min) at v m/min. */
const vo2At = (v: number) => -4.6 + 0.182258 * v + 0.000104 * v * v;
/** Fraction of VO2max sustainable for t minutes. */
const pctMaxFor = (tMin: number) => 0.8 + 0.1894393 * Math.exp(-0.012778 * tMin) + 0.2989558 * Math.exp(-0.1932605 * tMin);
export function vdotFromRace(distanceMi: number, seconds: number): number {
  const tMin = seconds / 60;
  const v = (distanceMi * M_PER_MI) / tMin;
  return vo2At(v) / pctMaxFor(tMin);
}
function velocityForVo2(vo2: number): number {
  const a = 0.000104, b = 0.182258, c = -(4.6 + vo2);
  return (-b + Math.sqrt(b * b - 4 * a * c)) / (2 * a);
}
/** Pace (s/mi) at a fraction of VDOT. */
export function paceAt(vdot: number, fraction: number): number {
  return (M_PER_MI / velocityForVo2(vdot * fraction)) * 60;
}
/** Race time (s) for a distance at a VDOT (bisection on Daniels' formula). */
export function raceTimeFor(vdot: number, distanceMi: number): number {
  let lo = distanceMi * 150, hi = distanceMi * 1500;
  for (let i = 0; i < 60; i++) {
    const mid = (lo + hi) / 2;
    if (vdotFromRace(distanceMi, mid) > vdot) lo = mid;
    else hi = mid;
  }
  return Math.round((lo + hi) / 2);
}
/** Riegel (research: 1.06; 1.07+ for recreational marathoners). */
export function riegel(t1: number, d1: number, d2: number, exp = 1.06): number {
  return t1 * Math.pow(d2 / d1, exp);
}

export const DEFAULT_VDOT = 30;
/** Fractions of VDOT (in the VO2–velocity curve) that reproduce Daniels' tables (VDOT 40: E 9:12–10:30, M 8:24, T 7:52, I 7:14, R 6:48). */
export const EASY_FRACTION: [number, number] = [0.76, 0.65];
export interface Paces {
  vdot: number;
  source: "vdot" | "best_effort" | "critical_speed" | "easy_pace" | "default";
  /** [fast, slow] */
  easy_s: [number, number];
  long_s: [number, number];
  marathon_s: number;
  threshold_s: number;
  interval_s: number;
  rep_s: number;
}

export function goalDistanceMi(g: Pick<Goal, "distance" | "distance_mi">): number | null {
  if (!g.distance) return null;
  if (g.distance === "custom") return g.distance_mi ?? null;
  return DISTANCE_MI[g.distance];
}

/** The VDOT the plan is built on: profile → best effort → critical speed → easy pace → default. */
export function resolveVdot(p: FitnessProfile | null): { vdot: number; source: Paces["source"] } {
  if (p?.vdot) return { vdot: p.vdot, source: "vdot" };
  const efforts = (p?.best_efforts ?? [])
    .map((e) => {
      const d = e.distance === "custom" ? e.distance_mi ?? null : DISTANCE_MI[e.distance];
      return d ? vdotFromRace(d, e.seconds) : null;
    })
    .filter((x): x is number => x != null && x > 15 && x < 90);
  if (efforts.length) return { vdot: Math.max(...efforts), source: "best_effort" };
  if (p?.critical_speed_mps) {
    // Critical speed ≈ the pace held for ~30–40 min: score it as a 10K.
    const d = 6.21371;
    return { vdot: vdotFromRace(d, (d * M_PER_MI) / p.critical_speed_mps), source: "critical_speed" };
  }
  const easy = p?.zone2_pace_s ?? p?.easy_pace_s;
  if (easy) {
    const mid = (EASY_FRACTION[0] + EASY_FRACTION[1]) / 2;
    let lo = 15, hi = 85;
    for (let i = 0; i < 50; i++) {
      const m = (lo + hi) / 2;
      if (paceAt(m, mid) > easy) lo = m;
      else hi = m;
    }
    return { vdot: (lo + hi) / 2, source: "easy_pace" };
  }
  return { vdot: DEFAULT_VDOT, source: "default" };
}

export function pacesFor(vdot: number, source: Paces["source"] = "vdot", factor = 1): Paces {
  const p = (f: number) => Math.round(paceAt(vdot, f) * factor);
  return {
    vdot: round1(vdot),
    source,
    easy_s: [p(EASY_FRACTION[0]), p(EASY_FRACTION[1])],
    long_s: [p(0.74), p(0.63)],
    marathon_s: p(0.853),
    threshold_s: p(0.926),
    interval_s: p(1.027),
    rep_s: p(1.109),
  };
}

export interface HrBands {
  has_hr: boolean;
  easy_ceiling: number | null;
  tempo: [number, number] | null;
  zones: Zone[];
}
/** Rule 14–15: zones from the phone (LTHR → HRR → %HRmax), else derived; never 220 − age. */
export function hrBandsFor(p: FitnessProfile | null): HrBands {
  const zones = p?.zones ?? [];
  const z2 = zones.find((z) => z.zone === 2);
  const z4 = zones.find((z) => z.zone === 4);
  let ceiling: number | null = z2?.high ?? null;
  let tempo: [number, number] | null = z4 ? [z4.low, z4.high] : null;
  if (ceiling == null && p?.lthr) ceiling = Math.round(p.lthr * 0.89);
  if (ceiling == null && p?.max_hr && p?.resting_hr) ceiling = Math.round(p.resting_hr + 0.7 * (p.max_hr - p.resting_hr));
  if (ceiling == null && p?.max_hr) ceiling = Math.round(p.max_hr * 0.8);
  if (tempo == null && p?.lthr) tempo = [Math.round(p.lthr * 0.95), Math.round(p.lthr * 1.0)];
  if (tempo == null && p?.max_hr) tempo = [Math.round(p.max_hr * 0.86), Math.round(p.max_hr * 0.91)];
  const has = Boolean(p?.has_hr) && ceiling != null;
  return { has_hr: has, easy_ceiling: has ? ceiling : null, tempo: has ? tempo : null, zones: has ? zones : [] };
}

// ─── Segments / days ──────────────────────────────────────────────────────

export type SegmentKind = "warmup" | "steady" | "work" | "recover" | "cooldown" | "walk";
export interface Segment {
  kind: SegmentKind;
  distance_mi: number | null;
  duration_s: number | null;
  rep: number | null;
  reps: number | null;
  target_pace_s: number | null;
  pace_low_s: number | null;
  pace_high_s: number | null;
  speed_mph: number | null;
  hr_low: number | null;
  hr_high: number | null;
  zone: number | null;
  score_by: "pace" | "hr" | "pace_and_hr" | "effort" | null;
  feel: string;
}

/** What a coach model sends: intent only. Every number is computed by `buildDay`. */
export interface DaySpec {
  kind: DayKind;
  distance_mi?: number | null;
  work_mi?: number | null;
  reps?: number | null;
  rep_mi?: number | null;
  rep_s?: number | null;
  recover_s?: number | null;
  pace_factor?: number | null;
  strides?: boolean | null;
  note?: string | null;
}

export interface Day {
  kind: DayKind;
  title: string;
  subtitle: string;
  distance_mi: number;
  est_duration_s: number;
  is_hard: boolean;
  is_key: boolean;
  flex: boolean;
  phase: Phase;
  week_index: number;
  segments: Segment[];
  note: string | null;
  /** The spec this day was built from (proposals rebuild from it). */
  spec: DaySpec;
}

export interface BuildContext {
  paces: Paces;
  hr: HrBands;
  focus: GoalDistance | "calories";
  /** Goal pace (s/mi) for race days, if a target time was given. */
  race_pace_s?: number | null;
}

const FEEL = {
  easy: "Conversational. You could talk in full sentences the whole way.",
  long: "Easy and patient. Breathing steady; slow down on hills rather than push.",
  tempo: "Comfortably hard. You could say a few words, not sentences.",
  work: "Hard but controlled. You couldn't hold a conversation.",
  recover: "Easy jog or walk. Let your breathing settle before the next one.",
  warmup: "Start easy and let your legs wake up.",
  cooldown: "Bring it down gently.",
  walk: "Easy walk. 1 mile or 10k steps keeps your streak.",
  race: "Even effort. Hold back the first third, then race.",
  calibration: "A hard, even effort you could just hold to the end. This sets your paces.",
};

const MIN_RUN_MI = 1;
const LONG_MAX_S = 150 * 60;
const easyMid = (p: Paces) => Math.round((p.easy_s[0] + p.easy_s[1]) / 2);

function seg(
  kind: SegmentKind,
  len: { distance_mi?: number; duration_s?: number },
  pace: { target: number | null; low?: number | null; high?: number | null },
  hr: { low?: number | null; high?: number | null; zone?: number | null },
  scoreBy: Segment["score_by"],
  feel: string,
  rep: { rep?: number; reps?: number } = {},
): Segment {
  const t = pace.target != null ? Math.round(pace.target) : null;
  return {
    kind,
    distance_mi: len.distance_mi != null ? round2(len.distance_mi) : null,
    duration_s: len.distance_mi == null && len.duration_s != null ? Math.round(len.duration_s) : null,
    rep: rep.rep ?? null,
    reps: rep.reps ?? null,
    target_pace_s: t,
    pace_low_s: pace.low != null ? Math.round(pace.low) : t,
    pace_high_s: pace.high != null ? Math.round(pace.high) : t,
    speed_mph: t ? round1(3600 / t) : null,
    hr_low: hr.low ?? null,
    hr_high: hr.high ?? null,
    zone: hr.zone ?? null,
    score_by: scoreBy,
    feel,
  };
}

function easySeg(kind: SegmentKind, mi: number, ctx: BuildContext, f: number, longRun = false): Segment {
  const band = longRun ? ctx.paces.long_s : ctx.paces.easy_s;
  return seg(
    kind,
    { distance_mi: mi },
    { target: ((band[0] + band[1]) / 2) * f, low: band[0] * f, high: band[1] * f },
    { high: ctx.hr.easy_ceiling, zone: ctx.hr.has_hr ? 2 : null },
    ctx.hr.has_hr ? "hr" : "pace",
    kind === "warmup" ? FEEL.warmup : kind === "cooldown" ? FEEL.cooldown : longRun ? FEEL.long : FEEL.easy,
  );
}

const REP_LABEL: Record<string, string> = { "0.25": "400m", "0.5": "800m", "0.62": "1K", "0.75": "1200m", "1": "1 mi" };
const repLabel = (mi: number) => REP_LABEL[String(round2(mi))] ?? `${fmtMi(mi)} mi`;

function segDistance(segs: Segment[], ctx: BuildContext): number {
  return round2(
    segs.reduce((a, s) => {
      if (s.kind === "walk") return a;
      if (s.distance_mi != null) return a + s.distance_mi;
      const pace = s.target_pace_s ?? easyMid(ctx.paces) * 1.15;
      return a + (s.duration_s ?? 0) / pace;
    }, 0),
  );
}
function segDuration(segs: Segment[], ctx: BuildContext): number {
  return Math.round(
    segs.reduce((a, s) => {
      if (s.duration_s != null) return a + s.duration_s;
      const pace = s.target_pace_s ?? (s.kind === "walk" ? 1080 : easyMid(ctx.paces));
      return a + (s.distance_mi ?? 0) * pace;
    }, 0),
  );
}

function validSpec(spec: DaySpec): DaySpec {
  if (!spec || !DAY_KINDS.includes(spec.kind)) throw new EngineError("invalid_day_spec", { field: "kind" });
  const n = (v: unknown, lo: number, hi: number, field: string) => {
    if (v === null || v === undefined) return null;
    const x = Number(v);
    if (!Number.isFinite(x) || x < lo || x > hi) throw new EngineError("invalid_day_spec", { field, range: [lo, hi] });
    return x;
  };
  return {
    kind: spec.kind,
    distance_mi: n(spec.distance_mi, 0.5, 50, "distance_mi"),
    work_mi: n(spec.work_mi, 0.25, 20, "work_mi"),
    reps: n(spec.reps, 1, 30, "reps") != null ? Math.round(Number(spec.reps)) : null,
    rep_mi: n(spec.rep_mi, 0.05, 3, "rep_mi"),
    rep_s: n(spec.rep_s, 10, 1800, "rep_s"),
    recover_s: n(spec.recover_s, 0, 600, "recover_s"),
    pace_factor: n(spec.pace_factor, 0.85, 1.15, "pace_factor"),
    strides: spec.strides == null ? null : Boolean(spec.strides),
    note: typeof spec.note === "string" ? spec.note.slice(0, 600) : null,
  };
}

/** A full Day from a DaySpec: every distance, pace, speed and HR band computed here. */
export function buildDay(
  rawSpec: DaySpec,
  ctx: BuildContext,
  meta: { phase?: Phase; week_index?: number; flex?: boolean } = {},
): Day {
  const spec = validSpec(rawSpec);
  const f = spec.pace_factor ?? 1;
  const p = ctx.paces;
  const segs: Segment[] = [];
  let title = "";
  let subtitle = "";
  let note: string | null = spec.note ?? null;
  const total = spec.distance_mi ?? null;
  switch (spec.kind) {
    case "walk": {
      segs.push(seg("walk", { distance_mi: 1 }, { target: null }, {}, null, FEEL.walk));
      title = "Walk day";
      subtitle = "1 mile or 10k steps keeps the streak";
      note ??= "Walk it off. A walk day still keeps the streak: 1 mile or 10k steps.";
      break;
    }
    case "easy":
    case "long": {
      const long = spec.kind === "long";
      const d = Math.max(MIN_RUN_MI, round2(total ?? (long ? 4 : 3)));
      segs.push(easySeg("steady", d, ctx, f, long));
      if (spec.strides) {
        for (let r = 1; r <= 4; r++) {
          segs.push(seg("work", { duration_s: 20 }, { target: p.rep_s * f }, {}, "pace", "Quick and relaxed, not a sprint.", { rep: r, reps: 4 }));
          if (r < 4) segs.push(seg("recover", { duration_s: 60 }, { target: null }, {}, null, FEEL.recover, { rep: r, reps: 4 }));
        }
      }
      const band = long ? p.long_s : p.easy_s;
      title = `${long ? "Long" : "Easy"} ${fmtMi(d)} mi${spec.strides ? " + strides" : ""}`;
      subtitle = `At ${formatPace(band[0] * f)}–${formatPace(band[1] * f)}/mi${ctx.hr.easy_ceiling ? `, under ${ctx.hr.easy_ceiling} bpm` : ""}`;
      note ??= long
        ? "Long and easy. Time on your feet builds the engine; keep it conversational."
        : ctx.hr.easy_ceiling
          ? `Easy means easy: zone 2, under ${ctx.hr.easy_ceiling} bpm.`
          : "Easy means easy: you should be able to talk in full sentences.";
      break;
    }
    case "tempo": {
      const wu = total != null && total >= 6 ? 1 : 0.5;
      const work = round025(spec.work_mi ?? Math.max(1, (total ?? 4) - 2 * wu));
      const rest = Math.max(0, round2((total ?? work + 2 * wu) - work));
      const w = rest > 0 ? round2(Math.min(wu, rest / 2)) : 0;
      const c = round2(rest - w);
      if (w > 0) segs.push(easySeg("warmup", w, ctx, f));
      const t = p.threshold_s * f;
      segs.push(seg("work", { distance_mi: work }, { target: t, low: t - 8, high: t + 8 }, { low: ctx.hr.tempo?.[0] ?? null, high: ctx.hr.tempo?.[1] ?? null, zone: ctx.hr.has_hr ? 4 : null }, ctx.hr.has_hr ? "pace_and_hr" : "pace", FEEL.tempo));
      if (c > 0) segs.push(easySeg("cooldown", c, ctx, f));
      title = `Tempo ${fmtMi(segDistance(segs, ctx))} mi`;
      subtitle = `${fmtMi(work)} mi at ${formatPace(t)}/mi (${round1(3600 / t)} mph)`;
      note ??= "Tempo day: comfortably hard in the middle, easy on both ends.";
      break;
    }
    case "intervals": {
      const reps = spec.reps ?? 5;
      const repMi = spec.rep_s != null ? null : spec.rep_mi ?? (ctx.focus === "mile" ? 0.25 : 0.5);
      const t = (ctx.focus === "mile" && repMi != null && repMi <= 0.25 ? (p.interval_s + p.rep_s) / 2 : p.interval_s) * f;
      const repDur = repMi != null ? repMi * t : spec.rep_s!;
      const recover = spec.recover_s ?? (repDur <= 120 ? 120 : repDur <= 240 ? 150 : 180);
      const tol = Math.max(3, t * 0.0125);
      const wu = total != null && total >= 6 ? 1 : 0.75;
      segs.push(easySeg("warmup", wu, ctx, f));
      for (let r = 1; r <= reps; r++) {
        segs.push(
          seg(
            "work",
            repMi != null ? { distance_mi: repMi } : { duration_s: spec.rep_s! },
            { target: t, low: t - tol, high: t + tol },
            { zone: ctx.hr.has_hr ? 5 : null },
            repDur < 120 || !ctx.hr.has_hr ? "pace" : "pace_and_hr",
            FEEL.work,
            { rep: r, reps },
          ),
        );
        if (r < reps) segs.push(seg("recover", { duration_s: recover }, { target: null }, {}, null, FEEL.recover, { rep: r, reps }));
      }
      const sofar = segDistance(segs, ctx);
      const cd = total != null ? Math.max(0.25, round2(total - sofar)) : wu;
      segs.push(easySeg("cooldown", cd, ctx, f));
      title = repMi != null ? `${reps} × ${repLabel(repMi)}` : `${reps} × ${formatDuration(spec.rep_s!)}`;
      subtitle = `At ${formatPace(t)}/mi (${round1(3600 / t)} mph), ${formatDuration(recover)} jog between`;
      note ??= "Intervals day. Easy days stay easy so this one can be fast.";
      break;
    }
    case "race": {
      const d = total ?? 3.10686;
      const t = (ctx.race_pace_s ?? paceAt(p.vdot, pctMaxFor((d * paceAt(p.vdot, 0.9)) / 60))) * 1;
      segs.push(easySeg("warmup", 0.5, ctx, 1));
      segs.push(seg("work", { distance_mi: d }, { target: t, low: t - 10, high: t + 10 }, {}, "pace", FEEL.race));
      title = `Race: ${fmtMi(d)} mi`;
      subtitle = `Goal pace ${formatPace(t)}/mi`;
      note ??= "Race day. Go see what the training built.";
      break;
    }
    case "calibration": {
      const d = total ?? 1;
      const t = p.interval_s * f;
      segs.push(easySeg("warmup", 0.75, ctx, f));
      segs.push(seg("work", { distance_mi: d }, { target: t, low: t - 30, high: t + 30 }, {}, "effort", FEEL.calibration));
      segs.push(easySeg("cooldown", 0.5, ctx, f));
      title = d <= 1.01 ? "1-mile time trial" : `${fmtMi(d)} mi time trial`;
      subtitle = "Hard, even effort. This sets your paces.";
      note ??= "Calibration run: run it hard and even. Your plan's paces come from it.";
      break;
    }
  }
  const distance = spec.kind === "walk" ? 0 : segDistance(segs, ctx);
  return {
    kind: spec.kind,
    title,
    subtitle,
    distance_mi: distance,
    est_duration_s: segDuration(segs, ctx),
    is_hard: isHard(spec.kind),
    is_key: isKey(spec.kind),
    flex: Boolean(meta.flex),
    phase: meta.phase ?? "rolling",
    week_index: meta.week_index ?? 0,
    segments: segs,
    note,
    spec: { ...spec, distance_mi: spec.kind === "walk" ? null : spec.distance_mi ?? distance },
  };
}

/** Rebuild an existing day's spec with changes (keeps its meta). */
export function rebuild(day: Day, patch: Partial<DaySpec>, ctx: BuildContext): Day {
  return buildDay({ ...day.spec, ...patch, note: patch.note ?? null }, ctx, { phase: day.phase, week_index: day.week_index, flex: day.flex });
}

// ─── Plan settings → structure ────────────────────────────────────────────

export interface PlanSettings {
  goals: Goal[];
  target_date: string | null;
  runs_per_week: number;
  difficulty: Difficulty;
  walk_mode: WalkMode;
  fixed_walk_days: number[];
  start_date: string;
  /** Plan-wide pace multiplier from applied pace updates (>1 slower). */
  pace_factor?: number;
}

export function validateGoals(raw: unknown): Goal[] {
  if (!Array.isArray(raw) || raw.length < 1 || raw.length > 4) throw new EngineError("invalid_goals");
  let ji = 0, bc = 0;
  return raw.map((g: any) => {
    if (!g || !GOAL_TYPES.includes(g.type)) throw new EngineError("invalid_goals");
    if (g.type === "distance_time") {
      if (!GOAL_DISTANCES.includes(g.distance)) throw new EngineError("invalid_goals", { field: "distance" });
      const out: Goal = { type: "distance_time", distance: g.distance };
      if (g.distance === "custom") {
        const d = Number(g.distance_mi);
        if (!Number.isFinite(d) || d < 0.5 || d > 31.1) throw new EngineError("invalid_goals", { field: "distance_mi" });
        out.distance_mi = round2(d);
      } else out.distance_mi = round2(DISTANCE_MI[g.distance as Exclude<GoalDistance, "custom">]);
      if (g.target_s != null) {
        const t = Number(g.target_s);
        if (!Number.isFinite(t) || t / out.distance_mi! < 180 || t / out.distance_mi! > 1800) throw new EngineError("invalid_goals", { field: "target_s" });
        out.target_s = Math.round(t);
      } else out.target_s = null;
      return out;
    }
    if (g.type === "just_improve") {
      if (++ji > 1) throw new EngineError("invalid_goals");
      return { type: "just_improve" };
    }
    if (++bc > 1) throw new EngineError("invalid_goals");
    const m = g.weekly_minutes == null ? 150 : Number(g.weekly_minutes);
    if (!Number.isFinite(m) || m < 60 || m > 600) throw new EngineError("invalid_goals", { field: "weekly_minutes" });
    return { type: "burn_calories", weekly_minutes: Math.round(m) };
  });
}

/** The goal the plan's sessions are shaped around (rule 23). */
export function focusOf(goals: Goal[]): GoalDistance | "calories" {
  const dt = goals.filter((g) => g.type === "distance_time");
  if (dt.length) {
    // The longest race distance decides the structure; shorter goals ride along.
    const longest = dt.reduce((a, b) => ((goalDistanceMi(b) ?? 0) > (goalDistanceMi(a) ?? 0) ? b : a));
    return longest.distance!;
  }
  if (goals.some((g) => g.type === "just_improve")) return "5k";
  return "calories";
}
const focusDistanceMi = (goals: Goal[]) =>
  Math.max(0, ...goals.filter((g) => g.type === "distance_time").map((g) => goalDistanceMi(g) ?? 0));

/** Rule 3: hard sessions per week from runs/week, difficulty and experience. */
export function hardSessionsFor(
  runsPerWeek: number,
  difficulty: Difficulty,
  experience: FitnessProfile["experience"],
  goals: Goal[],
): number {
  let h: number = ({ 1: 0, 2: 1, 3: 2, 4: 3 } as const)[difficulty];
  if (experience === "new") h = 0; // strides only for a new runner's first 8 weeks
  else if (experience === "novice") h = Math.min(h, 1);
  const byRuns = runsPerWeek <= 1 ? 0 : runsPerWeek === 2 ? 1 : runsPerWeek <= 5 ? 2 : 3;
  h = Math.min(h, byRuns, 3);
  if (focusOf(goals) === "calories") h = Math.min(h, 1); // rule 22
  return h;
}

/** Rule 9 taper length by race distance. */
export function taperDays(distanceMi: number): number {
  if (distanceMi <= 3.2) return 7;
  if (distanceMi <= 6.3) return 9;
  if (distanceMi <= 13.2) return 14;
  return 21;
}
const TAPER_FACTORS: Record<number, number[]> = { 1: [0.55], 2: [0.75, 0.5], 3: [0.8, 0.65, 0.5] };

export interface WeekInfo {
  index: number;
  monday: string;
  phase: Phase;
  cutback: boolean;
  volume_mi: number;
  hard: number;
  long: boolean;
  retest: boolean;
}

/** Rule 5: the next week's increase — smaller of +10% or +2 mi, ≥ +1 under 10 mi/wk, never > 30%. */
export function rampStep(current: number, difficulty: Difficulty): number {
  const pct = ({ 1: 0.05, 2: 0.075, 3: 0.1, 4: 0.1 } as const)[difficulty];
  let inc = Math.min(current * pct, 2);
  if (current < 10) inc = Math.max(inc, difficulty === 1 ? 0.5 : 1);
  return Math.min(inc, Math.max(0.5, current * 0.3));
}

function peakWeekly(s: PlanSettings, start: number, paces: Paces): number {
  const dfac = ({ 1: 0.75, 2: 0.9, 3: 1, 4: 1.15 } as const)[s.difficulty];
  const focus = focusOf(s.goals);
  let peak: number;
  if (focus === "calories") {
    const g = s.goals.find((x) => x.type === "burn_calories");
    const minutes = (g?.weekly_minutes ?? 150) * (s.difficulty === 4 ? 1.5 : 1); // stretch 225+
    peak = (minutes * 60) / easyMid(paces);
  } else {
    const byFocus: Record<GoalDistance, number> = { mile: 15, "5k": 20, "10k": 25, half: 30, marathon: 40, custom: 20 };
    peak = byFocus[focus] * dfac;
    if (focus === "custom") peak = Math.max(15, focusDistanceMi(s.goals) * 2.2) * dfac;
    if (s.goals.some((g) => g.type === "just_improve") && !s.goals.some((g) => g.type === "distance_time")) peak = Math.min(30, Math.max(start * 1.5, 15)) * dfac;
  }
  const byRuns = s.runs_per_week * (s.runs_per_week <= 2 ? 5 : 7);
  return Math.max(start, Math.min(peak, byRuns));
}

export function startWeekly(s: PlanSettings, profile: FitnessProfile | null): number {
  return Math.max(s.runs_per_week * MIN_RUN_MI, round1(profile?.weekly_miles_4w ?? 0));
}

const cutbackEvery = (p: FitnessProfile | null) => ((p?.age ?? 0) >= 50 || p?.experience === "new" ? 3 : 4);

/** Week descriptors 0..n−1: phases (rule 1), cutbacks (rule 2), ramp (rule 5), taper (rule 9). */
export function planWeeks(s: PlanSettings, profile: FitnessProfile | null, paces: Paces, through: number): WeekInfo[] {
  const start = startWeekly(s, profile);
  const peak = peakWeekly(s, start, paces);
  const H = hardSessionsFor(s.runs_per_week, s.difficulty, profile?.experience ?? null, s.goals);
  const every = cutbackEvery(profile);
  const longOk = s.runs_per_week >= 3 || (s.runs_per_week === 2 && focusDistanceMi(s.goals) >= 6);
  const monday0 = weekStart(s.start_date);
  const out: WeekInfo[] = [];
  let level = start;
  let peakReached = start;
  let total = Infinity;
  let taperW = 0, peakW = 0, baseW = 0;
  if (s.target_date) {
    total = Math.floor(dayDiff(monday0, weekStart(s.target_date)) / 7) + 1;
    taperW = Math.min(3, Math.max(1, Math.round(taperDays(focusDistanceMi(s.goals) || 3.1) / 7)));
    if (total <= taperW + 1) taperW = Math.max(0, total - 1);
    peakW = total - taperW >= 10 ? 2 : total - taperW >= 6 ? 1 : 0;
    baseW = Math.min(Math.max(1, total - taperW - peakW), Math.max(4, Math.floor((total - taperW - peakW) / 2)));
  }
  const n = Math.min(through, Number.isFinite(total) ? total : through);
  let sinceCutback = 0;
  let lastVol = start;
  for (let w = 0; w < n; w++) {
    const monday = addDays(monday0, 7 * w);
    let phase: Phase = "rolling";
    let cutback = false;
    let vol = level;
    let hard = H;
    let retest = false;
    if (Number.isFinite(total)) {
      const fromEnd = total - 1 - w; // 0 = race week
      if (fromEnd < taperW) {
        phase = fromEnd === 0 ? "race" : "taper";
        const fac = TAPER_FACTORS[taperW][taperW - 1 - fromEnd];
        vol = peakReached * fac;
      } else if (fromEnd < taperW + peakW) {
        phase = "peak";
        vol = level;
      } else {
        phase = w < baseW ? "base" : "build";
      }
    }
    if (phase !== "taper" && phase !== "race" && phase !== "peak") {
      if (sinceCutback === every - 1 && w > 0) {
        cutback = true;
        vol = lastVol * 0.75; // rule 2: −25% on the week before, keep one short quality session
        hard = Math.min(hard, 1);
        retest = !Number.isFinite(total) && w >= 6 && (w + 1) % 8 === 0 && focusOf(s.goals) !== "calories";
        sinceCutback = 0;
      } else {
        sinceCutback++;
      }
    }
    if (phase === "base") hard = Math.min(hard, 1);
    vol = Math.max(s.runs_per_week * MIN_RUN_MI, round1(vol));
    out.push({ index: w, monday, phase: cutback ? "cutback" : phase, cutback, volume_mi: vol, hard, long: longOk, retest });
    if (!cutback) lastVol = vol;
    if (!cutback && phase !== "taper" && phase !== "race") {
      peakReached = Math.max(peakReached, level);
      if (phase !== "peak") level = Math.min(peak, level + rampStep(level, s.difficulty));
    }
  }
  return out;
}

/** Run-day patterns (0 = Mon) by runs per week. */
const RUN_PATTERNS: Record<number, number[]> = {
  1: [5],
  2: [2, 5],
  3: [1, 3, 5],
  4: [0, 2, 3, 5],
  5: [0, 1, 3, 5, 6],
  6: [0, 1, 2, 3, 5, 6],
  7: [0, 1, 2, 3, 4, 5, 6],
};

export interface WeekLayout {
  /** weekday → kind; `flex` marks flexible-mode optional runs. */
  slots: { kind: DayKind | "easy"; flex: boolean }[];
}

/** Which weekdays are runs, walks, hard and long (rules 3, 11: never two hard days in a row). */
export function layoutWeek(
  s: Pick<PlanSettings, "runs_per_week" | "walk_mode" | "fixed_walk_days" | "goals">,
  week: Pick<WeekInfo, "hard" | "long" | "phase">,
): WeekLayout {
  let runDays: number[];
  let flexDays: number[] = [];
  if (s.walk_mode === "fixed") {
    const walk = new Set(s.fixed_walk_days);
    runDays = [0, 1, 2, 3, 4, 5, 6].filter((d) => !walk.has(d));
  } else {
    runDays = RUN_PATTERNS[clamp(s.runs_per_week, 1, 7)];
    if (s.walk_mode === "flexible") flexDays = [0, 1, 2, 3, 4, 5, 6].filter((d) => !runDays.includes(d));
  }
  const slots: WeekLayout["slots"] = Array.from({ length: 7 }, () => ({ kind: "walk" as DayKind, flex: false }));
  for (const d of runDays) slots[d] = { kind: "easy", flex: false };
  for (const d of flexDays) slots[d] = { kind: "easy", flex: true };
  // Long run: Saturday when it's a run day, else the last core run day.
  let longDay: number | null = null;
  if (week.long && runDays.length >= 2) {
    longDay = runDays.includes(5) ? 5 : runDays[runDays.length - 1];
    slots[longDay] = { kind: "long", flex: false };
  }
  const H = week.hard;
  if (H > 0) {
    const candidates = runDays.filter((d) => d !== longDay);
    const combos = combinations(candidates, Math.min(H, candidates.length));
    let best: number[] | null = null;
    let bestScore = -Infinity;
    for (const c of combos) {
      const set = new Set(c);
      // HARD: no two hard days in a row, Sunday→Monday included.
      if (c.some((d) => set.has((d + 1) % 7))) continue;
      let score = 0;
      for (const d of c) {
        if (longDay != null && Math.abs(d - longDay) === 1) score -= 3; // hard next to long: avoid
        if (flexDays.includes((d + 1) % 7) || slots[(d + 1) % 7].kind === "walk") score += 1; // recovery after
      }
      const gaps = c.map((d, i) => ((c[(i + 1) % c.length] - d + 7) % 7) || 7);
      score += Math.min(...gaps) * 0.5 - c[0] * 0.01;
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    const kinds = hardKindsFor(s.goals, best?.length ?? 0, week.phase);
    (best ?? []).forEach((d, i) => (slots[d] = { kind: kinds[i], flex: false }));
  }
  return { slots };
}

function combinations<T>(xs: T[], k: number): T[][] {
  if (k <= 0) return [[]];
  if (xs.length < k) return [];
  const out: T[][] = [];
  const rec = (i: number, acc: T[]) => {
    if (acc.length === k) return void out.push([...acc]);
    for (let j = i; j < xs.length; j++) rec(j + 1, [...acc, xs[j]]);
  };
  rec(0, []);
  return out;
}

/** Rule 1/23: pyramidal (threshold) in base/build, polarized (intervals) near the race. */
export function hardKindsFor(goals: Goal[], n: number, phase: Phase): DayKind[] {
  const focus = focusOf(goals);
  const shortFocus = focus === "mile" || focus === "5k" || focus === "calories";
  let order: DayKind[];
  if (phase === "base" || phase === "build") order = shortFocus ? ["tempo", "intervals", "tempo"] : ["tempo", "tempo", "intervals"];
  else if (phase === "peak" || phase === "taper" || phase === "race") order = ["intervals", "tempo", "intervals"];
  else order = shortFocus ? ["intervals", "tempo", "intervals"] : ["tempo", "intervals", "tempo"];
  if (phase === "build" && shortFocus) order = ["intervals", "tempo", "tempo"];
  return order.slice(0, n);
}

// ─── Spike guard (rule 6, HARD) ───────────────────────────────────────────

export interface RunHistoryItem {
  local_date: string;
  distance_mi: number;
}
export const SPIKE_FACTOR = 1.1;
export const SPIKE_FLOOR_MI = 1.1;
/**
 * The longest run allowed on `date`: 10% over the longest run of the 30 days
 * before it (actual runs, plus planned runs between today and `date`, which
 * the plan assumes done). Floor 1.1 mi so the streak mile is always allowed.
 */
export function spikeLimit(date: string, history: RunHistoryItem[]): number {
  const from = addDays(date, -30);
  let ref = 0;
  for (const h of history) if (h.local_date >= from && h.local_date < date) ref = Math.max(ref, h.distance_mi);
  return round2(Math.max(SPIKE_FLOOR_MI, ref * SPIKE_FACTOR));
}

// ─── Week generation ──────────────────────────────────────────────────────

export interface GenContext {
  settings: PlanSettings;
  profile: FitnessProfile | null;
  paces: Paces;
  hr: HrBands;
}

export function buildContextFor(g: Pick<GenContext, "settings" | "paces" | "hr">): BuildContext {
  const focus = focusOf(g.settings.goals);
  const race = g.settings.goals.find((x) => x.type === "distance_time" && x.distance === focus && x.target_s);
  const d = race ? goalDistanceMi(race) : null;
  return { paces: g.paces, hr: g.hr, focus, race_pace_s: race && d ? Math.round(race.target_s! / d) : null };
}

const TEMPO_MAX: Record<string, number> = { mile: 2, "5k": 3, "10k": 4, half: 6, marathon: 8, custom: 4, calories: 2 };

/**
 * Generate plan days for [from, to]. `history` = actual runs before `today`
 * (spike guard reference). Pure and deterministic.
 */
export function generateDays(
  g: GenContext,
  from: string,
  to: string,
  history: RunHistoryItem[],
): { local_date: string; day: Day }[] {
  const s = g.settings;
  const bctx = buildContextFor(g);
  const monday0 = weekStart(s.start_date);
  const lastW = Math.floor(dayDiff(monday0, weekStart(to)) / 7);
  const weeks = planWeeks(s, g.profile, g.paces, lastW + 1);
  const hist = [...history];
  const out: { local_date: string; day: Day }[] = [];
  const pf = s.pace_factor ?? 1;
  const raceGoal = s.goals.find((x) => x.type === "distance_time" && x.distance === bctx.focus);
  for (const wk of weeks) {
    const days = generateWeek(g, wk, bctx, hist, pf, raceGoal ?? null, from);
    for (const d of days) {
      if (d.local_date >= from && d.local_date <= to && d.local_date >= s.start_date) out.push(d);
    }
  }
  return out;
}

function generateWeek(
  g: GenContext,
  wk: WeekInfo,
  bctx: BuildContext,
  hist: RunHistoryItem[],
  pf: number,
  raceGoal: Goal | null,
  histFrom: string,
): { local_date: string; day: Day }[] {
  const s = g.settings;
  const lay = layoutWeek(s, wk);
  const V = wk.volume_mi;
  const focus = bctx.focus;
  const meta = (i: number) => ({ phase: wk.phase, week_index: wk.index, flex: lay.slots[i].flex });
  const specs: (DaySpec | null)[] = Array(7).fill(null);
  const wuMi = V >= 15 ? 1 : 0.75;
  const shortFocus = focus === "mile" || focus === "5k" || focus === "calories";
  // Hard sessions (rule 4 caps: threshold ≤ 10% of weekly volume, VO2 ≤ 8%).
  const tempoWork = clamp(round025(V * 0.1), 0.5, TEMPO_MAX[focus] ?? 3) * (wk.phase === "taper" || wk.phase === "race" ? 0.75 : 1);
  const repMi = focus === "mile" ? 0.25 : shortFocus ? 0.5 : 1;
  const vo2Work = Math.max(repMi * 3, V * 0.08);
  const reps = clamp(Math.floor(vo2Work / repMi + 1e-9), 3, focus === "mile" ? 12 : shortFocus ? 8 : 6) - (wk.phase === "taper" || wk.phase === "race" ? 1 : 0);
  const longCapMin = (LONG_MAX_S / easyMid(g.paces)) | 0;
  const longShare = focus === "mile" || focus === "5k" ? 0.25 : 0.3;
  let hardTotal = 0;
  for (let i = 0; i < 7; i++) {
    const k = lay.slots[i].kind;
    if (k === "tempo") {
      specs[i] = { kind: "tempo", work_mi: round025(tempoWork), distance_mi: round2(tempoWork + 2 * wuMi * 0.75) };
    } else if (k === "intervals") {
      specs[i] = { kind: "intervals", reps: Math.max(2, reps), rep_mi: repMi };
    }
    if (specs[i]) hardTotal += buildDay(specs[i]!, bctx).distance_mi;
  }
  const runSlots = lay.slots.map((x, i) => (x.kind !== "walk" ? i : -1)).filter((i) => i >= 0);
  const longIdx = lay.slots.findIndex((x) => x.kind === "long");
  const easyIdx = runSlots.filter((i) => lay.slots[i].kind === "easy");
  const flexIdx = easyIdx.filter((i) => lay.slots[i].flex);
  const coreEasy = easyIdx.filter((i) => !lay.slots[i].flex);
  let remaining = V - hardTotal - flexIdx.length * MIN_RUN_MI;
  let long = 0;
  if (longIdx >= 0) {
    long = Math.max(2, round05(Math.min(V * longShare, longCapMin)));
    long = Math.min(long, Math.max(MIN_RUN_MI, remaining - coreEasy.length * MIN_RUN_MI));
    remaining -= long;
  }
  const perEasy = coreEasy.length ? Math.max(MIN_RUN_MI, round05(remaining / coreEasy.length)) : 0;
  const strides = wk.hard === 0 && s.difficulty >= 2;
  for (const i of easyIdx) {
    const d = lay.slots[i].flex ? MIN_RUN_MI : longIdx >= 0 ? Math.min(perEasy, Math.max(MIN_RUN_MI, long - 0.5)) : perEasy;
    specs[i] = { kind: "easy", distance_mi: d, strides: strides && !lay.slots[i].flex && i === coreEasy[0] };
  }
  if (longIdx >= 0) specs[longIdx] = { kind: "long", distance_mi: long };
  // Calibration (rule 18) in the first week when history is thin.
  if (wk.index === 0 && g.profile?.calibration_needed) {
    const first = runSlots.find((i) => addDays(wk.monday, i) >= s.start_date);
    if (first != null) {
      const ck = g.profile.calibration_kind ?? "mile_tt_talk_test";
      specs[first] =
        ck === "lthr_30min"
          ? { kind: "calibration", distance_mi: round2((30 * 60) / g.paces.threshold_s), note: "30-minute test: run 30 minutes as hard as you can hold evenly." }
          : { kind: "calibration", distance_mi: ck === "3k" ? 1.86 : ck === "5k" ? 3.11 : 1 };
      const next = runSlots.find((i) => i > first && specs[i]?.kind === "easy");
      if (ck === "mile_tt_talk_test" && next != null)
        specs[next] = { kind: "easy", distance_mi: Math.min(2, specs[next]!.distance_mi ?? 2), note: "Talk-test run: easy enough to talk in full sentences. If speech gets unsure, slow down." };
    }
  }
  // Retest (rule 1: just improve retests every 6–8 weeks) in the cutback week.
  if (wk.retest) {
    const hi = lay.slots.findIndex((x) => isHard(x.kind));
    if (hi >= 0) specs[hi] = { kind: "race", distance_mi: focus === "mile" ? 1 : 3.11, note: "Retest: a hard, even effort. It updates your paces." };
  }
  // Race week: the race on target_date, shakeouts around it.
  if (wk.phase === "race" && s.target_date && raceGoal) {
    const ri = weekdayIndex(s.target_date);
    const dist = goalDistanceMi(raceGoal) ?? 3.11;
    for (let i = 0; i < 7; i++) {
      if (i === ri) specs[i] = { kind: "race", distance_mi: round2(dist) };
      else if (i > ri) specs[i] = { kind: "walk" };
      else if (i === ri - 1 && specs[i] && specs[i]!.kind !== "walk") specs[i] = { kind: "easy", distance_mi: Math.min(2, Math.max(1, specs[i]!.distance_mi ?? 1)), strides: true, note: "Shakeout: easy, a few strides, legs up after." };
      else if (i === ri - 2 && specs[i] && isHard(specs[i]!.kind)) specs[i] = { kind: "easy", distance_mi: specs[i]!.distance_mi ?? 2 };
    }
  }
  // Build + spike guard, in date order.
  const out: { local_date: string; day: Day }[] = [];
  for (let i = 0; i < 7; i++) {
    const date = addDays(wk.monday, i);
    let spec = specs[i] ?? { kind: "walk" as DayKind };
    if (pf !== 1 && spec.kind !== "walk" && spec.kind !== "race") spec = { ...spec, pace_factor: clamp(pf, 0.85, 1.15) };
    let day = buildDay(spec, bctx, meta(i));
    if (day.kind !== "walk" && day.kind !== "race") {
      const limit = spikeLimit(date, hist);
      if (day.distance_mi > limit) day = shrinkTo(day, limit, bctx);
    }
    if (wk.cutback && day.kind !== "walk" && !day.note?.startsWith("Retest")) day = { ...day, note: day.note ? `${day.note} Lighter week on purpose.` : "Lighter week on purpose." };
    out.push({ local_date: date, day });
    // Generated days before `from` are history the caller already supplied (actual runs).
    if (day.kind !== "walk" && date >= histFrom) hist.push({ local_date: date, distance_mi: day.distance_mi });
  }
  return out;
}

/** Fit a day under `limit` miles: easy/long shorten; hard sessions lose reps/work, then warm-up. */
export function shrinkTo(day: Day, limit: number, ctx: BuildContext): Day {
  const meta = { phase: day.phase, week_index: day.week_index, flex: day.flex };
  let spec = { ...day.spec };
  for (let guard = 0; guard < 40; guard++) {
    const d = buildDay(spec, ctx, meta);
    if (d.distance_mi <= limit + 1e-9) return { ...d, note: day.note };
    if (spec.kind === "easy" || spec.kind === "long") {
      // Strides add distance on top of the steady part: take the overage off the steady part.
      const next = Math.max(MIN_RUN_MI, Math.floor(((spec.distance_mi ?? d.distance_mi) - (d.distance_mi - limit)) * 4 - 1e-9) / 4);
      if (next === spec.distance_mi) spec = { ...spec, strides: false };
      else spec = { ...spec, distance_mi: next };
    }
    else if (spec.kind === "intervals" && (spec.reps ?? 0) > 2) spec = { ...spec, reps: (spec.reps ?? 3) - 1, distance_mi: null };
    else if (spec.kind === "tempo" && (spec.work_mi ?? 1) > 0.5) spec = { ...spec, work_mi: (spec.work_mi ?? 1) - 0.25, distance_mi: Math.max(1, (spec.distance_mi ?? 2) - 0.25) };
    else if (spec.kind === "calibration") return d;
    else return buildDay({ kind: "easy", distance_mi: Math.max(MIN_RUN_MI, Math.floor(limit * 4) / 4) }, ctx, meta);
  }
  return buildDay(spec, ctx, meta);
}

// ─── Validator: HARD rules + conventions ──────────────────────────────────

export interface Violation {
  rule: "spike_guard" | "no_back_to_back_hard";
  local_date: string;
  message: string;
  limit_mi?: number;
}
export interface Deviation {
  rule: string;
  local_date?: string;
  message: string;
}
export interface Checks {
  week_mi_before: number;
  week_mi_after: number;
  hard_rules_passed: string[];
  deviations: Deviation[];
  deviation_reason: string | null;
  text: string;
}
export interface ValidationContext {
  today: string;
  /** Current plan days (as the user sees them), by date. */
  days: Map<string, Day>;
  /** Actual runs (counted running workouts) before today. */
  actual: RunHistoryItem[];
}
export interface ProposedChange {
  local_date: string;
  after: Day;
}

const weekTotal = (days: Map<string, Day>, monday: string) =>
  round2(dateRange(monday, addDays(monday, 6)).reduce((a, d) => a + (days.get(d)?.distance_mi ?? 0), 0));

function historyFor(ctx: ValidationContext, days: Map<string, Day>): RunHistoryItem[] {
  const h = ctx.actual.filter((r) => r.local_date < ctx.today);
  for (const [d, day] of days) if (d >= ctx.today && day.kind !== "walk") h.push({ local_date: d, distance_mi: day.distance_mi });
  return h;
}

function violationsIn(ctx: ValidationContext, days: Map<string, Day>, dates: Iterable<string>): Violation[] {
  const hist = historyFor(ctx, days);
  const out: Violation[] = [];
  for (const date of dates) {
    const day = days.get(date);
    if (!day || day.kind === "walk") continue;
    if (day.kind !== "race") {
      const limit = spikeLimit(date, hist);
      if (day.distance_mi > limit + 1e-6)
        out.push({ rule: "spike_guard", local_date: date, limit_mi: limit, message: `${weekdayName(date)} ${fmtMi(day.distance_mi)} mi is more than 10% over the longest run of the past 30 days (limit ${fmtMi(limit)} mi).` });
    }
    if (day.is_hard) {
      const monday = weekStart(date);
      const hardInWeek = dateRange(monday, addDays(monday, 6)).filter((d) => days.get(d)?.is_hard).length;
      for (const nb of [addDays(date, -1), addDays(date, 1)]) {
        if (days.get(nb)?.is_hard && hardInWeek <= 3)
          out.push({ rule: "no_back_to_back_hard", local_date: date, message: `${weekdayName(date)} and ${weekdayName(nb)} would be hard days in a row.` });
      }
    }
  }
  return out;
}
const vkey = (v: Violation) => `${v.rule}|${v.local_date}`;

function deviationsIn(ctx: ValidationContext, after: Map<string, Day>, changes: ProposedChange[]): Deviation[] {
  const deviations: Deviation[] = [];
  const changed = changes.map((c) => c.local_date).sort();
  const weeks = [...new Set(changed.map(weekStart))];
  for (const monday of weeks) {
    const b = weekTotal(ctx.days, monday);
    const a = weekTotal(after, monday);
    const prevMonday = addDays(monday, -7);
    const prev = Math.max(
      weekTotal(ctx.days, prevMonday),
      round2(ctx.actual.filter((r) => r.local_date >= prevMonday && r.local_date < monday).reduce((x, r) => x + r.distance_mi, 0)),
    );
    if (a > b + 0.01 && prev > 0) {
      const allowed = prev + Math.max(Math.min(prev * 0.1, 2), prev < 10 ? 1 : 0);
      if (a > prev * 1.3 + 0.01) deviations.push({ rule: "ramp_30", local_date: monday, message: `Week goes ${fmtMi(prev)} → ${fmtMi(a)} mi, over +30%.` });
      else if (a > allowed + 0.5) deviations.push({ rule: "ramp", local_date: monday, message: `Week goes ${fmtMi(prev)} → ${fmtMi(a)} mi (rule: +10% or +2 mi).` });
    }
    const longs = dateRange(monday, addDays(monday, 6)).map((d) => after.get(d)).filter((d): d is Day => d?.kind === "long");
    for (const l of longs) if (a > 0 && l.distance_mi > 3 && l.distance_mi > a * 0.3 + 0.01) deviations.push({ rule: "long_run_share", local_date: monday, message: `Long run ${fmtMi(l.distance_mi)} mi is over 30% of the week.` });
    const wk = dateRange(monday, addDays(monday, 6)).map((d) => after.get(d));
    if (wk.some((d) => d?.phase === "taper" || d?.phase === "race") && a > b + 0.01) deviations.push({ rule: "taper", local_date: monday, message: "Adds volume during the taper." });
  }
  for (const c of changes) {
    const b = ctx.days.get(c.local_date);
    if (c.after.kind === "long" && c.after.est_duration_s > LONG_MAX_S) deviations.push({ rule: "long_run_minutes", local_date: c.local_date, message: "Long run over 150 minutes." });
    if (c.local_date === ctx.today && b && isRun(b.kind) && isRun(c.after.kind)) {
      const dd = b.distance_mi > 0 ? Math.abs(c.after.distance_mi / b.distance_mi - 1) : 0;
      const pfb = b.spec.pace_factor ?? 1, pfa = c.after.spec.pace_factor ?? 1;
      if (dd > 0.1 + 1e-9 || Math.abs(pfa / pfb - 1) > 0.1 + 1e-9 || (!b.is_hard && c.after.is_hard))
        deviations.push({ rule: "today_small_change", local_date: c.local_date, message: "Today's change is bigger than about ±10%." });
    }
    if (c.after.is_hard) {
      const monday = weekStart(c.local_date);
      const hardInWeek = dateRange(monday, addDays(monday, 6)).filter((d) => after.get(d)?.is_hard).length;
      if (hardInWeek > 3) deviations.push({ rule: "hard_cap", local_date: c.local_date, message: `${hardInWeek} hard sessions in one week (rule: cap 3).` });
      for (const nb of [addDays(c.local_date, -1), addDays(c.local_date, 1)]) if (after.get(nb)?.kind === "long") deviations.push({ rule: "hard_next_to_long", local_date: c.local_date, message: "Hard session next to the long run." });
    }
  }
  return deviations;
}

/**
 * Validate a change set against the plan as it stands. HARD violations
 * (spike guard, back-to-back hard days while ≤ 3 hard/week) block the
 * proposal. Convention deviations are allowed with a stated reason.
 */
export function validateChanges(
  ctx: ValidationContext,
  changes: ProposedChange[],
): { ok: boolean; violations: Violation[]; deviations: Deviation[]; checks: Omit<Checks, "deviation_reason"> } {
  const after = new Map(ctx.days);
  for (const c of changes) after.set(c.local_date, c.after);
  const changed = changes.map((c) => c.local_date).sort();
  const first = changed[0] ?? ctx.today;
  const windowDates = dateRange(addDays(first, -1), addDays(changed[changed.length - 1] ?? first, 31)).filter((d) => after.has(d));
  const before = new Set(violationsIn(ctx, ctx.days, windowDates).map(vkey));
  const own = new Set(changed);
  const neighbors = new Set(changed.flatMap((d) => [addDays(d, -1), addDays(d, 1)]));
  const violations = violationsIn(ctx, after, windowDates).filter((v) => own.has(v.local_date) || (!before.has(vkey(v)) && (neighbors.has(v.local_date) || v.rule === "spike_guard")));
  // Dedupe symmetric back-to-back reports.
  const seen = new Set<string>();
  const uniq = violations.filter((v) => (seen.has(vkey(v)) ? false : (seen.add(vkey(v)), true)));

  // Only deviations this change introduces (an existing long-run share etc. isn't the proposal's doing).
  const beforeDevs = new Set(deviationsIn(ctx, ctx.days, changes.map((c) => ({ local_date: c.local_date, after: ctx.days.get(c.local_date) ?? c.after }))).map((d) => `${d.rule}|${d.local_date}`));
  const deviations = deviationsIn(ctx, after, changes).filter((d) => !beforeDevs.has(`${d.rule}|${d.local_date}`));
  const mainWeek = weekStart(first);
  const wb = weekTotal(ctx.days, mainWeek);
  const wa = weekTotal(after, mainWeek);
  const passed = ["spike_guard", "no_back_to_back_hard"].filter((r) => !uniq.some((v) => v.rule === r));
  const text = `Checked: week goes ${fmtMi(wb)} → ${fmtMi(wa)} mi${passed.includes("spike_guard") ? ", no run over the spike limit" : ""}${passed.includes("no_back_to_back_hard") ? ", no two hard days in a row" : ""}.`;
  return { ok: uniq.length === 0, violations: uniq, deviations, checks: { week_mi_before: wb, week_mi_after: wa, hard_rules_passed: passed, deviations, text } };
}

// ─── Completion / status ──────────────────────────────────────────────────

export interface ActualRun {
  workout_id: string;
  local_date: string;
  workout_type: string;
  distance_mi: number;
  duration_s: number;
  moving_s: number | null;
  start_hour?: number | null;
  splits?: { distance_mi: number | null; duration_s: number; pace_s: number | null }[];
}
export type DayStatus = "planned" | "today" | "done" | "partial" | "missed" | "walk_done";
export const DONE_FRACTION = 0.8;
export const MISSED_FRACTION = 0.3;
export function dayStatus(day: Day, date: string, today: string, runs: ActualRun[], anyOnFoot: number): DayStatus {
  const miles = runs.reduce((a, r) => a + r.distance_mi, 0);
  if (day.kind === "walk") return anyOnFoot >= 0.95 ? "walk_done" : date < today ? "missed" : date === today ? "today" : "planned";
  if (miles >= day.distance_mi * DONE_FRACTION) return "done";
  if (date > today) return "planned";
  if (miles >= day.distance_mi * MISSED_FRACTION) return "partial";
  return date === today ? "today" : "missed";
}

// ─── Formula adaptations (every one is a PROPOSAL draft) ──────────────────

export interface ProposalDraft {
  kind: ProposalKind;
  title: string;
  reason: string;
  changes: ProposedChange[];
  goal_impact: { label: string; before_s: number; after_s: number } | null;
  deviation_reason: string | null;
  dedupe_key: string | null;
  plan_patch?: { pace_factor?: number } | null;
}

export interface AdaptContext extends ValidationContext {
  settings: PlanSettings;
  bctx: BuildContext;
  profile: FitnessProfile | null;
  /** Actual counted RUNNING workouts, last ~60 days. */
  runs: ActualRun[];
  /** Graded sessions, last 30 days. */
  grades: GradeRecord[];
  /** Dates (≥ today) already touched by a pending proposal. */
  pendingDates: Set<string>;
}

export interface GradeRecord {
  local_date: string;
  kind: DayKind;
  score: number;
  on_target: number;
  /** Avg work pace vs target (actual/target − 1; negative = faster). */
  pace_delta: number | null;
  /** Avg HR minus the band's high end (≤ 0 = at or under). */
  hr_delta: number | null;
}

const runsOn = (runs: ActualRun[], d: string) => runs.filter((r) => r.local_date === d);

/** Rule 11 placement test for moving a key session to `d`. */
function canHostKey(ctx: AdaptContext, d: string, days: Map<string, Day>): boolean {
  const cur = days.get(d);
  if (!cur || cur.is_key || cur.kind === "race") return false;
  if (cur.kind === "walk" && ctx.settings.walk_mode === "fixed") return false;
  if (days.get(addDays(d, -1))?.is_key || days.get(addDays(d, 1))?.is_key) return false;
  // ≥ 2 clear days before the next key session.
  for (let i = 1; i <= 2; i++) if (days.get(addDays(d, i))?.is_key) return false;
  return true;
}

/** Rules 10–12: missed runs. Easy → drop (no proposal). Key → move if rule 11 allows. Long → else hold next long. */
export function missedRunProposals(ctx: AdaptContext, lookbackDays = 3): ProposalDraft[] {
  const out: ProposalDraft[] = [];
  const end = addDays(ctx.today, 6 - weekdayIndex(ctx.today));
  for (let back = lookbackDays; back >= 1; back--) {
    const date = addDays(ctx.today, -back);
    const day = ctx.days.get(date);
    if (!day || !day.is_key || day.kind === "race") continue;
    const st = dayStatus(day, date, ctx.today, runsOn(ctx.runs, date), 0);
    if (st !== "missed") continue;
    // Move within the same week, from today on.
    let moved = false;
    if (weekStart(date) === weekStart(ctx.today)) {
      // From tomorrow: proposals for today stay small (spec §5).
      for (const d of dateRange(addDays(ctx.today, 1), end)) {
        if (ctx.pendingDates.has(d) || !canHostKey(ctx, d, ctx.days)) continue;
        const target = ctx.days.get(d)!;
        const after = rebuild({ ...day, phase: target.phase, week_index: target.week_index, flex: false }, {}, ctx.bctx);
        const v = validateChanges(ctx, [{ local_date: d, after }]);
        if (!v.ok) continue;
        out.push({
          kind: "missed_run",
          title: `Move ${day.title} to ${weekdayName(d)}`,
          reason: `You missed ${weekdayName(date)}'s ${day.kind === "long" ? "long run" : "key session"}. ${weekdayName(d)} has easy days around it, so it fits there.`,
          changes: [{ local_date: d, after }],
          goal_impact: null,
          deviation_reason: v.deviations.length ? `Moving a missed ${day.kind} session.` : null,
          dedupe_key: `missed:${date}`,
        });
        moved = true;
        break;
      }
    }
    if (!moved && day.kind === "long") {
      // Rule 12: drop it; the next long run stays at the missed one's length.
      const next = dateRange(addDays(ctx.today, 0), addDays(ctx.today, 13)).find((d) => ctx.days.get(d)?.kind === "long");
      const nl = next ? ctx.days.get(next)! : null;
      if (next && nl && nl.distance_mi > day.distance_mi + 0.01 && !ctx.pendingDates.has(next)) {
        const after = rebuild(nl, { distance_mi: day.distance_mi }, ctx.bctx);
        out.push({
          kind: "missed_run",
          title: `Keep ${weekdayName(next)}'s long run at ${fmtMi(day.distance_mi)} mi`,
          reason: `${weekdayName(date)}'s long run was missed, so the next one holds its length instead of growing.`,
          changes: [{ local_date: next, after }],
          goal_impact: null,
          deviation_reason: null,
          dedupe_key: `missed:${date}`,
        });
      }
    }
  }
  return out;
}

/** Rule 13: time off. ≤ 5 d resume · 6–28 d: week 1 at 50% easy, week 2 at 75% · > 4 wk: 33% then rebuild. */
export function returnFromBreakProposal(ctx: AdaptContext): ProposalDraft | null {
  const last = ctx.runs.filter((r) => r.local_date < ctx.today).map((r) => r.local_date).sort().pop();
  const gap = last ? dayDiff(last, ctx.today) - 1 : null;
  if (gap == null || gap <= 5) return null;
  const red = gap <= 28 ? 0.01 + ((gap - 6) / 22) * 0.06 : Math.min(0.2, 0.07 + ((gap - 28) / 7) * 0.015);
  const factor = round2(1 / (1 - red));
  const weekFactors = gap <= 28 ? [0.5, 0.75] : [0.33, 0.5];
  const changes: ProposedChange[] = [];
  for (let w = 0; w < 2; w++) {
    for (let i = 0; i < 7; i++) {
      const d = addDays(ctx.today, w * 7 + i);
      const day = ctx.days.get(d);
      if (!day || day.kind === "walk" || day.kind === "race" || ctx.pendingDates.has(d)) continue;
      const easyOnly = w === 0 || gap > 28;
      const spec: Partial<DaySpec> = easyOnly && day.is_hard
        ? { kind: "easy", distance_mi: Math.max(MIN_RUN_MI, round05(day.distance_mi * weekFactors[w])), reps: null, work_mi: null, rep_mi: null, strides: false }
        : day.kind === "easy" || day.kind === "long"
          ? { distance_mi: Math.max(MIN_RUN_MI, round05(day.distance_mi * weekFactors[w])) }
          : { distance_mi: null, reps: day.spec.reps ? Math.max(2, Math.round(day.spec.reps * weekFactors[w])) : null, work_mi: day.spec.work_mi ? Math.max(0.5, round025(day.spec.work_mi * weekFactors[w])) : null };
      const after = rebuild(day, { ...spec, pace_factor: clamp((day.spec.pace_factor ?? 1) * factor, 0.85, 1.15) }, ctx.bctx);
      changes.push({ local_date: d, after: { ...after, phase: "return" } });
    }
  }
  if (!changes.length) return null;
  return {
    kind: "return_from_break",
    title: gap <= 28 ? "Ease back in: two lighter weeks" : "Restart gently after the break",
    reason: `${gap} days since your last run. Easy running first${gap <= 28 ? " (50%, then 75%)" : " at about a third of the volume"}, paces ${Math.round(red * 100)}% gentler, then we rebuild.`,
    changes,
    goal_impact: null,
    deviation_reason: "Return-to-run after time off (research rule 13).",
    dedupe_key: `return:${last}`,
  };
}

/** Rule 20: pace up after 3+ sessions 3–5% fast at the same or lower HR; down after 2+ sessions > 5% slow. */
export function paceUpdateProposal(ctx: AdaptContext, horizonDays = 14): ProposalDraft | null {
  const hard = ctx.grades.filter((g) => isHard(g.kind) && g.pace_delta != null && g.local_date < ctx.today).sort((a, b) => a.local_date.localeCompare(b.local_date));
  const last3 = hard.slice(-3);
  const last2 = hard.slice(-2);
  let step = 0;
  let reason = "";
  if (last3.length === 3 && last3.every((g) => g.pace_delta! <= -0.03 && (g.hr_delta == null || g.hr_delta <= 0))) {
    const m = median(last3.map((g) => -g.pace_delta!))!;
    step = -clamp(m, 0.03, 0.05);
    reason = `You beat your target pace ${last3.length} hard runs in a row${last3.some((g) => g.hr_delta != null) ? " at the same heart rate" : ""}.`;
  } else if (last2.length === 2 && last2.every((g) => g.pace_delta! > 0.05)) {
    const m = median(last2.map((g) => g.pace_delta!))!;
    step = clamp(m, 0.03, 0.05);
    reason = "The last two hard runs came in more than 5% slower than planned. Easing the paces so you can hit them.";
  }
  if (!step) return null;
  const changes: ProposedChange[] = [];
  for (const d of dateRange(ctx.today, addDays(ctx.today, horizonDays))) {
    const day = ctx.days.get(d);
    if (!day || day.kind === "walk" || day.kind === "race" || ctx.pendingDates.has(d)) continue;
    const pf = clamp(round2((day.spec.pace_factor ?? 1) * (1 + step)), 0.85, 1.15);
    changes.push({ local_date: d, after: rebuild(day, { pace_factor: pf }, ctx.bctx) });
  }
  if (!changes.length) return null;
  const est = estimateFor(ctx.bctx.paces.vdot, 3.10686);
  const est2 = Math.round(est * (1 + step));
  return {
    kind: "pace_update",
    title: step < 0 ? "Faster paces" : "Gentler paces",
    reason,
    changes,
    goal_impact: { label: "5K estimate", before_s: est, after_s: est2 },
    deviation_reason: null,
    dedupe_key: `pace:${hard[hard.length - 1].local_date}`,
    plan_patch: { pace_factor: round2((ctx.settings.pace_factor ?? 1) * (1 + step)) },
  };
}

export function estimateFor(vdot: number, distanceMi: number): number {
  return raceTimeFor(vdot, distanceMi);
}

export interface FatigueSignals {
  hard_efforts_last_6d: number;
  resting_hr_delta: number | null;
  resting_hr_up_3d: boolean;
  hrv_below_baseline: boolean;
  acwr: number | null;
  fatigue_flag: boolean;
}

/** Rule 21 + spec §2.4 "overdoing it". ACWR (rule 8) is reported, never the sole gate. */
export function fatigueSignals(ctx: Pick<AdaptContext, "today" | "days" | "runs" | "profile" | "bctx">): FatigueSignals {
  let hard = 0;
  for (let i = 1; i <= 6; i++) {
    const d = addDays(ctx.today, -i);
    const day = ctx.days.get(d);
    const rs = runsOn(ctx.runs, d);
    if (!rs.length) continue;
    if (day?.is_hard) hard++;
    else {
      const t = rs.reduce((a, r) => a + (r.moving_s ?? r.duration_s), 0);
      const mi = rs.reduce((a, r) => a + r.distance_mi, 0);
      if (mi > 0 && t / mi < ctx.bctx.paces.threshold_s * 1.02) hard++;
    }
  }
  const p = ctx.profile;
  const rhr = (p?.resting_hr_7d ?? []).filter((x): x is number => x != null);
  const base = p?.resting_hr ?? null;
  const last3 = rhr.slice(-3);
  const up3 = base != null && last3.length === 3 && last3.every((x) => x >= base + 5);
  const hrv = (p?.hrv_7d_ms ?? []).filter((x): x is number => x != null);
  const hrvLow = hrv.length >= 3 && p?.hrv_baseline_ms != null && hrv.reduce((a, b) => a + b, 0) / hrv.length < p.hrv_baseline_ms * 0.93;
  const acute = ctx.runs.filter((r) => dayDiff(r.local_date, ctx.today) >= 1 && dayDiff(r.local_date, ctx.today) <= 7).reduce((a, r) => a + r.distance_mi, 0);
  const chronic = ctx.runs.filter((r) => dayDiff(r.local_date, ctx.today) >= 1 && dayDiff(r.local_date, ctx.today) <= 28).reduce((a, r) => a + r.distance_mi, 0) / 4;
  const acwr = chronic > 0 ? round2(acute / chronic) : null;
  return {
    hard_efforts_last_6d: hard,
    resting_hr_delta: base != null && rhr.length ? Math.round(rhr[rhr.length - 1] - base) : null,
    resting_hr_up_3d: up3,
    hrv_below_baseline: hrvLow,
    acwr,
    fatigue_flag: up3 || hrvLow,
  };
}

/** Flexible walk days: "you've earned one" (today) and "you're overdoing it" (tomorrow). Fatigue elsewhere: next hard → easy. */
export function walkDayProposals(ctx: AdaptContext): ProposalDraft[] {
  const out: ProposalDraft[] = [];
  const sig = fatigueSignals(ctx);
  const flexible = ctx.settings.walk_mode === "flexible";
  const overdoing = sig.hard_efforts_last_6d >= 4 || sig.fatigue_flag;
  if (overdoing) {
    const why =
      sig.hard_efforts_last_6d >= 4
        ? `${sig.hard_efforts_last_6d} hard efforts in 6 days${sig.resting_hr_up_3d && sig.resting_hr_delta ? `, and your resting heart rate is up ${sig.resting_hr_delta} bpm` : ""}.`
        : sig.resting_hr_up_3d
          ? `Your resting heart rate has been up ${sig.resting_hr_delta ?? 5}+ bpm for 3 days.`
          : "Your heart-rate variability is below your usual for the week.";
    if (flexible) {
      const tm = addDays(ctx.today, 1);
      const day = ctx.days.get(tm);
      if (day && day.kind !== "walk" && day.kind !== "race" && !ctx.pendingDates.has(tm))
        out.push({ kind: "walk_day_needed", title: "Walk day tomorrow?", reason: `${why} A walk day lets it settle.`, changes: [{ local_date: tm, after: buildDay({ kind: "walk" }, ctx.bctx, { phase: day.phase, week_index: day.week_index }) }], goal_impact: null, deviation_reason: null, dedupe_key: `needed:${tm}` });
    } else {
      const next = dateRange(ctx.today, addDays(ctx.today, 6)).find((d) => ctx.days.get(d)?.is_hard && ctx.days.get(d)?.kind !== "race");
      if (next && !ctx.pendingDates.has(next)) {
        const day = ctx.days.get(next)!;
        const after = rebuild(day, { kind: "easy", distance_mi: Math.max(MIN_RUN_MI, round05(day.distance_mi)), reps: null, rep_mi: null, work_mi: null }, ctx.bctx);
        out.push({ kind: "adjust", title: `Easy run instead of ${day.title}`, reason: `${why} Your next hard session becomes easy.`, changes: [{ local_date: next, after }], goal_impact: null, deviation_reason: next === ctx.today ? "Fatigue signals (research rule 21)." : null, dedupe_key: `fatigue:${next}` });
      }
    }
  }
  if (flexible && !overdoing) {
    const today = ctx.days.get(ctx.today);
    const monday = weekStart(ctx.today);
    const past = dateRange(monday, addDays(ctx.today, -1));
    const doneCore = past.filter((d) => {
      const day = ctx.days.get(d);
      return day && day.kind !== "walk" && !day.flex && dayStatus(day, d, ctx.today, runsOn(ctx.runs, d), 0) === "done";
    });
    const plannedCore = past.filter((d) => ctx.days.get(d) && ctx.days.get(d)!.kind !== "walk" && !ctx.days.get(d)!.flex);
    const gradesOk = doneCore.every((d) => (ctx.grades.find((g) => g.local_date === d)?.score ?? 100) >= 70);
    const walksTaken = past.filter((d) => ctx.days.get(d)?.kind === "walk").length;
    const walksAllowed = 7 - ctx.settings.runs_per_week;
    if (today && today.flex && today.kind === "easy" && doneCore.length >= 2 && doneCore.length === plannedCore.length && gradesOk && walksTaken < walksAllowed && !ctx.pendingDates.has(ctx.today) && !runsOn(ctx.runs, ctx.today).length)
      out.push({ kind: "walk_day_earned", title: "You've earned a walk day", reason: `${doneCore.length} runs this week and you hit every target. Take today easy: a walk counts.`, changes: [{ local_date: ctx.today, after: buildDay({ kind: "walk" }, ctx.bctx, { phase: today.phase, week_index: today.week_index, flex: true }) }], goal_impact: null, deviation_reason: null, dedupe_key: `earned:${ctx.today}` });
  }
  return out;
}

export interface CheckinInput {
  local_date: string;
  time_available_min?: number | null;
  energy?: number | null;
  soreness?: number | null;
  go_further_mi?: number | null;
  text?: string | null;
}

/** Spec §7: check-in → fixed tweaks (formula tier). */
export function checkinProposal(ctx: AdaptContext, c: CheckinInput, lowEnergyStreak: number): ProposalDraft | null {
  const day = ctx.days.get(c.local_date);
  if (!day || day.kind === "walk" || day.kind === "race") return null;
  const tired = (c.energy != null && c.energy <= 3) || (c.soreness != null && c.soreness >= 7);
  if (tired && lowEnergyStreak >= 3) {
    const changes: ProposedChange[] = [];
    for (const d of dateRange(c.local_date, addDays(c.local_date, 2))) {
      const x = ctx.days.get(d);
      if (!x || x.kind === "walk" || x.kind === "race") continue;
      changes.push({ local_date: d, after: rebuild(x, { kind: x.is_hard ? "easy" : x.kind, distance_mi: Math.max(MIN_RUN_MI, round05(x.distance_mi * 0.8)), reps: null, work_mi: null, rep_mi: null }, ctx.bctx) });
    }
    return { kind: "checkin", title: "A lighter few days", reason: `Low energy ${lowEnergyStreak} days running. Easier for the next few days, then a gentle return.`, changes, goal_impact: null, deviation_reason: "Several low-energy check-ins in a row.", dedupe_key: null };
  }
  if (tired) {
    const after = day.is_hard
      ? rebuild(day, { kind: "easy", distance_mi: Math.max(MIN_RUN_MI, round05(day.distance_mi * 0.9)), reps: null, work_mi: null, rep_mi: null }, ctx.bctx)
      : rebuild(day, { distance_mi: Math.max(MIN_RUN_MI, round2(day.distance_mi * 0.9)) }, ctx.bctx);
    return { kind: "checkin", title: day.is_hard ? `Easy ${fmtMi(after.distance_mi)} mi instead of ${day.title}` : `${after.title} instead of ${fmtMi(day.distance_mi)} mi`, reason: c.soreness != null && c.soreness >= 7 ? "You're sore today. Keep it easy and let it recover." : "Low energy today. An easier run still counts.", changes: [{ local_date: c.local_date, after }], goal_impact: null, deviation_reason: day.is_hard ? "Check-in: tired or sore." : null, dedupe_key: null };
  }
  if (c.time_available_min != null && day.est_duration_s > c.time_available_min * 60 + 60) {
    const ratio = (c.time_available_min * 60) / day.est_duration_s;
    let after: Day;
    if (day.kind === "easy" || day.kind === "long") after = rebuild(day, { distance_mi: Math.max(MIN_RUN_MI, Math.floor(day.distance_mi * ratio * 4) / 4) }, ctx.bctx);
    else if (day.kind === "intervals") after = rebuild(day, { reps: Math.max(2, Math.floor((day.spec.reps ?? 4) * ratio)), distance_mi: null }, ctx.bctx);
    else after = rebuild(day, { work_mi: Math.max(0.5, round025((day.spec.work_mi ?? 1) * ratio)), distance_mi: Math.max(1, Math.floor(day.distance_mi * ratio * 4) / 4) }, ctx.bctx);
    return { kind: "checkin", title: `${after.title} to fit ${c.time_available_min} min`, reason: `You have about ${c.time_available_min} minutes, so it's shorter today.`, changes: [{ local_date: c.local_date, after }], goal_impact: null, deviation_reason: `Only ${c.time_available_min} minutes available.`, dedupe_key: null };
  }
  if (c.go_further_mi != null && c.go_further_mi > day.distance_mi + 0.2) {
    const hist = historyFor(ctx, ctx.days);
    const limit = spikeLimit(c.local_date, hist);
    const target = Math.min(c.go_further_mi, limit, day.distance_mi * 2);
    if (target <= day.distance_mi + 0.2) return null;
    const after = day.kind === "easy" || day.kind === "long" ? rebuild(day, { distance_mi: round2(Math.floor(target * 4) / 4) }, ctx.bctx) : rebuild(day, { distance_mi: round2(Math.floor(target * 4) / 4) }, ctx.bctx);
    const capped = target < c.go_further_mi;
    return { kind: "checkin", title: `Make it ${fmtMi(after.distance_mi)} mi, keep the extra easy?`, reason: `You've got time and energy.${capped ? ` ${fmtMi(after.distance_mi)} mi is as far as the spike rule allows today.` : ""}`, changes: [{ local_date: c.local_date, after }], goal_impact: null, deviation_reason: "You asked to go further.", dedupe_key: null };
  }
  return null;
}

// ─── Grade (rule 24) ──────────────────────────────────────────────────────

export interface GradeInputs {
  actual_distance_mi: number;
  segments?: { index: number; scored_s: number; in_band_s: number; too_fast_s?: number; too_slow_s?: number; avg_pace_s?: number | null; avg_hr?: number | null }[];
  rep_paces_s?: number[];
  easy_hr_drift_pct?: number | null;
  avg_hr?: number | null;
  /** Server fallback: average pace of the run(s). */
  avg_pace_s?: number | null;
  split_paces_s?: number[];
}
export interface Grade {
  score: number;
  completion: number;
  on_target: number;
  consistency: number;
  pace_delta: number | null;
  hr_delta: number | null;
}

export function completionScore(planned: number, actual: number): number {
  if (!(planned > 0)) return 100;
  const dev = Math.abs(actual / planned - 1);
  if (dev <= 0.2) return 100;
  if (dev >= 0.5) return 0;
  return Math.round(((0.5 - dev) / 0.3) * 100);
}
/** CV of rep paces: ≤ 3% full, > 6% zero. */
export function repConsistency(paces: number[]): number | null {
  if (paces.length < 2) return null;
  const m = paces.reduce((a, b) => a + b, 0) / paces.length;
  const sd = Math.sqrt(paces.reduce((a, b) => a + (b - m) ** 2, 0) / paces.length);
  const cv = sd / m;
  if (cv <= 0.03) return 100;
  if (cv > 0.06) return 0;
  return Math.round(((0.06 - cv) / 0.03) * 100);
}
/** Easy HR drift < 5% full credit → 0 at 10%. */
export function driftConsistency(pct: number): number {
  if (pct < 5) return 100;
  if (pct >= 10) return 0;
  return Math.round(((10 - pct) / 5) * 100);
}

/** 40% completion, 40% time in band (rule 16 exclusions already applied by the phone), 20% consistency. */
export function gradeSession(day: Day, i: GradeInputs): Grade {
  const completion = completionScore(day.distance_mi, i.actual_distance_mi);
  let onTarget: number;
  let paceDelta: number | null = null;
  let hrDelta: number | null = null;
  const work = day.segments.filter((s) => s.kind === "work" || s.kind === "steady");
  const workTarget = work.find((s) => s.target_pace_s)?.target_pace_s ?? null;
  if (i.segments && i.segments.length) {
    const scored = i.segments.reduce((a, s) => a + Math.max(0, s.scored_s), 0);
    const inBand = i.segments.reduce((a, s) => a + Math.max(0, Math.min(s.in_band_s, s.scored_s)), 0);
    onTarget = scored > 0 ? Math.round((inBand / scored) * 100) : 100;
    const workSegs = i.segments.filter((s) => {
      const seg = day.segments[s.index];
      return seg && (seg.kind === "work" || (seg.kind === "steady" && !day.is_hard)) && s.avg_pace_s && seg.target_pace_s;
    });
    if (workSegs.length) {
      const deltas = workSegs.map((s) => s.avg_pace_s! / day.segments[s.index].target_pace_s! - 1);
      paceDelta = round2(deltas.reduce((a, b) => a + b, 0) / deltas.length * 1000) / 1000;
      const hrs = workSegs.filter((s) => s.avg_hr != null && day.segments[s.index].hr_high != null).map((s) => s.avg_hr! - day.segments[s.index].hr_high!);
      hrDelta = hrs.length ? Math.round(hrs.reduce((a, b) => a + b, 0) / hrs.length) : null;
    }
  } else if (i.avg_pace_s && workTarget) {
    // Server fallback: average pace vs the day's band, linear to 0 at 10% outside.
    const seg = work[0];
    const lo = seg.pace_low_s ?? workTarget, hi = seg.pace_high_s ?? workTarget;
    const p = i.avg_pace_s;
    const out = p < lo ? (lo - p) / lo : p > hi ? (p - hi) / hi : 0;
    // Hard days: average includes warm-ups, so judge only "not slower than easy".
    onTarget = day.is_hard ? (p <= day.segments[0].pace_high_s! * 1.05 ? 80 : 50) : Math.round(clamp(1 - out / 0.1, 0, 1) * 100);
    if (!day.is_hard) paceDelta = Math.round((p / workTarget - 1) * 1000) / 1000;
  } else onTarget = 100;
  let consistency = 100;
  if (day.kind === "intervals" && i.rep_paces_s?.length) consistency = repConsistency(i.rep_paces_s) ?? 100;
  else if (i.easy_hr_drift_pct != null) consistency = driftConsistency(i.easy_hr_drift_pct);
  else if (i.split_paces_s && i.split_paces_s.length >= 2 && !day.is_hard) consistency = repConsistency(i.split_paces_s) ?? 100;
  const score = Math.round(0.4 * completion + 0.4 * onTarget + 0.2 * consistency);
  return { score, completion, on_target: onTarget, consistency, pace_delta: paceDelta, hr_delta: hrDelta };
}

export function gradeSummaryTemplate(day: Day, g: Grade): string {
  const parts: string[] = [];
  parts.push(g.completion >= 100 ? "Full distance done." : g.completion >= 50 ? "Most of the distance done." : "A short one today.");
  if (g.on_target >= 85) parts.push(day.is_hard ? "Right on target pace." : "Easy stayed easy.");
  else if (g.pace_delta != null && g.pace_delta < -0.03 && !day.is_hard) parts.push("A bit fast for an easy day; slower easy runs make the hard ones better.");
  else if (g.on_target < 60) parts.push("Off the target band for a good part of it.");
  if (day.kind === "intervals" && g.consistency >= 85) parts.push("Reps were even.");
  return parts.join(" ");
}

// ─── Notification timing (spec §6) ────────────────────────────────────────

/** Typical run hour before 9 → 8 PM local the evening before; else 9 AM local on the day. */
export function notificationLocalTime(typicalRunHour: number | null, firstDate: string): { local_date: string; hour: number } {
  if (typicalRunHour != null && typicalRunHour < 9) return { local_date: addDays(firstDate, -1), hour: 20 };
  return { local_date: firstDate, hour: 9 };
}
/** UTC instant of a local date + hour given the user's UTC offset in minutes (local = UTC + offset). */
export function localToUtc(localDate: string, hour: number, offsetMinutes: number): Date {
  return new Date(toMs(localDate) + hour * 3_600_000 - offsetMinutes * 60_000);
}
export function notificationDueAt(typicalRunHour: number | null, firstDate: string, offsetMinutes: number): Date {
  const t = notificationLocalTime(typicalRunHour, firstDate);
  return localToUtc(t.local_date, t.hour, offsetMinutes);
}

// ─── Checkpoints for big jumps (goals screen) ────────────────────────────

export interface Checkpoint {
  label: string;
  goal_index: number;
  target_s: number;
  eta_week: number | null;
}
export function checkpointsFor(goals: Goal[], vdot: number, difficulty: Difficulty): Checkpoint[] {
  const out: Checkpoint[] = [];
  const gain = 0.002 + 0.001 * difficulty; // fraction of race time per week
  goals.forEach((g, gi) => {
    if (g.type !== "distance_time" || !g.target_s) return;
    const d = goalDistanceMi(g)!;
    const now = estimateFor(vdot, d);
    if (g.target_s >= now * 0.92) {
      out.push({ label: `${DISTANCE_LABEL[g.distance!]} in ${formatDuration(g.target_s)}`, goal_index: gi, target_s: g.target_s, eta_week: Math.ceil(Math.log(g.target_s / now) / Math.log(1 - gain)) });
      return;
    }
    let t = now;
    for (let k = 0; k < 6 && t > g.target_s; k++) {
      t = Math.max(g.target_s, Math.floor((t * 0.92) / 60) * 60);
      const label = t === g.target_s ? `${DISTANCE_LABEL[g.distance!]} in ${formatDuration(t)}` : `sub-${formatDuration(t + (t % 60 === 0 ? 0 : 0)).replace(/:00$/, "")} ${DISTANCE_LABEL[g.distance!]}`;
      out.push({ label, goal_index: gi, target_s: t, eta_week: Math.ceil(Math.log(t / now) / Math.log(1 - gain)) });
    }
  });
  return out;
}

// ─── Coach "options" (the tool the model picks from) ──────────────────────

export type OptionIntent = "easier" | "shorter" | "longer" | "harder" | "swap_walk" | "move_key" | "fit_time";
export function optionsFor(
  ctx: AdaptContext,
  date: string,
  intent: OptionIntent,
  extra: { minutes?: number; to_date?: string } = {},
): { label: string; changes: ProposedChange[] }[] {
  const day = ctx.days.get(date);
  if (!day) return [];
  const cands: { label: string; changes: ProposedChange[] }[] = [];
  const add = (label: string, changes: ProposedChange[]) => cands.push({ label, changes });
  const r = (patch: Partial<DaySpec>) => rebuild(day, patch, ctx.bctx);
  switch (intent) {
    case "easier":
      if (day.is_hard) {
        add(`Easy ${fmtMi(round05(day.distance_mi))} mi`, [{ local_date: date, after: r({ kind: "easy", distance_mi: Math.max(1, round05(day.distance_mi)), reps: null, work_mi: null, rep_mi: null }) }]);
        if (day.kind === "intervals" && (day.spec.reps ?? 0) > 3) add(`${(day.spec.reps ?? 4) - 2} reps instead of ${day.spec.reps}`, [{ local_date: date, after: r({ reps: (day.spec.reps ?? 4) - 2, distance_mi: null }) }]);
        if (day.kind === "tempo") add("Shorter tempo", [{ local_date: date, after: r({ work_mi: Math.max(0.5, round025((day.spec.work_mi ?? 1) * 0.75)) }) }]);
      }
      for (const f of [1.03, 1.05]) if (day.kind !== "walk") add(`Same run, ${Math.round((f - 1) * 100)}% gentler paces`, [{ local_date: date, after: r({ pace_factor: clamp((day.spec.pace_factor ?? 1) * f, 0.85, 1.15) }) }]);
      break;
    case "shorter":
      for (const f of [0.9, 0.75, 0.5]) if (day.kind === "easy" || day.kind === "long") add(`${fmtMi(Math.max(1, round05(day.distance_mi * f)))} mi`, [{ local_date: date, after: r({ distance_mi: Math.max(1, round05(day.distance_mi * f)) }) }]);
      if (day.kind === "intervals") add("Fewer reps", [{ local_date: date, after: r({ reps: Math.max(2, (day.spec.reps ?? 4) - 2), distance_mi: null }) }]);
      if (day.kind === "tempo") add("Shorter tempo", [{ local_date: date, after: r({ work_mi: Math.max(0.5, round025((day.spec.work_mi ?? 1) * 0.66)), distance_mi: Math.max(1, round05(day.distance_mi * 0.75)) }) }]);
      break;
    case "longer": {
      const limit = spikeLimit(date, historyFor(ctx, ctx.days));
      for (const f of [1.1, 1.2, 1.5]) {
        const d = Math.min(limit, round05(day.distance_mi * f));
        if (d > day.distance_mi && (day.kind === "easy" || day.kind === "long")) add(`${fmtMi(d)} mi`, [{ local_date: date, after: r({ distance_mi: d }) }]);
      }
      break;
    }
    case "harder":
      for (const f of [0.98, 0.97]) if (day.kind !== "walk") add(`${Math.round((1 - f) * 100)}% faster paces`, [{ local_date: date, after: r({ pace_factor: clamp((day.spec.pace_factor ?? 1) * f, 0.85, 1.15) }) }]);
      if (day.kind === "intervals") add("One more rep", [{ local_date: date, after: r({ reps: (day.spec.reps ?? 4) + 1, distance_mi: null }) }]);
      if (day.kind === "easy") add("Add strides", [{ local_date: date, after: r({ strides: true }) }]);
      break;
    case "swap_walk":
      if (day.kind !== "walk" && day.kind !== "race") add("Walk day", [{ local_date: date, after: buildDay({ kind: "walk" }, ctx.bctx, { phase: day.phase, week_index: day.week_index, flex: day.flex }) }]);
      for (let i = 1; i <= 3; i++) {
        const d2 = addDays(date, i);
        const other = ctx.days.get(d2);
        if (day.kind !== "walk" && other?.kind === "walk" && ctx.settings.walk_mode !== "fixed")
          add(`Walk today, run ${weekdayName(d2)}`, [
            { local_date: date, after: buildDay({ kind: "walk" }, ctx.bctx, { phase: day.phase, week_index: day.week_index }) },
            { local_date: d2, after: buildDay(day.spec, ctx.bctx, { phase: other.phase, week_index: other.week_index }) },
          ]);
      }
      break;
    case "move_key": {
      const targets = extra.to_date ? [extra.to_date] : dateRange(addDays(date, 1), addDays(date, 6));
      for (const d2 of targets) {
        const other = ctx.days.get(d2);
        if (!day.is_key || !other || other.is_key || d2 < ctx.today) continue;
        add(`Move to ${weekdayName(d2)}`, [
          { local_date: date, after: buildDay(other.kind === "walk" ? { kind: "walk" } : { kind: "easy", distance_mi: Math.max(1, other.distance_mi) }, ctx.bctx, { phase: day.phase, week_index: day.week_index }) },
          { local_date: d2, after: buildDay(day.spec, ctx.bctx, { phase: other.phase, week_index: other.week_index }) },
        ]);
      }
      break;
    }
    case "fit_time": {
      const m = extra.minutes ?? 30;
      const p = checkinProposal(ctx, { local_date: date, time_available_min: m }, 0);
      if (p) add(p.title, p.changes);
      break;
    }
  }
  return cands.filter((c) => validateChanges(ctx, c.changes).ok);
}

// ─── Rules text for the coach model (cached prefix) ──────────────────────

export const COACH_RULES_TEXT = `Mile A Day Run Plans: training rules (research-backed; S strong, M moderate, C convention).
HARD rules (code rejects any proposal that breaks them):
- Spike guard (M-S): no run more than 10% longer than the longest run of the past 30 days (planned runs before it count as done). Race day is exempt.
- No two hard days in a row (tempo, intervals, race, calibration) while the week has 3 or fewer hard sessions.
Conventions (you may deviate with a stated reason):
1 Phases: base (>=4 wk) -> build -> peak (2-3 wk) -> taper. Pyramidal (more threshold) in build, polarized near the race. No date or "just improve": rolling 3-up/1-down, retest every 6-8 weeks.
2 Cutback every 4th week (3rd for age 50+, injury history, first 12 weeks of running): volume -25%, keep one short quality session.
3 >=80% of running time easy. Hard sessions/week: 0 for a new runner's first 8 weeks (strides only), 1 novice, 2 experienced, cap 3. >=1 easy or walk day between hard days.
4 Quality caps: threshold <=10% of weekly volume, VO2max intervals <=8%, reps <=5%.
5 Weekly progression: smaller of +10% or +2 mi; at least +1 mi/week under 10 mi/week; never >30%.
6 Long run <=30% of weekly volume and <=150 min.
8 ACWR: monitor only; warn above 1.5; never the sole reason.
9 Taper (S): mile/5K 5-7 d, 10K 7-10 d, half 10-14 d, marathon 14-21 d; cut volume 41-60% progressively, keep intensity and frequency.
10 Missed easy run: drop it, don't redistribute.
11 Missed key workout: move it only if it keeps >=1 easy day each side and >=2 days before the next key session; otherwise drop.
12 Missed long run: move within the week if rule 11 allows; else drop and keep the next long run at the previous length.
13 Time off: <=5 d resume; 6-28 d week 1 at 50% easy only, week 2 at 75%; >4 wk restart at 33% and rebuild under rule 5.
16 HR scoring ignores the first 90 s of each rep and the first 5 min of a run; reps <2 min on pace only; long easy runs or heat: hold HR, let pace slow.
19 Run/walk: beginners 1:00 run / 1:00-2:00 walk; walk when over the easy ceiling, run again when HR drops 10 bpm.
20 Pace updates: up after a race/test or 3+ sessions 3-5% faster at the same or lower HR; down after 2+ sessions >5% slow or after time off.
21 Fatigue: 7-day HRV below baseline, or resting HR +5-7 bpm for 3+ days -> next hard session becomes easy.
22 Calorie goal: 150 min/week moving (stretch 225+), volume over intensity, <=1 interval session/week. Never give diet or calorie-deficit advice; never adjust runs based on weight.
23 Goal templates: mile/5K intervals + strides, long run <=25%; half threshold-focused; marathon volume + long runs + MP work.
24 Grade = 40% completion, 40% time in target band, 20% consistency.
Today's changes stay small (about +-10% distance or pace); bigger changes target later days. Never state a number the tools didn't compute. Never give medical or dosing advice; pain and illness are the runner's call.`;
