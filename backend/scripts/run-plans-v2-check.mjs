/**
 * Run Plans v2 check (contract: /p/mad-run-plans-api, spec: /p/mad-run-plans-build).
 *
 * A wrong plan is a plausible plan nobody audits, so the rules are pinned:
 *   E. ENGINE (pure): spike guard and back-to-back hard days are HARD; ramp,
 *      taper, cutback are conventions; missed-day rules 10–13; walk modes;
 *      runs/week + difficulty → hard sessions; check-in tweaks; grade
 *      (rule 24); notification timing; pace updates; walk-day suggestions;
 *      every generated plan passes its own HARD rules.
 *   S. SERVICE (DB): proposals never auto-apply (formula pass, first open,
 *      upload hook, nightly); apply / apply-after-run / decline / undo /
 *      supersede / stale; HARD rules reject proposals from every source;
 *      plus_required gating; ai_mode gating; Anthropic counter stop with a
 *      mocked client (strict tools, tool_choice auto, cached prefix, model +
 *      effort per kind, cost recorded, proposals only); AI log retention
 *      sweep; overseer set_plan needs confirmed_in_chat and the admin's own
 *      plan; notification candidate + once-only claim.
 *
 * Usage: DATABASE_URL=... node scripts/run-plans-v2-check.mjs (after `npm run build`)
 */
import { PostgresService } from "../dist/services/DbService.js";
import * as E from "../dist/services/runPlans/engine.js";
import * as S from "../dist/services/runPlans/runPlanService.js";
import * as C from "../dist/services/runPlans/coachSettings.js";
import * as A from "../dist/services/runPlans/anthropicCoach.js";
import * as N from "../dist/services/runPlans/notifications.js";
import * as T from "../dist/services/runPlans/triggers.js";
import * as Admin from "../dist/services/runPlans/adminCoachService.js";
import * as Ctl from "../dist/controllers/runPlansController.js";
import { uploadWorkouts } from "../dist/services/workoutService.js";
import { FOUNDING_CUTOFF } from "../dist/services/plusCatalog.js";

const db = PostgresService.getInstance();
let failures = 0;
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  console.log(`${ok ? "ok  " : "FAIL"}  ${label} → ${JSON.stringify(actual)}${ok ? "" : ` (expected ${JSON.stringify(expected)})`}`);
}
const truthy = (label, v) => check(label, Boolean(v), true);
async function rejects(label, fn, code) {
  try {
    await fn();
    check(label, "resolved", code);
  } catch (e) {
    check(label, e?.code ?? e?.message, code);
  }
}

// ─── E. Engine (pure) ─────────────────────────────────────────────────────

const PROFILE = E.normalizeProfile({ weekly_miles_4w: 15, longest_run_30d_mi: 6, has_hr: true, max_hr: 189, resting_hr: 58, zones: [{ zone: 2, low: 132, high: 146 }, { zone: 4, low: 161, high: 174 }], vdot: 40, experience: "experienced", typical_run_hour: 18 });
const paces = E.pacesFor(40, "vdot");
const hr = E.hrBandsFor(PROFILE);
const settings = (o = {}) => ({ goals: [{ type: "distance_time", distance: "5k", distance_mi: 3.11, target_s: 1320 }], target_date: null, runs_per_week: 4, difficulty: 3, walk_mode: "built_in", fixed_walk_days: [], start_date: "2026-11-23", ...o });
const bctx = E.buildContextFor({ settings: settings(), paces, hr });
const D0 = "2026-11-23"; // a Monday

console.log("\n— paces (Daniels: VDOT 40 → 5K 24:08, T 7:52, I 7:14)");
check("5K at VDOT 40", E.formatDuration(E.raceTimeFor(40, 3.10686)), "24:06");
check("threshold pace", E.formatPace(paces.threshold_s), "7:52");
check("interval pace", E.formatPace(paces.interval_s), "7:14");
check("easy band is slower than marathon pace", paces.easy_s[0] > paces.marathon_s, true);
check("never 220 − age: no HR data ⇒ no zones", E.hrBandsFor({ age: 40 }).easy_ceiling, null);
check("Karvonen ceiling from max + resting", E.hrBandsFor({ has_hr: true, max_hr: 190, resting_hr: 60 }).easy_ceiling, 151);

console.log("\n— runs/week + experience → hard sessions (rule 3); difficulty never changes them");
const G5 = settings().goals;
check("1–3 runs → 1", [1, 2, 3].map((n) => E.hardSessionsFor(n, "experienced", G5)), [1, 1, 1]);
check("4–5 runs → 2", [4, 5].map((n) => E.hardSessionsFor(n, "experienced", G5)), [2, 2]);
check("6–7 runs → 2, 3 only when experienced", [E.hardSessionsFor(6, "novice", G5), E.hardSessionsFor(7, null, G5), E.hardSessionsFor(6, "experienced", G5), E.hardSessionsFor(7, "experienced", G5)], [1, 2, 3, 3]);
check("new runner → 0 (strides)", E.hardSessionsFor(5, "new", G5), 0);
check("novice → max 1", E.hardSessionsFor(5, "novice", G5), 1);
check("calorie primary → ≤ 1 interval session (rule 22)", E.hardSessionsFor(6, "experienced", [{ type: "burn_calories", weekly_minutes: 150 }]), 1);
{
  // Same runs/week, effort 1 vs 4: identical hard days, more miles and reps at 4 (spec §2.3).
  const P25 = { ...PROFILE, weekly_miles_4w: 25, longest_run_30d_mi: 8 };
  const gen = (diff) => E.generateDays({ settings: settings({ difficulty: diff, runs_per_week: 5 }), profile: P25, paces, hr }, D0, E.addDays(D0, 55), [{ local_date: "2026-11-20", distance_mi: 8 }]);
  const d1 = gen(1), d4 = gen(4);
  const hardDates = (ds) => ds.filter((d) => d.day.is_hard).map((d) => d.local_date);
  check("effort 1 vs 4 (5 runs/week): the same hard days, every week", hardDates(d1), hardDates(d4));
  const miles = (ds) => Math.round(ds.reduce((a, d) => a + d.day.distance_mi, 0));
  check("effort 4 runs more miles over 8 weeks than effort 1", miles(d4) > miles(d1) * 1.15, true);
  const reps = (ds) => ds.filter((d) => d.day.kind === "intervals").reduce((a, d) => a + d.day.spec.reps, 0);
  const work = (ds) => ds.filter((d) => d.day.kind === "tempo").reduce((a, d) => a + d.day.spec.work_mi, 0);
  check("effort 4 has more interval reps / tempo work per session", reps(d4) > reps(d1) || work(d4) > work(d1), true);
  const longest = (ds) => Math.max(...ds.filter((d) => d.day.kind === "long").map((d) => d.day.distance_mi));
  check("effort 4 builds a longer long run", longest(d4) > longest(d1), true);
  const sz1 = E.sessionSizes(30, "5k", 1, "rolling"), sz4 = E.sessionSizes(30, "5k", 4, "rolling");
  check("30 mi week, 5K: 800m reps 3 at effort 1 vs 4 at effort 4 (VO2 ≤ 8% of the week)", [sz1.reps, sz4.reps, sz4.reps * sz4.rep_mi <= 30 * 0.08], [3, 4, true]);
  const w1 = E.planWeeks(settings({ difficulty: 1 }), P25, paces, 8), w4 = E.planWeeks(settings({ difficulty: 4 }), P25, paces, 8);
  check("planWeeks: hard per week identical at effort 1 and 4", w1.map((w) => w.hard), w4.map((w) => w.hard));
  const vi = E.volumeInfo({ settings: settings({ difficulty: 3 }), profile: P25, paces, hr }, 0);
  check("volume summary for Push: growth 10%, long-run target, text", [vi.label, vi.weekly_growth_pct, vi.long_run_target_mi > 0, vi.text.startsWith("Push: weekly miles grow up to ~10% a week")], ["Push", 10, true, true]);
}

console.log("\n— generated plans pass their own HARD rules (every runs/week × difficulty × walk mode)");
let genBad = [];
let walkCountBad = [];
for (const rpw of [1, 2, 3, 4, 5, 6, 7]) {
  for (const diff of [1, 2, 3, 4]) {
    for (const mode of ["built_in", "fixed", "flexible"]) {
      const fixed = mode === "fixed" ? [6, 3, 0, 5, 1, 4, 2].slice(0, 7 - rpw) : [];
      const s = settings({ runs_per_week: rpw, difficulty: diff, walk_mode: mode, fixed_walk_days: fixed });
      const days = E.generateDays({ settings: s, profile: PROFILE, paces, hr }, D0, E.addDays(D0, 55), [{ local_date: "2026-11-20", distance_mi: 6 }]);
      const map = new Map(days.map((d) => [d.local_date, d.day]));
      const v = E.validateChanges({ today: D0, days: map, actual: [{ local_date: "2026-11-20", distance_mi: 6 }] }, days.map((d) => ({ local_date: d.local_date, after: d.day })));
      if (!v.ok) genBad.push(`${rpw}/${diff}/${mode}: ${v.violations[0].rule} ${v.violations[0].local_date}`);
      const wk = days.slice(0, 7);
      const walks = wk.filter((d) => d.day.kind === "walk").length;
      const expectWalks = mode === "flexible" ? 0 : 7 - rpw;
      if (walks !== expectWalks) walkCountBad.push(`${rpw}/${diff}/${mode}: ${walks} walks`);
      const hardCount = wk.filter((d) => d.day.is_hard).length;
      if (hardCount > 3) genBad.push(`${rpw}/${diff}/${mode}: ${hardCount} hard`);
    }
  }
}
check("no generated plan breaks the spike guard or back-to-back rule", genBad, []);
check("walk days per week = 7 − runs (flexible: 0, the coach suggests them)", walkCountBad, []);

const fixedWeek = E.generateDays({ settings: settings({ walk_mode: "fixed", fixed_walk_days: [3, 6], runs_per_week: 5 }), profile: PROFILE, paces, hr }, D0, E.addDays(D0, 6), []);
check("fixed walk days land on Thu + Sun", fixedWeek.filter((d) => d.day.kind === "walk").map((d) => E.weekdayName(d.local_date)), ["Thu", "Sun"]);
const flexWeek = E.generateDays({ settings: settings({ walk_mode: "flexible", runs_per_week: 4 }), profile: PROFILE, paces, hr }, D0, E.addDays(D0, 6), []);
check("flexible: 3 flex days (7 − runs) marked walk-able", flexWeek.filter((d) => d.day.flex).length, 3);
const pushWeek = E.generateDays({ settings: settings(), profile: PROFILE, paces, hr }, D0, E.addDays(D0, 6), [{ local_date: "2026-11-20", distance_mi: 6 }]);
check("Push + 4 runs → 2 hard sessions in the week", pushWeek.filter((d) => d.day.is_hard).length, 2);

console.log("\n— spike guard (rule 6, HARD)");
const baseDays = new Map(pushWeek.map((d) => [d.local_date, d.day]));
const actual6 = [{ local_date: "2026-11-20", distance_mi: 6 }];
const vctx = { today: D0, days: baseDays, actual: actual6 };
const sat = E.addDays(D0, 5);
const longOf = (mi) => E.buildDay({ kind: "long", distance_mi: mi }, bctx, { phase: "rolling", week_index: 0 });
check("limit = 10% over the 30-day longest", E.spikeLimit(sat, actual6), 6.6);
check("6.6 mi long run passes", E.validateChanges(vctx, [{ local_date: sat, after: longOf(6.6) }]).ok, true);
const spike = E.validateChanges(vctx, [{ local_date: sat, after: longOf(7) }]);
check("7 mi long run is a HARD violation", spike.violations.map((v) => v.rule), ["spike_guard"]);
check("a run older than 30 days doesn't count", E.spikeLimit(sat, [{ local_date: "2026-10-01", distance_mi: 10 }]), 1.1);
check("planned runs before it count as done", E.spikeLimit("2026-12-12", [...actual6, { local_date: "2026-12-05", distance_mi: 6.6 }]), 7.26);

console.log("\n— no back-to-back hard days (HARD while ≤ 3 hard/week)");
const hardDates = pushWeek.filter((d) => d.day.is_hard).map((d) => d.local_date);
const nextToHard = E.addDays(hardDates[0], 1);
const tempoDay = E.buildDay({ kind: "tempo", distance_mi: 4, work_mi: 2 }, bctx, { phase: "rolling", week_index: 0 });
const b2b = E.validateChanges(vctx, [{ local_date: nextToHard, after: tempoDay }]);
check("hard next to hard ⇒ violation", b2b.violations.some((v) => v.rule === "no_back_to_back_hard"), true);
const four = new Map(baseDays);
for (const d of [0, 2, 4].map((i) => E.addDays(D0, i))) four.set(d, tempoDay);
const b2b4 = E.validateChanges({ ...vctx, days: four }, [{ local_date: E.addDays(D0, 5), after: tempoDay }]);
check("with 4 hard sessions back-to-back is a deviation, not a violation", [b2b4.violations.filter((v) => v.rule === "no_back_to_back_hard").length, b2b4.deviations.some((d) => d.rule === "hard_cap")], [0, true]);

console.log("\n— ramp (rule 5, convention)");
const prevWeek = new Map();
for (let i = 0; i < 7; i++) prevWeek.set(E.addDays(D0, i - 7), i === 2 ? E.buildDay({ kind: "easy", distance_mi: 10 }, bctx) : E.buildDay({ kind: "walk" }, bctx));
const thisWeek = new Map([...prevWeek]);
for (let i = 0; i < 7; i++) thisWeek.set(E.addDays(D0, i), i === 2 ? E.buildDay({ kind: "easy", distance_mi: 10 }, bctx) : E.buildDay({ kind: "walk" }, bctx));
const rctx = { today: E.addDays(D0, -7), days: thisWeek, actual: [{ local_date: E.addDays(D0, -20), distance_mi: 10 }] };
const r1 = E.validateChanges(rctx, [{ local_date: E.addDays(D0, 4), after: E.buildDay({ kind: "easy", distance_mi: 1 }, bctx) }]);
check("+1 mi on a 10 mi week: no deviation", r1.deviations.map((d) => d.rule), []);
const r2 = E.validateChanges(rctx, [{ local_date: E.addDays(D0, 4), after: E.buildDay({ kind: "easy", distance_mi: 2.5 }, bctx) }]);
check("+2.5 mi (25%): ramp deviation", r2.deviations.map((d) => d.rule), ["ramp"]);
const r3 = E.validateChanges(rctx, [{ local_date: E.addDays(D0, 4), after: E.buildDay({ kind: "easy", distance_mi: 5 }, bctx) }, { local_date: E.addDays(D0, 6), after: E.buildDay({ kind: "easy", distance_mi: 1 }, bctx) }]);
check("+6 mi (60%): over-30% deviation", r3.deviations.map((d) => d.rule), ["ramp_30"]);
check("rampStep: 10 mi Push → +1", E.rampStep(10, 3), 1);
check("rampStep: 30 mi → +2 (cap)", E.rampStep(30, 3), 2);
check("rampStep: 5 mi → ≥ +1 under 10 mi/week", E.rampStep(5, 2), 1);

console.log("\n— phases, cutback and taper (rules 1, 2, 9)");
const dated = (dist, weeks) => {
  const target = E.addDays(D0, weeks * 7 - 2); // a Saturday
  return { s: settings({ goals: [{ type: "distance_time", distance: dist, distance_mi: E.DISTANCE_MI[dist] }], target_date: target }), target };
};
const half = dated("half", 16);
const hw = E.planWeeks(half.s, PROFILE, paces, 99);
check("half, 16 weeks: 16 weeks planned", hw.length, 16);
check("half: ends taper → race", hw.slice(-2).map((w) => w.phase), ["taper", "race"]);
check("half: 2 taper weeks (rule 9: 10–14 d)", hw.filter((w) => w.phase === "taper").length + 1, 2);
check("half: starts with ≥ 4 base weeks", hw.slice(0, 4).every((w) => w.phase === "base" || w.phase === "cutback"), true);
check("half: peak phase present", hw.some((w) => w.phase === "peak"), true);
const peakVol = Math.max(...hw.filter((w) => w.phase !== "race" && w.phase !== "taper").map((w) => w.volume_mi));
const taperVols = hw.filter((w) => w.phase === "taper" || w.phase === "race").map((w) => w.volume_mi);
check("taper volume falls progressively (41–60% by race week)", [taperVols[0] < peakVol, taperVols[taperVols.length - 1] <= peakVol * 0.6 + 0.1, taperVols.every((v, i) => i === 0 || v <= taperVols[i - 1])], [true, true, true]);
check("taper keeps intensity: hard sessions in taper weeks", hw.filter((w) => w.phase === "taper").every((w) => w.hard > 0), true);
const mar = E.planWeeks(dated("marathon", 20).s, PROFILE, paces, 99);
check("marathon: 3-week taper (14–21 d)", mar.filter((w) => w.phase === "taper" || w.phase === "race").length, 3);
const fk = dated("5k", 10);
const fkDays = E.generateDays({ settings: fk.s, profile: PROFILE, paces, hr }, D0, E.addDays(D0, 80), actual6);
check("5K: race day on the target date", fkDays.find((d) => d.local_date === fk.target)?.day.kind, "race");
check("5K: 1-week taper (5–7 d)", E.planWeeks(fk.s, PROFILE, paces, 99).filter((w) => w.phase === "race" || w.phase === "taper").length, 1);
const roll = E.planWeeks(settings(), PROFILE, paces, 12);
check("no date: rolling 3-up / 1-down (cutback weeks 4, 8, 12)", roll.map((w, i) => (w.cutback ? i + 1 : null)).filter(Boolean), [4, 8, 12]);
check("cutback = −25% of the week before", Math.round((roll[3].volume_mi / roll[2].volume_mi) * 100) / 100, 0.75);
check("age 50+: cutback every 3rd week", E.planWeeks(settings(), { ...PROFILE, age: 55 }, paces, 9).map((w, i) => (w.cutback ? i + 1 : null)).filter(Boolean), [3, 6, 9]);
check("just improve: a retest in the 8th week", roll[7].retest, true);

console.log("\n— missed days (rules 10–13)");
// A week: Mon intervals (missed), Tue walk, Wed easy, Thu walk, Fri easy, Sat long, Sun walk; today = Wed.
const mk = (spec) => E.buildDay(spec, bctx, { phase: "rolling", week_index: 0 });
const mwk = new Map([
  [D0, mk({ kind: "intervals", reps: 5, rep_mi: 0.5 })],
  [E.addDays(D0, 1), mk({ kind: "walk" })],
  [E.addDays(D0, 2), mk({ kind: "easy", distance_mi: 3 })],
  [E.addDays(D0, 3), mk({ kind: "walk" })],
  [E.addDays(D0, 4), mk({ kind: "easy", distance_mi: 3 })],
  [E.addDays(D0, 5), mk({ kind: "long", distance_mi: 6 })],
  [E.addDays(D0, 6), mk({ kind: "walk" })],
]);
const actx = (o = {}) => ({ today: E.addDays(D0, 2), days: mwk, actual: actual6, settings: settings(), bctx, profile: PROFILE, runs: [], grades: [], pendingDates: new Set(), ...o });
const miss = E.missedRunProposals(actx());
check("missed key session: no slot with an easy day each side + 2 clear days ⇒ dropped", miss.length, 0);
const mwk2 = new Map(mwk);
mwk2.set(E.addDays(D0, 5), mk({ kind: "easy", distance_mi: 3 }));
mwk2.set(E.addDays(D0, 6), mk({ kind: "long", distance_mi: 6 }));
const miss2 = E.missedRunProposals(actx({ days: mwk2 }));
check("missed key session moves to Thu (rule 11 satisfied)", miss2.map((p) => [p.kind, p.changes[0].local_date, p.changes[0].after.kind]), [["missed_run", E.addDays(D0, 3), "intervals"]]);
const easyMissWk = new Map(mwk);
easyMissWk.set(D0, mk({ kind: "easy", distance_mi: 3 }));
check("missed easy run: dropped, no proposal (rule 10)", E.missedRunProposals(actx({ days: easyMissWk })).length, 0);
const longMiss = new Map(mwk);
const nextMon = E.addDays(D0, 7);
longMiss.set(D0, mk({ kind: "walk" }));
longMiss.set(E.addDays(D0, 5), mk({ kind: "long", distance_mi: 6 }));
for (let i = 7; i < 14; i++) longMiss.set(E.addDays(D0, i), i === 12 ? mk({ kind: "long", distance_mi: 6.5 }) : mk({ kind: i % 2 ? "easy" : "walk", distance_mi: 3 }));
const lm = E.missedRunProposals({ ...actx({ days: longMiss }), today: nextMon });
check("missed long run (no room to move): next long holds at the missed length (rule 12)", lm.map((p) => [p.changes[0].local_date, p.changes[0].after.distance_mi]), [[E.addDays(D0, 12), 6]]);
const brk = (gapDays) => E.returnFromBreakProposal(actx({ today: E.addDays(D0, 2), runs: [{ workout_id: "x", local_date: E.addDays(D0, 2 - gapDays - 1), workout_type: "running", distance_mi: 5, duration_s: 2700, moving_s: null }] }));
check("≤ 5 days off: resume, no proposal", brk(5), null);
const b10 = brk(10);
check("10 days off: return proposal, hard → easy in week 1", [b10?.kind, b10?.changes.filter((c) => c.after.is_hard).length], ["return_from_break", 0]);
check("10 days off: Sat long 6 → 3 mi (50%)", b10?.changes.find((c) => c.local_date === E.addDays(D0, 5))?.after.distance_mi, 3);
check("10 days off: paces gentler", (b10?.changes[0].after.spec.pace_factor ?? 1) > 1, true);
const b40 = brk(40);
check("> 4 weeks off: restart at ~33%", b40?.changes.find((c) => c.local_date === E.addDays(D0, 5))?.after.distance_mi, 2);

console.log("\n— pace updates (rule 20)");
const g = (d, delta, hrd = -2) => ({ local_date: d, kind: "intervals", score: 90, on_target: 80, pace_delta: delta, hr_delta: hrd });
const up = E.paceUpdateProposal(actx({ grades: [g("2026-11-10", -0.04), g("2026-11-14", -0.035), g("2026-11-18", -0.045)] }));
check("3 sessions 3–5% fast at ≤ HR → faster paces (step 4%)", [up?.kind, up?.plan_patch?.pace_factor], ["pace_update", 0.96]);
check("…only 2 fast sessions → nothing", E.paceUpdateProposal(actx({ grades: [g("2026-11-14", -0.04), g("2026-11-18", -0.04)] })), null);
check("…fast but HR higher → nothing", E.paceUpdateProposal(actx({ grades: [g("2026-11-10", -0.04, 5), g("2026-11-14", -0.04, 5), g("2026-11-18", -0.04, 5)] })), null);
const down = E.paceUpdateProposal(actx({ grades: [g("2026-11-14", 0.07), g("2026-11-18", 0.06)] }));
check("2 sessions > 5% slow → gentler paces", down?.plan_patch?.pace_factor, 1.05);
check("goal impact carries a computed 5K estimate", typeof up?.goal_impact?.before_s === "number" && up.goal_impact.after_s < up.goal_impact.before_s, true);

console.log("\n— flexible walk days: earned / overdoing it");
const fset = settings({ walk_mode: "flexible", runs_per_week: 4 });
const fDays = new Map(E.generateDays({ settings: fset, profile: PROFILE, paces, hr }, D0, E.addDays(D0, 13), actual6).map((d) => [d.local_date, d.day]));
const flexToday = [...fDays].find(([d, day]) => day.flex && E.weekdayIndex(d) >= 3)?.[0];
const coreBefore = [...fDays].filter(([d, day]) => d < flexToday && d >= D0 && !day.flex && day.kind !== "walk");
const doneRuns = coreBefore.map(([d, day], i) => ({ workout_id: `r${i}`, local_date: d, workout_type: "running", distance_mi: day.distance_mi, duration_s: day.est_duration_s, moving_s: null }));
const earned = E.walkDayProposals({ ...actx({ days: fDays, settings: fset, runs: doneRuns }), today: flexToday });
check("every core run done + on target ⇒ 'You've earned a walk day' for today", earned.map((p) => [p.kind, p.changes[0].local_date, p.changes[0].after.kind]), [["walk_day_earned", flexToday, "walk"]]);
const tired = { ...PROFILE, resting_hr: 58, resting_hr_7d: [58, 58, 59, 58, 64, 65, 65] };
const over = E.walkDayProposals({ ...actx({ days: fDays, settings: fset, runs: doneRuns, profile: tired }), today: flexToday });
check("resting HR +5 for 3 days ⇒ 'walk day tomorrow?' (not 'earned')", over.map((p) => p.kind), ["walk_day_needed"]);
const overB = E.walkDayProposals({ ...actx({ days: mwk2, profile: tired }), today: D0 });
check("built-in mode + fatigue ⇒ next hard session becomes easy (rule 21)", overB.map((p) => [p.kind, p.changes[0].after.kind]), [["adjust", "easy"]]);
const acwrOnly = E.fatigueSignals({ ...actx({ runs: Array.from({ length: 7 }, (_, i) => ({ workout_id: `a${i}`, local_date: E.addDays(D0, -i - 1), workout_type: "running", distance_mi: 8, duration_s: 4800, moving_s: null })) }), today: D0 });
check("ACWR is monitored but never the sole gate (rule 8)", [acwrOnly.acwr > 1.5, acwrOnly.fatigue_flag], [true, false]);

console.log("\n— check-in → fixed tweaks (spec §7)");
const cctx = actx({ days: mwk2, today: D0 });
const ci = (o) => E.checkinProposal(cctx, { local_date: D0, ...o }, 1);
check("tired on an interval day → easy run", ci({ energy: 2 })?.changes[0].after.kind, "easy");
check("very sore → easy run", ci({ soreness: 8 })?.changes[0].after.kind, "easy");
check("20 minutes available → fewer reps", (ci({ time_available_min: 20 })?.changes[0].after.spec.reps ?? 99) < 5, true);
const goWk = new Map(mwk2);
goWk.set(E.addDays(D0, 2), mk({ kind: "easy", distance_mi: 4 }));
const goCtx = actx({ days: goWk, today: E.addDays(D0, 2) });
const go = (mi) => E.checkinProposal(goCtx, { local_date: E.addDays(D0, 2), go_further_mi: mi }, 1)?.changes[0].after.distance_mi;
check("go further 4 → 5 mi", go(5), 5);
check("go further 4 → 8 mi is capped by the spike guard (6.6 → 6.5)", go(8), 6.5);
check("energized, nothing else → no change", ci({ energy: 9 }), null);
const streak3 = E.checkinProposal(cctx, { local_date: D0, energy: 2 }, 3);
check("low energy 3 days running → a lighter few days", [streak3?.title, streak3?.changes.length >= 2], ["A lighter few days", true]);

console.log("\n— grade (rule 24)");
check("completion: ±20% full credit", [E.completionScore(4, 4.8), E.completionScore(4, 3.2)], [100, 100]);
check("completion: 0 at ±50%", E.completionScore(4, 2), 0);
check("completion: linear between (−35% → 50)", E.completionScore(4, 2.6), 50);
check("rep CV ≤ 3% full, > 6% zero", [E.repConsistency([400, 402, 398, 401]), E.repConsistency([360, 440, 380, 460])], [100, 0]);
check("easy HR drift < 5% full, 10% zero", [E.driftConsistency(4), E.driftConsistency(7.5), E.driftConsistency(10)], [100, 50, 0]);
const ivDay = mk({ kind: "intervals", reps: 5, rep_mi: 0.25 });
const gr = E.gradeSession(ivDay, { actual_distance_mi: ivDay.distance_mi, segments: [{ index: 1, scored_s: 100, in_band_s: 78 }], rep_paces_s: [400, 400, 400, 400, 400] });
check("40/40/20 weighting (100, 78, 100 → 91)", [gr.completion, gr.on_target, gr.consistency, gr.score], [100, 78, 100, 91]);
const easyDay = mk({ kind: "easy", distance_mi: 4 });
const tooFast = E.gradeSession(easyDay, { actual_distance_mi: 4, avg_pace_s: paces.easy_s[0] * 0.88 });
const onPace = E.gradeSession(easyDay, { actual_distance_mi: 4, avg_pace_s: (paces.easy_s[0] + paces.easy_s[1]) / 2 });
check("an easy run done too fast loses points", tooFast.score < onPace.score && onPace.on_target === 100, true);

console.log("\n— notification timing (spec §6)");
check("runs before 9 AM → 8 PM the evening before", E.notificationLocalTime(6, "2026-12-01"), { local_date: "2026-11-30", hour: 20 });
check("runs at 6 PM → 9 AM on the day", E.notificationLocalTime(18, "2026-12-01"), { local_date: "2026-12-01", hour: 9 });
check("unknown → 9 AM", E.notificationLocalTime(null, "2026-12-01"), { local_date: "2026-12-01", hour: 9 });
check("9 AM New York (UTC−5) = 14:00 UTC", E.notificationDueAt(18, "2026-12-01", -300).toISOString(), "2026-12-01T14:00:00.000Z");
check("8 PM the night before in Tokyo (UTC+9) = 11:00 UTC", E.notificationDueAt(6, "2026-12-01", 540).toISOString(), "2026-11-30T11:00:00.000Z");
const dec = (h, nowIso) => N.notificationDecision(h, "2026-12-01", -300, new Date(nowIso));
check("not yet due at 8:59 AM local", dec(18, "2026-12-01T13:59:00Z").send, false);
check("due at 9:00 AM local, 'tonight' for an evening runner", [dec(18, "2026-12-01T14:00:00Z").send, dec(18, "2026-12-01T14:00:00Z").when], [true, "tonight"]);
check("early runner: due at 8 PM the night before, 'tomorrow'", [dec(6, "2026-12-01T01:00:00Z").send, dec(6, "2026-12-01T01:00:00Z").when], [true, "tomorrow"]);
check("stale after the run day", dec(18, "2026-12-02T15:00:00Z").send, false);
check("push body names the change", N.proposalPushBody("tomorrow", "5 × 800m", "Easy 4 mi", "You ran hard twice this week."), "Suggested for tomorrow: Easy 4 mi instead of 5 × 800m. You ran hard twice this week. Tap to decide.");

console.log("\n— DaySpec → computed numbers");
const built = E.buildDay({ kind: "intervals", reps: 5, rep_mi: 0.25 }, bctx);
check("5 × 400m: 5 work segments with pace band + mph", [built.segments.filter((s) => s.kind === "work").length, built.segments[1].pace_low_s < built.segments[1].target_pace_s, built.segments[1].speed_mph > 0], [5, true, true]);
check("short reps scored on pace only (rule 16)", built.segments[1].score_by, "pace");
check("walk day = 0 run miles, 1 mi walk segment", [E.buildDay({ kind: "walk" }, bctx).distance_mi, E.buildDay({ kind: "walk" }, bctx).segments[0].distance_mi], [0, 1]);
let specErr = null;
try { E.buildDay({ kind: "easy", distance_mi: 400 }, bctx); } catch (e) { specErr = e.code; }
check("absurd spec rejected", specErr, "invalid_day_spec");

console.log("\n— goals: primary + secondary (spec §2.1)");
{
  const roles = E.validateGoals([{ type: "distance_time", distance: "half", target_s: 9439, role: "primary" }, { type: "distance_time", distance: "5k", target_s: 1199, role: "secondary", target_date: null }]);
  check("roles kept as sent", roles.map((g) => [g.distance, g.role]), [["half", "primary"], ["5k", "secondary"]]);
  let err = null;
  try { E.validateGoals([{ type: "just_improve", role: "primary" }, { type: "distance_time", distance: "5k", role: "primary" }]); } catch (e) { err = e.code; }
  check("two primaries → invalid_goals", err, "invalid_goals");
  err = null;
  try { E.validateGoals([{ type: "just_improve", role: "primary" }, { type: "distance_time", distance: "5k", role: "secondary" }, { type: "burn_calories", role: "secondary" }]); } catch (e) { err = e.code; }
  check("three goals with roles → invalid_goals", err, "invalid_goals");
  err = null;
  try { E.validateGoals([{ type: "distance_time", distance: "5k", role: "secondary" }]); } catch (e) { err = e.code; }
  check("no primary → invalid_goals", err, "invalid_goals");
  check("legacy (no roles): the longest race is primary, the next goal secondary", E.validateGoals([{ type: "distance_time", distance: "5k" }, { type: "distance_time", distance: "half" }, { type: "just_improve" }]).map((g) => g.role), ["secondary", "primary", null]);
  check("legacy [5K, just improve]: 5K primary", E.validateGoals([{ type: "just_improve" }, { type: "distance_time", distance: "5k" }]).map((g) => g.role), ["secondary", "primary"]);
  check("the PRIMARY shapes the plan, even when the secondary is longer", E.focusOf([{ type: "distance_time", distance: "5k", distance_mi: 3.11, role: "primary" }, { type: "distance_time", distance: "half", distance_mi: 13.11, role: "secondary" }]), "5k");
}

console.log("\n— per-goal estimates (speed vs endurance limiter, checkpoints)");
const TD = "2026-11-25";
const v26 = E.vdotFromRace(E.DISTANCE_MI["5k"], 1560);
const P26 = E.normalizeProfile({ ...PROFILE, vdot: Math.round(v26 * 10) / 10, longest_run_30d_mi: 8, weekly_miles_4w: 15 });
const est = (goal, o = {}) => E.goalEstimate(goal, 0, { vdot: P26.vdot, profile: P26, today: TD, easy_pace_s: 700, ...o });
const halfGoal = { type: "distance_time", distance: "half", distance_mi: 13.11, target_s: Math.round(720 * 13.1094), role: "primary", target_date: null };
const he = est(halfGoal);
check("half at 12:00/mi, 5K 26:00, longest 8 mi → endurance-limited, ~5–7 weeks", [he.limiter, he.weeks, he.speed_weeks, he.long_run_needed_mi], ["endurance", [5, 7], [0, 0], 11]);
check("…'5K ~26:00 ≈ half ~2:00' and the projected date ~6 weeks out", [/^5K 2[56]:\d\d ≈ half (1:5\d|2:0\d):\d\d$/.test(he.now_label), he.projected_date, he.feasibility], [true, E.addDays(TD, 42), null]);
check("…its text names the gap", /speed is already there.*longest run 8 mi.*11 mi/.test(he.text), true);
const fe = est({ type: "distance_time", distance: "5k", distance_mi: 3.11, target_s: 1199, role: "secondary", target_date: null });
check("…text: 'a big jump', in months", /big jump: roughly \d+–\d+ months/.test(fe.text), true);
check("5K sub-20 from 26:00 → speed-limited, roughly a year (≤ 1 VDOT point per 2–3 weeks)", [fe.limiter, fe.weeks[0] >= 30, fe.weeks[1] <= 60], ["speed", true, true]);
check("…checkpoints sub-24, then sub-22", fe.checkpoints.map((c) => c.label), ["sub-24 5K", "sub-22 5K"]);
check("…checkpoints in order, before the goal", fe.checkpoints.every((c, i, a) => c.eta_week > 0 && c.eta_week < fe.weeks[1] && (i === 0 || c.eta_week > a[i - 1].eta_week)), true);
check("dated half in 3 weeks → unlikely; in 10 weeks → on track", [est({ ...halfGoal, target_date: E.addDays(TD, 21) }).feasibility, est({ ...halfGoal, target_date: E.addDays(TD, 70) }).feasibility], ["unlikely", "on_track"]);
check("plan.checkpoints: primary's then secondary's, with goal_index", E.checkpointsFor([he, { ...fe, goal_index: 1 }]).map((c) => [c.goal_index, c.label]), [[1, "sub-24 5K"], [1, "sub-22 5K"]]);
check("spike-rule endurance steps: 8 → 11 mi = 4 steps + 1 cutback", E.enduranceWeeks(8, 11), [5, 7]);
const run = (d, mi, secs) => ({ workout_id: `a-${d}-${mi}`, local_date: d, workout_type: "running", distance_mi: mi, duration_s: secs, moving_s: null });
check("achieved: a run ≥ the distance, at pace × distance ≤ target", E.goalAchievement(halfGoal, [run("2026-12-20", 13.2, 9000)], P26, "2026-11-25")?.seconds, Math.round((9000 * E.DISTANCE_MI.half) / 13.2));
check("not achieved: too slow, too short, or before the plan", [E.goalAchievement(halfGoal, [run("2026-12-20", 13.2, 9900)], P26, "2026-11-25"), E.goalAchievement(halfGoal, [run("2026-12-20", 12, 6000)], P26, "2026-11-25"), E.goalAchievement(halfGoal, [run("2026-11-01", 13.2, 8000)], P26, "2026-11-25")], [null, null, null]);

console.log("\n— the secondary gets ≤ 1 speed session a week, inside the hard-session count");
{
  const G2 = [{ type: "distance_time", distance: "half", distance_mi: 13.11, target_s: 9439, role: "primary", target_date: null }, { type: "distance_time", distance: "5k", distance_mi: 3.11, target_s: 1199, role: "secondary", target_date: null }];
  const P = { ...P26, weekly_miles_4w: 20 };
  const gen = (rpw) => E.generateDays({ settings: settings({ goals: G2, runs_per_week: rpw }), profile: P, paces, hr }, D0, E.addDays(D0, 27), [{ local_date: "2026-11-20", distance_mi: 8 }]);
  const byWeek = (ds) => [0, 1, 2, 3].map((w) => ds.filter((d) => d.day.week_index === w));
  const five = byWeek(gen(5));
  const fullWeeks = five.filter((wk) => wk.filter((d) => d.day.is_hard).length >= 2);
  check("5 runs: every 2-hard week has exactly one secondary session", fullWeeks.length > 0 && fullWeeks.every((wk) => wk.filter((d) => d.day.spec.for_goal === "secondary").length === 1), true);
  check("…it's 800m intervals (5K speed) and still only 2 hard days", fullWeeks.every((wk) => { const s2 = wk.find((d) => d.day.spec.for_goal === "secondary"); return s2.day.kind === "intervals" && s2.day.spec.rep_mi === 0.5 && wk.filter((d) => d.day.is_hard).length === 2; }), true);
  const three = byWeek(gen(3));
  check("3 runs (1 hard): the secondary gets strides on an easy day, the hard day stays the primary's", three.every((wk) => wk.filter((d) => d.day.is_hard && d.day.spec.for_goal === "secondary").length === 0 && wk.filter((d) => d.day.spec.for_goal === "secondary" && d.day.kind === "easy" && d.day.spec.strides).length <= 1) && three.some((wk) => wk.some((d) => d.day.spec.for_goal === "secondary")), true);
  const v = E.validateChanges({ today: D0, days: new Map(gen(5).map((d) => [d.local_date, d.day])), actual: [{ local_date: "2026-11-20", distance_mi: 8 }] }, gen(5).map((d) => ({ local_date: d.local_date, after: d.day })));
  check("plans with a secondary pass the HARD rules", v.violations, []);
}

console.log("\n— shoes: run types only, never walk days");
check("assignable types", [...E.SHOE_RUN_TYPES], ["easy", "long", "tempo", "intervals", "race"]);
check("walk day → no shoe type; calibration → race shoe", [E.shoeRunTypeFor("walk"), E.shoeRunTypeFor("calibration"), E.shoeRunTypeFor("long")], [null, "race", "long"]);

console.log("\n— effort guess (RPE) calibration and signals (spec §9)");
{
  check("2 ratings: calibration not applied yet", E.calibrationFrom("quality", [{ raw_guess: 6, user_rating: 8 }, { raw_guess: 6, user_rating: 8 }]).applied, false);
  const cal = E.calibrationFrom("quality", [{ raw_guess: 6, user_rating: 8 }, { raw_guess: 5, user_rating: 7 }, { raw_guess: 6.5, user_rating: 8.5 }]);
  check("3 ratings +2 each → offset +2, applied", [cal.offset, cal.samples, cal.applied], [2, 3, true]);
  check("served guess = raw + offset, clamped 1–10", [E.servedGuess(6.4, cal).guess, E.servedGuess(9.5, cal).guess, E.servedGuess(6.4, null).guess], [8, 10, 6]);
  check("EWMA leans to recent ratings", E.calibrationFrom("easy", [{ raw_guess: 5, user_rating: 5 }, { raw_guess: 5, user_rating: 5 }, { raw_guess: 5, user_rating: 9 }]).offset, 1.2);
  check("offset capped at ±4", E.calibrationFrom("easy", [{ raw_guess: 1, user_rating: 10 }]).offset, 4);
  check("labels", [1, 4, 6, 7, 9, 10].map(E.rpeLabel), ["very easy", "easy", "moderate", "hard", "very hard", "max"]);
  check("reason from features", E.effortReason(E.normalizeEffortFeatures({ has_hr: true, avg_hr_zone: 3.4, peak_hr_zone: 5, pace_vs_predicted_pct: -5 }), "intervals"), "HR reached zone 5 on the hard parts, pace was 5% faster than your fitness predicts.");
  let ferr = null;
  try { E.normalizeEffortFeatures({ time_in_zones_s: [1, 2, 3] }); } catch (e) { ferr = e.code; }
  check("features: time_in_zones_s must be 5 numbers", ferr, "invalid_effort");
  const ectx = actx({ days: mwk2, today: E.addDays(D0, -1) });
  const fat = E.effortFatigueProposal(ectx, { workout_id: "w", local_date: E.addDays(D0, -1), effort_type: "easy", guess: 6, user_rating: 8 });
  check("rated 8 vs guess 6 → lighter next hard day (fewer reps, gentler pace), proposal kind effort_fatigue", [fat?.kind, fat?.changes[0].local_date, fat?.changes[0].after.spec.reps < 5, fat?.changes[0].after.spec.pace_factor > 1], ["effort_fatigue", D0, true, true]);
  check("rated 7 vs guess 6 → no signal", E.effortFatigueProposal(ectx, { workout_id: "w", local_date: E.addDays(D0, -1), effort_type: "easy", guess: 6, user_rating: 7 }), null);
  const r = (g, u, t = "easy") => ({ workout_id: `x${g}${u}`, local_date: D0, effort_type: t, guess: g, user_rating: u });
  check("3 of the last 4 rated ≥ 2 below → progression signal", [E.progressionSignal([r(6, 4), r(6, 6), r(6, 3), r(5, 3)], "easy"), E.progressionSignal([r(6, 4), r(6, 6), r(6, 5), r(5, 3)], "easy"), E.progressionSignal([r(6, 4), r(6, 4), r(6, 4)], "long")], [true, false, false]);
  const prog = E.effortProgressionProposal(actx({ days: mwk2, today: E.addDays(D0, -1) }), "easy", "w9");
  check("progression → paces 3% faster for the coming days (rule 20 step)", [prog?.kind, prog?.plan_patch?.pace_factor, prog?.changes.every((c) => c.after.spec.pace_factor === 0.97)], ["effort_progression", 0.97, true]);
}

// ─── S. Service (DB) ──────────────────────────────────────────────────────

const PLUS = "rp2-plus";
const FREE = "rp2-free";
const ADMIN = "rp2-admin";
const AI = "rp2-ai";
const SEQ = "rp2-seq";
const GOAL = "rp2-goal";
const ALL = [PLUS, FREE, ADMIN, AI, SEQ, GOAL];
const today = new Date().toISOString().slice(0, 10);
const savedEnv = { key: process.env.ANTHROPIC_API_KEY };
const month = C.currentMonth();
let savedSpend = null;

async function cleanup() {
  await db.query(`DELETE FROM coach_review_notes WHERE author_id = ANY($1) OR user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM coach_ai_calls WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM coach_settings WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM run_plans WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM run_fitness_profiles WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM device_tokens WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM in_app_notifications WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM workout_splits WHERE workout_id IN (SELECT workout_id FROM workouts WHERE user_id = ANY($1))`, [ALL]);
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM plus_purchases WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1)`, [ALL]);
}
const daysSnapshot = async (uid) =>
  JSON.stringify(await db.query(`SELECT d.local_date::text, d.version, d.day FROM run_plan_days d JOIN run_plans p ON p.plan_id = d.plan_id WHERE p.user_id = $1 AND p.status = 'active' AND d.local_date <= $2::date ORDER BY 1`, [uid, E.addDays(today, 27)]));
function mockRes() {
  const r = { statusCode: 200, body: null, headersSent: false };
  r.status = (c) => ((r.statusCode = c), r);
  r.json = (b) => ((r.body = b), (r.headersSent = true), r);
  return r;
}
async function callCtl(fn, userId, { body = {}, query = {}, params = {}, method = "POST" } = {}) {
  const res = mockRes();
  let nexted = false;
  await fn({ userId, body, query, params, method }, res, () => (nexted = true));
  return { status: res.statusCode, body: res.body, nexted };
}
function workout(id, localDate, miles, hourUtc = 12) {
  const end = `${localDate}T${String(hourUtc).padStart(2, "0")}:00:00.000Z`;
  return { workoutId: id, distance: miles, localDate, date: end, timezoneOffset: 0, workoutType: "running", deviceEndDate: end, calories: 100 * miles, totalDuration: miles * 600, splits: [] };
}

async function main() {
  await cleanup();
  const afterCutoff = new Date(Date.parse(FOUNDING_CUTOFF) + 86_400_000).toISOString();
  for (const id of ALL) {
    await db.query(`INSERT INTO users (user_id, apple_sub, email, username, first_name, created_at) VALUES ($1::text, $1::text, $1::text || '@example.com', $1::text, 'RP', GREATEST(now(), $2::timestamptz))`, [id, afterCutoff]);
  }
  await db.query(`UPDATE users SET role = 'admin' WHERE user_id = $1`, [ADMIN]);
  for (const id of [PLUS, ADMIN, AI, SEQ, GOAL]) {
    await db.query(
      `INSERT INTO plus_purchases (original_transaction_id, user_id, product_id, transaction_id, kind, ownership, environment, purchased_at)
       VALUES ($1, $2, 'mad_plus_lifetime', $1, 'lifetime', 'PURCHASED', 'Sandbox', now())`,
      [`rp2-tx-${id}`, id],
    );
  }

  console.log("\n— plus_required gating");
  const gate = async (uid) => callCtl(Ctl.requirePlus, uid);
  const g1 = await gate(FREE);
  check("non-member → 403 plus_required", [g1.status, g1.body?.error, g1.nexted], [403, "plus_required", false]);
  check("member passes the gate", (await gate(PLUS)).nexted, true);
  const stFree = await callCtl(Ctl.status, FREE, { method: "GET" });
  check("/status still answers a non-member (plus: false, formula)", [stFree.status, stFree.body?.plus, stFree.body?.ai?.effective, stFree.body?.ai?.reason], [200, false, "formula", "not_plus"]);

  console.log("\n— create + read");
  await S.putProfile(PLUS, { ...PROFILE, typical_run_hour: 18 }, today);
  const created = await S.createPlan(PLUS, { goals: [{ type: "distance_time", distance: "5k", target_s: 1320 }, { type: "just_improve" }], runs_per_week: 4, difficulty: 3, walk_mode: "built_in" }, today);
  check("plan created; this week = its days from the start date", [created.plan.runs_per_week, created.plan.hard_sessions_per_week, created.week.length], [4, 2, 7 - E.weekdayIndex(today)]);
  await rejects("a second active plan → plan_exists", () => S.createPlan(PLUS, { goals: [{ type: "just_improve" }], runs_per_week: 3, difficulty: 2, walk_mode: "built_in" }, today), "plan_exists");
  await rejects("fixed walk days must be 7 − runs", () => S.previewPlan(PLUS, { goals: [{ type: "just_improve" }], runs_per_week: 4, difficulty: 2, walk_mode: "fixed", fixed_walk_days: [3] }, today), "fixed_walk_days_mismatch");
  const days28 = await S.getDays(PLUS, today, E.addDays(today, 27), today);
  check("28 days materialized ahead", days28.length, 28);
  check("served day carries segments, status, version", ["segments", "status", "version", "pending_proposal_ids", "shoe"].every((k) => k in days28[0]), true);

  console.log("\n— proposals never auto-apply (formula pass, first open, upload hook, nightly)");
  // Time off: one run 12 days ago, nothing since ⇒ the formula proposes a return-to-run block.
  await uploadWorkouts(PLUS, [workout("rp2-w-old", E.addDays(today, -12), 5)]);
  const before = await daysSnapshot(PLUS);
  const pass = await S.runFormulaPass(PLUS, today, "first_open");
  check("formula pass made a proposal (return from break)", pass.map((p) => [p.source, p.kind, p.status]), [["formula", "return_from_break", "pending"]]);
  check("…and the plan days did not change", (await daysSnapshot(PLUS)) === before, true);
  const pass2 = await S.runFormulaPass(PLUS, today, "first_open");
  check("re-running the pass doesn't repeat it (dedupe)", pass2.length, 0);
  const op = await S.openPlan(PLUS, today);
  const op2 = await S.openPlan(PLUS, today);
  check("first open of the day runs once", [op.ran, op2.ran], [true, false]);
  check("…days still unchanged", (await daysSnapshot(PLUS)) === before, true);
  await uploadWorkouts(PLUS, [workout("rp2-w-today", today, 1.2)]);
  await T.afterWorkoutUpload(PLUS, ["rp2-w-today"]);
  const afterUpload = JSON.parse(await daysSnapshot(PLUS)).map((r) => [r.local_date, r.version]);
  check("upload hook graded the day but changed no plan day", afterUpload.every(([, v]) => v === 1), true);
  const graded = await db.query(`SELECT g.source FROM run_plan_grades g JOIN run_plans p ON p.plan_id = g.plan_id WHERE p.user_id = $1 AND g.local_date = $2::date`, [PLUS, today]);
  const todayIsRun = days28[0].kind !== "walk";
  check("server fallback grade stored for a run day", graded.map((r) => r.source), todayIsRun ? ["server"] : []);
  await db.query(`UPDATE run_plans SET last_nightly_date = NULL WHERE user_id = $1`, [PLUS]);
  const ran = await S.nightlyPass(PLUS, today);
  const ranAgain = await S.nightlyPass(PLUS, today);
  check("nightly pass claimed once per local day", [ran, ranAgain], [true, false]);
  check("…days still unchanged", JSON.parse(await daysSnapshot(PLUS)).every((r) => r.version === 1), true);
  const cronRun = await T.runNightlyPasses(new Date());
  check("nightly cron runs without error", typeof cronRun.due, "number");

  console.log("\n— lifecycle: apply / undo / decline / apply-after-run / supersede / stale");
  const pend = await S.listProposals(PLUS, "pending", 50, today);
  const ret = pend.find((p) => p.kind === "return_from_break");
  const firstDate = ret.changes[0].local_date;
  const ap = await S.applyProposal(PLUS, ret.id, today);
  check("apply → applied, undo window 24 h", [ap.proposal.status, Math.round((Date.parse(ap.proposal.undo_until) - Date.parse(ap.proposal.applied_at)) / 3_600_000)], ["applied", 24]);
  const dayAfter = (await S.getDays(PLUS, firstDate, firstDate, today))[0];
  check("…the day now shows the proposal's version", [dayAfter.version, dayAfter.distance_mi], [2, ret.changes[0].after.distance_mi]);
  await rejects("apply twice → proposal_not_pending", () => S.applyProposal(PLUS, ret.id, today), "proposal_not_pending");
  const un = await S.undoProposal(PLUS, ret.id, today);
  const dayUndone = (await S.getDays(PLUS, firstDate, firstDate, today))[0];
  check("undo → undone, day restored", [un.proposal.status, dayUndone.distance_mi, dayUndone.kind], ["undone", ret.changes[0].before.distance_mi, ret.changes[0].before.kind]);
  await rejects("undo twice → proposal_not_pending", () => S.undoProposal(PLUS, ret.id, today), "proposal_not_pending");

  const futureRun = (await S.getDays(PLUS, E.addDays(today, 1), E.addDays(today, 13), today)).find((d) => d.kind === "easy" || d.kind === "long");
  const shorter = { kind: futureRun.kind, distance_mi: Math.max(1, futureRun.distance_mi - 0.5) };
  const userP = await S.createProposal(PLUS, { source: "user", kind: "adjust", title: "Shorter", reason: "Busy day.", changes: [{ local_date: futureRun.local_date, spec: shorter }] }, today);
  check("user proposal is pending; plan unchanged", [userP.status, (await S.getDays(PLUS, futureRun.local_date, futureRun.local_date, today))[0].version], ["pending", futureRun.version]);
  const userP2 = await S.createProposal(PLUS, { source: "user", kind: "adjust", title: "Even shorter", reason: "Busier.", changes: [{ local_date: futureRun.local_date, spec: { ...shorter, distance_mi: 1 } }] }, today);
  check("a newer proposal for the same day supersedes the older", (await S.getProposal(PLUS, userP.id, today)).status, "superseded");
  const dec2 = await S.declineProposal(PLUS, userP2.id, today);
  check("decline → declined, plan unchanged", [dec2.proposal.status, (await S.getDays(PLUS, futureRun.local_date, futureRun.local_date, today))[0].version], ["declined", futureRun.version]);

  const userP3 = await S.createProposal(PLUS, { source: "user", kind: "adjust", title: "Shorter", reason: "Busy.", changes: [{ local_date: futureRun.local_date, spec: shorter }] }, today);
  await db.query(`UPDATE run_plan_days d SET version = version + 1 FROM run_plans p WHERE p.plan_id = d.plan_id AND p.user_id = $1 AND d.local_date = $2::date`, [PLUS, futureRun.local_date]);
  await rejects("apply after the day changed → stale_proposal", () => S.applyProposal(PLUS, userP3.id, today), "stale_proposal");
  check("…stale proposal is marked superseded", (await S.getProposal(PLUS, userP3.id, today)).status, "superseded");

  // Apply after today's run: scheduled, lands when today's run syncs.
  const todayDay = (await S.getDays(PLUS, today, E.addDays(today, 6), today)).find((d) => d.local_date === today);
  const tomorrow = E.addDays(today, 1);
  const tomorrowDay = (await S.getDays(PLUS, tomorrow, tomorrow, today))[0];
  const aar = await S.createProposal(PLUS, { source: "user", kind: "adjust", title: "Walk tomorrow", reason: "Rest.", changes: [{ local_date: today, spec: todayDay.kind === "walk" ? { kind: "walk" } : { kind: "easy", distance_mi: Math.max(1, todayDay.distance_mi) } }, { local_date: tomorrow, spec: { kind: "walk" } }], deviation_reason: "Test." }, today);
  const sch = await S.applyAfterRun(PLUS, aar.id, today);
  check("apply after today's run → scheduled for today", [sch.proposal.status, sch.proposal.apply_after_date], ["scheduled", today]);
  check("…nothing changed yet", (await S.getDays(PLUS, tomorrow, tomorrow, today))[0].version, tomorrowDay.version);
  await uploadWorkouts(PLUS, [workout("rp2-w-today2", today, 1.5, 13)]);
  await T.afterWorkoutUpload(PLUS, ["rp2-w-today2"]);
  const aarAfter = await S.getProposal(PLUS, aar.id, today);
  check("today's run synced → applied (tomorrow is a walk day; today's done run untouched)", [aarAfter.status, (await S.getDays(PLUS, tomorrow, tomorrow, today))[0].kind, aarAfter.changes.map((c) => c.local_date)], ["applied", "walk", [tomorrow]]);
  const p4 = await S.createProposal(PLUS, { source: "user", kind: "adjust", title: "x", reason: "y", changes: [{ local_date: E.addDays(today, 3), spec: { kind: "walk" } }] }, today).catch((e) => e);
  if (p4?.id) await rejects("apply-after-run needs a change for today", () => S.applyAfterRun(PLUS, p4.id, today), "not_for_today");

  console.log("\n— apply re-checks HARD rules on the CURRENT plan; late apply skips past days; long getDays windows");
  await S.putProfile(SEQ, PROFILE, today);
  const seqPlan = await S.createPlan(SEQ, { goals: [{ type: "just_improve" }], runs_per_week: 4, difficulty: 3, walk_mode: "built_in" }, today);
  const seqId = seqPlan.plan.plan_id;
  const W = E.weekStart(E.addDays(today, 8)); // a Monday 2–8 days out
  const W2 = E.addDays(W, 7);
  const dayVer = async (d) => (await db.query(`SELECT version FROM run_plan_days WHERE plan_id = $1 AND local_date = $2::date`, [seqId, d]))[0]?.version;
  const dayOf = async (d) => (await db.query(`SELECT day FROM run_plan_days WHERE plan_id = $1 AND local_date = $2::date`, [seqId, d]))[0]?.day;
  // Week W: every day a plain 3 mi easy run, so no hard day anywhere near Wed/Thu.
  const easy3 = E.buildDay({ kind: "easy", distance_mi: 3 }, bctx, { phase: "rolling", week_index: 0 });
  await db.query(
    `UPDATE run_plan_days SET kind = 'easy', day = $4::jsonb, note = $5 WHERE plan_id = $1 AND local_date BETWEEN $2::date AND $3::date`,
    [seqId, E.addDays(W, -1), E.addDays(W, 7), JSON.stringify(easy3), easy3.note],
  );
  const wed = E.addDays(W, 2);
  const thu = E.addDays(W, 3);
  const tempo = { kind: "tempo", distance_mi: 4, work_mi: 2 };
  const pA = await S.createProposal(SEQ, { source: "user", kind: "adjust", title: "Wed tempo", reason: "Feeling good.", changes: [{ local_date: wed, spec: tempo }], deviation_reason: "Test." }, today);
  const pB = await S.createProposal(SEQ, { source: "user", kind: "adjust", title: "Thu tempo", reason: "Feeling good.", changes: [{ local_date: thu, spec: tempo }], deviation_reason: "Test." }, today);
  check("two non-overlapping proposals (Wed hard, Thu hard) are both pending", [pA.status, pB.status], ["pending", "pending"]);
  await S.applyProposal(SEQ, pA.id, today);
  const thuVer = await dayVer(thu);
  let bErr = null;
  try {
    await S.applyProposal(SEQ, pB.id, today);
  } catch (e) {
    bErr = e;
  }
  check("second apply would make back-to-back hard days → 409 stale_proposal with the violation", [bErr?.code, bErr?.status, (bErr?.extra?.violations ?? []).some((v) => v.rule === "no_back_to_back_hard")], ["stale_proposal", 409, true]);
  check("…refused proposal is superseded; Thursday untouched (still easy)", [(await S.getProposal(SEQ, pB.id, today)).status, await dayVer(thu), (await dayOf(thu)).is_hard], ["superseded", thuVer, false]);

  // Undo re-checks HARD rules: Fri starts hard; A eases Fri, B makes Sat hard; undoing A
  // would put Fri + Sat hard in a row (Wed, Fri, Sat = 3 hard that week).
  const fri1 = E.addDays(W, 4);
  const sat1 = E.addDays(W, 5);
  const tempoDay1 = E.buildDay(tempo, bctx, { phase: "rolling", week_index: 0 });
  await db.query(`UPDATE run_plan_days SET kind = 'tempo', day = $3::jsonb, note = $4 WHERE plan_id = $1 AND local_date = $2::date`, [seqId, fri1, JSON.stringify(tempoDay1), tempoDay1.note]);
  const uA = await S.createProposal(SEQ, { source: "user", kind: "adjust", title: "Easy Fri", reason: "Tired.", changes: [{ local_date: fri1, spec: { kind: "easy", distance_mi: 3 } }], deviation_reason: "Test." }, today);
  await S.applyProposal(SEQ, uA.id, today);
  const uB = await S.createProposal(SEQ, { source: "user", kind: "adjust", title: "Sat tempo", reason: "Fresh.", changes: [{ local_date: sat1, spec: tempo }], deviation_reason: "Test." }, today);
  await S.applyProposal(SEQ, uB.id, today);
  const friVer1 = await dayVer(fri1);
  let uErr = null;
  try {
    await S.undoProposal(SEQ, uA.id, today);
  } catch (e) {
    uErr = e;
  }
  check("undo that would make back-to-back hard days → 409 undo_conflicts_with_plan with the violation", [uErr?.code, uErr?.status, (uErr?.extra?.violations ?? []).some((v) => v.rule === "no_back_to_back_hard")], ["undo_conflicts_with_plan", 409, true]);
  check("…nothing written: A still applied, Friday still easy", [(await S.getProposal(SEQ, uA.id, today)).status, await dayVer(fri1), (await dayOf(fri1)).is_hard], ["applied", friVer1, false]);
  await S.undoProposal(SEQ, uB.id, today);
  const reA = await S.undoProposal(SEQ, uA.id, today);
  check("undo B first, then A undoes cleanly (Friday hard again)", [reA.proposal.status, (await dayOf(fri1)).is_hard, (await dayOf(sat1)).is_hard], ["undone", true, false]);

  // Late acceptance: proposed on W2 Mon for Mon–Thu, accepted on W2 Wed.
  const w2 = [0, 1, 2, 3].map((i) => E.addDays(W2, i));
  const w2Before = await Promise.all(w2.map(async (d) => [await dayVer(d), (await dayOf(d)).distance_mi]));
  const late = await S.createProposal(SEQ, { source: "user", kind: "adjust", title: "Short week", reason: "Travel.", changes: w2.map((d) => ({ local_date: d, spec: { kind: "easy", distance_mi: 2 } })), deviation_reason: "Test." }, W2);
  const lateApplied = await S.applyProposal(SEQ, late.id, w2[2]);
  check("late accept → applied, only today-or-later days recorded", [lateApplied.proposal.status, lateApplied.proposal.changes.map((c) => c.local_date)], ["applied", [w2[2], w2[3]]]);
  check("…past days (Mon, Tue) were not written", [await dayVer(w2[0]), await dayVer(w2[1])], [w2Before[0][0], w2Before[1][0]]);
  check("…Wed, Thu were", [(await dayOf(w2[2])).distance_mi, (await dayOf(w2[3])).distance_mi, await dayVer(w2[2])], [2, 2, w2Before[2][0] + 1]);
  const lateHist = await db.query(`SELECT detail FROM run_plan_history WHERE proposal_id = $1 AND event = 'proposal_applied'`, [late.id]);
  check("…history records the skipped dates", lateHist[0]?.detail?.skipped_dates, [w2[0], w2[1]]);
  await S.undoProposal(SEQ, late.id, w2[2]);
  check("undo restores only the applied days", [
    (await dayOf(w2[2])).distance_mi, (await dayOf(w2[3])).distance_mi, await dayVer(w2[0]), await dayVer(w2[1]),
  ], [w2Before[2][1], w2Before[3][1], w2Before[0][0], w2Before[1][0]]);
  const fri = E.addDays(W2, 4);
  const allPast = await S.createProposal(SEQ, { source: "user", kind: "adjust", title: "Fri walk", reason: "Rest.", changes: [{ local_date: fri, spec: { kind: "walk" } }], deviation_reason: "Test." }, fri);
  const friVer = await dayVer(fri);
  await rejects("accepting after every day passed → proposal_not_pending", () => S.applyProposal(SEQ, allPast.id, E.addDays(fri, 1)), "proposal_not_pending");
  check("…and it is expired, the day untouched", [(await S.getProposal(SEQ, allPast.id, today)).status, await dayVer(fri)], ["expired", friVer]);

  // getDays 90 days back: a completed run there shows done (runs were loaded from only 60 days back).
  const old = E.addDays(today, -90);
  await db.query(
    `INSERT INTO run_plan_days (plan_id, local_date, kind, day, note, version, source) VALUES ($1, $2::date, 'easy', $3::jsonb, $4, 1, 'formula')`,
    [seqId, old, JSON.stringify(easy3), easy3.note],
  );
  await uploadWorkouts(SEQ, [workout("rp2-seq-old", old, 3.2)]);
  const oldDay = (await S.getDays(SEQ, old, old, today))[0];
  check("a 90-day-old completed run shows completed", [oldDay?.status, oldDay?.completed?.workout_ids], ["done", ["rp2-seq-old"]]);

  console.log("\n— HARD rules reject proposals from every source");
  const farDate = (await S.getDays(PLUS, E.addDays(today, 2), E.addDays(today, 10), today)).find((d) => d.kind !== "walk" && d.kind !== "race");
  await rejects("user: a 20 mi run → hard_rule_violation", () => S.createProposal(PLUS, { source: "user", kind: "adjust", title: "Huge", reason: "x", changes: [{ local_date: farDate.local_date, spec: { kind: "long", distance_mi: 20 } }], deviation_reason: "x" }, today), "hard_rule_violation");
  await rejects("apple: same", () => S.createProposal(PLUS, { source: "apple", kind: "adjust", title: "Huge", reason: "x", changes: [{ local_date: farDate.local_date, spec: { kind: "long", distance_mi: 20 } }], deviation_reason: "x" }, today), "hard_rule_violation");
  await rejects("overseer propose: same", () => S.proposeOverseerChange(ADMIN, PLUS, { title: "Huge", reason: "x", changes: [{ local_date: farDate.local_date, day: { kind: "long", distance_mi: 20 } }], deviation_reason: "x" }, today), "hard_rule_violation");
  await rejects("past dates refused", () => S.createProposal(PLUS, { source: "user", kind: "adjust", title: "x", reason: "y", changes: [{ local_date: E.addDays(today, -1), spec: { kind: "walk" } }] }, today), "past_date");
  const ovp = await S.proposeOverseerChange(ADMIN, PLUS, { title: "Easier", reason: "Review.", changes: [{ local_date: farDate.local_date, day: { kind: "walk" } }] }, today);
  check("overseer propose_plan_change on another user's plan → pending, source overseer", [ovp.status, ovp.source], ["pending", "overseer"]);
  await rejects("non-admin can't use the overseer", () => S.proposeOverseerChange(PLUS, PLUS, { changes: [{ local_date: farDate.local_date, day: { kind: "walk" } }] }, today), "admin_required");

  console.log("\n— ai_mode gating");
  check("default ai_mode = apple", (await C.getAiStatus(PLUS)).effective, "apple");
  const okCtx = await callCtl(Ctl.coachContext, PLUS, { method: "GET", query: { today } });
  check("coach context served to an Apple user", [okCtx.status, typeof okCtx.body?.rules, typeof okCtx.body?.limits?.spike_limit_mi_by_date], [200, "string", "object"]);
  await C.setUserAiMode(PLUS, "off", ADMIN);
  check("ai_mode off → formula", (await C.getAiStatus(PLUS)).effective, "formula");
  const offCtx = await callCtl(Ctl.coachContext, PLUS, { method: "GET", query: { today } });
  check("coach tools → 403 ai_off", [offCtx.status, offCtx.body?.error], [403, "ai_off"]);
  const appleOff = await callCtl(Ctl.submitProposal, PLUS, { body: { today, source: "apple", title: "x", reason: "y", changes: [{ local_date: farDate.local_date, after: { kind: "walk" } }] } });
  check("apple proposal while off → 403 ai_mode_mismatch", [appleOff.status, appleOff.body?.error], [403, "ai_mode_mismatch"]);
  const badSrc = await callCtl(Ctl.submitProposal, PLUS, { body: { today, source: "formula", title: "x", reason: "y", changes: [] } });
  check("clients can't submit as formula/overseer → invalid_source", badSrc.body?.error, "invalid_source");
  await C.setUserAiMode(PLUS, "apple", ADMIN);
  await C.setGlobalCoachSettings({ ai_enabled: false }, ADMIN);
  check("global switch off → formula (global_off)", [(await C.getAiStatus(PLUS)).effective, (await C.getAiStatus(PLUS)).reason], ["formula", "global_off"]);
  await C.setGlobalCoachSettings({ ai_enabled: true }, ADMIN);
  await C.setUserOptOut(PLUS, true);
  check("user opt-out → formula", (await C.getAiStatus(PLUS)).reason, "user_opt_out");
  await C.setUserOptOut(PLUS, false);
  const upl = await C.uploadAiCalls(PLUS, [{ client_call_id: "c1", provider: "apple", kind: "adjust", trigger: "after_run", latency_ms: 1200, input: "in", output: "out", daily_limit_hit: false }, { client_call_id: "c2", provider: "apple", kind: "chat", error: "daily_limit", daily_limit_hit: true }]);
  const upl2 = await C.uploadAiCalls(PLUS, [{ client_call_id: "c1", provider: "apple", kind: "adjust" }]);
  check("Apple call log upload, idempotent on client_call_id", [upl.accepted, upl2.accepted], [2, 0]);
  await rejects("call log: unknown kind refused", () => C.uploadAiCalls(PLUS, [{ provider: "apple", kind: "nope" }]), "invalid_call_log");

  console.log("\n— Anthropic provider (mocked client) + monthly counter stop");
  savedSpend = (await db.query(`SELECT * FROM coach_spend_monthly WHERE month = $1`, [month]))[0] ?? null;
  await db.query(`DELETE FROM coach_spend_monthly WHERE month = $1`, [month]);
  await S.putProfile(AI, PROFILE, today);
  await S.createPlan(AI, { goals: [{ type: "just_improve" }], runs_per_week: 4, difficulty: 2, walk_mode: "built_in" }, today);
  await C.setUserAiMode(AI, "anthropic", ADMIN);
  delete process.env.ANTHROPIC_API_KEY;
  check("anthropic without a key → formula (not configured)", (await C.getAiStatus(AI)).reason, "anthropic_not_configured");
  process.env.ANTHROPIC_API_KEY = "test-key-not-used";
  check("anthropic without consent → formula (consent required)", (await C.getAiStatus(AI)).reason, "anthropic_consent_required");
  await rejects("run without consent → consent_required", () => A.runAnthropicCoach(AI, { today, kind: "checkin" }), "consent_required");
  await C.setAnthropicConsent(AI, true);
  check("consented → anthropic", (await C.getAiStatus(AI)).effective, "anthropic");
  const aiDays = await S.getDays(AI, E.addDays(today, 2), E.addDays(today, 9), today);
  const aiTarget = aiDays.find((d) => d.kind === "easy");
  const requests = [];
  let turn = 0;
  A.setAnthropicClientForTesting({
    messages: {
      async create(params) {
        requests.push(params);
        turn++;
        const usage = { input_tokens: 1000, output_tokens: 500, cache_read_input_tokens: 8000, cache_creation_input_tokens: 0 };
        if (turn === 1)
          return { id: "m1", type: "message", role: "assistant", model: params.model, stop_reason: "tool_use", usage, content: [{ type: "text", text: "Let me check." }, { type: "tool_use", id: "t1", name: "submit_proposal", input: { kind: "adjust", title: "Shorter easy run", reason: "Legs heavy.", changes: [{ local_date: aiTarget.local_date, after: { kind: "easy", distance_mi: Math.max(1, aiTarget.distance_mi - 0.5), work_mi: null, reps: null, rep_mi: null, rep_s: null, recover_s: null, pace_factor: null, strides: null, note: "Easy and short." } }], deviation_reason: null } }] };
        return { id: "m2", type: "message", role: "assistant", model: params.model, stop_reason: "end_turn", usage, content: [{ type: "text", text: "Made Thursday a little shorter." }] };
      },
    },
  });
  const beforeAi = await daysSnapshot(AI);
  const run1 = await A.runAnthropicCoach(AI, { today, kind: "checkin", message: "Legs heavy" });
  check("Haiku 5.5 at effort low for a check-in", [requests[0].model, requests[0].output_config?.effort], ["claude-haiku-5-5", "low"]);
  check("tool_choice auto (forced choice 400s on these models)", requests[0].tool_choice, { type: "auto" });
  check("every tool is strict with additionalProperties: false", requests[0].tools.every((t) => t.strict === true && t.input_schema.additionalProperties === false), true);
  check("shared rules prefix carries cache_control", requests[0].system[0].cache_control, { type: "ephemeral" });
  check("Claude's change is a PENDING proposal, plan unchanged", [run1.proposals.map((p) => [p.source, p.status]), (await daysSnapshot(AI)) === beforeAi], [[["anthropic", "pending"]], true]);
  const call = (await db.query(`SELECT provider, model, tokens_in, tokens_out, tokens_cached, cost_usd FROM coach_ai_calls WHERE id = $1`, [run1.call_id]))[0];
  const expCost = 2 * C.costUsd("claude-haiku-5-5", { input: 1000, output: 500, cacheRead: 8000, cacheWrite: 0 });
  check("call logged with tokens and cost", [call.provider, call.model, call.tokens_in, call.tokens_out, call.tokens_cached, Math.abs(call.cost_usd - expCost) < 1e-9], ["anthropic", "claude-haiku-5-5", 18000, 1000, 16000, true]);
  check("monthly counter advanced by the call's cost", Math.abs((await C.monthSpend(month)).spent_usd - expCost) < 1e-9, true);
  turn = 1; // next call: straight to end_turn
  requests.length = 0;
  await A.runAnthropicCoach(AI, { today, kind: "adjust" });
  check("Sonnet 5.5 at effort medium for an adjustment", [requests[0].model, requests[0].output_config?.effort], ["claude-sonnet-5-5", "medium"]);
  await db.query(`UPDATE coach_spend_monthly SET spent_usd = $2 WHERE month = $1`, [month, C.ANTHROPIC_STOP_USD()]);
  requests.length = 0;
  await rejects("at the $48 stop → ai_unavailable", () => A.runAnthropicCoach(AI, { today, kind: "chat", message: "hi" }), "ai_unavailable");
  check("…and the API was never called", requests.length, 0);
  check("status falls back to the formula plan (budget exhausted)", [(await C.getAiStatus(AI)).effective, (await C.getAiStatus(AI)).reason], ["formula", "anthropic_budget_exhausted"]);
  check("stop threshold is env-configurable", (process.env.COACH_ANTHROPIC_STOP_USD = "60", C.ANTHROPIC_STOP_USD()), 60);
  delete process.env.COACH_ANTHROPIC_STOP_USD;
  await db.query(`UPDATE coach_spend_monthly SET spent_usd = 30, warned_low_at = NULL WHERE month = $1`, [month]);
  await C.addAnthropicSpend(0.01, month);
  check("crossing $25 stamps the warning once", (await db.query(`SELECT warned_low_at IS NOT NULL AS w, warned_high_at IS NULL AS h FROM coach_spend_monthly WHERE month = $1`, [month]))[0], { w: true, h: true });
  A.setAnthropicClientForTesting(null);
  const spendView = await Admin.coachSpend(month);
  check("admin spend view: cap $50, stop $48, warn $25/$40", [spendView.cap_usd, spendView.stop_at_usd, spendView.warn_at_usd], [50, 48, [25, 40]]);

  console.log("\n— AI call log retention (90 days)");
  await db.query(`INSERT INTO coach_ai_calls (user_id, provider, kind, created_at) VALUES ($1, 'apple', 'chat', now() - interval '91 days'), ($1, 'apple', 'chat', now() - interval '89 days')`, [PLUS]);
  const before91 = (await db.query(`SELECT COUNT(*)::int AS n FROM coach_ai_calls WHERE user_id = $1`, [PLUS]))[0].n;
  await C.sweepAiCallLogs();
  const after91 = (await db.query(`SELECT COUNT(*)::int AS n, COUNT(*) FILTER (WHERE created_at < now() - interval '90 days')::int AS old FROM coach_ai_calls WHERE user_id = $1`, [PLUS]))[0];
  check("sweep deletes only rows older than 90 days", [before91 - after91.n, after91.old], [1, 0]);

  console.log("\n— overseer set_plan (admin, own plan, confirmed in chat)");
  await S.putProfile(ADMIN, PROFILE, today);
  await S.createPlan(ADMIN, { goals: [{ type: "distance_time", distance: "5k" }], runs_per_week: 4, difficulty: 3, walk_mode: "built_in" }, today);
  const adDay = (await S.getDays(ADMIN, E.addDays(today, 2), E.addDays(today, 9), today)).find((d) => d.kind !== "walk" && d.kind !== "race");
  const change = { title: "Easy instead", reason: "Soreness 7/10.", changes: [{ local_date: adDay.local_date, day: { kind: "easy", distance_mi: Math.max(1, Math.min(adDay.distance_mi, 4)) } }], deviation_reason: "Overseer review." };
  await rejects("without confirmed_in_chat → refused", () => S.applyOverseerChange(ADMIN, change, { confirmed_in_chat: false, summary: "x", today }), "confirmation_required");
  await rejects("confirmed_in_chat must be literally true", () => S.applyOverseerChange(ADMIN, change, { confirmed_in_chat: "yes", summary: "x", today }), "confirmation_required");
  await rejects("without the summary shown → refused", () => S.applyOverseerChange(ADMIN, change, { confirmed_in_chat: true, summary: "", today }), "summary_required");
  await rejects("another user's plan → own_plan_only", () => S.applyOverseerChange(ADMIN, change, { confirmed_in_chat: true, summary: "x", target_user_id: PLUS, today }), "own_plan_only");
  await rejects("a non-admin → admin_required", () => S.applyOverseerChange(PLUS, { ...change, changes: [{ local_date: farDate.local_date, day: { kind: "walk" } }] }, { confirmed_in_chat: true, summary: "x", today }), "admin_required");
  const set = await S.applyOverseerChange(ADMIN, change, { confirmed_in_chat: true, summary: "Thu tempo → easy 4 mi (you said yes)", today });
  check("confirmed → applied directly, source overseer", [set.proposal.status, set.proposal.source, set.days[0]?.kind], ["applied", "overseer", "easy"]);
  const hist = await db.query(`SELECT event, summary, detail FROM run_plan_history h JOIN run_plans p ON p.plan_id = h.plan_id WHERE p.user_id = $1 AND event = 'overseer_set_plan'`, [ADMIN]);
  check("history records the summary shown and confirmed_in_chat", [hist.length, hist[0]?.summary, hist[0]?.detail?.confirmed_in_chat], [1, "Thu tempo → easy 4 mi (you said yes)", true]);
  await rejects("set_plan still enforces HARD rules", () => S.applyOverseerChange(ADMIN, { changes: [{ local_date: adDay.local_date, day: { kind: "long", distance_mi: 25 } }], deviation_reason: "x" }, { confirmed_in_chat: true, summary: "x", today }), "hard_rule_violation");

  console.log("\n— notification candidates: once per proposal, only for the next run");
  const nr = await S.nextRunFor(PLUS, today);
  const nrDate = nr.date === today ? E.addDays(today, 0) : nr.date;
  const np = await S.createProposal(PLUS, { source: "user", kind: "adjust", title: "Next run shorter", reason: "Test.", changes: [{ local_date: nrDate, spec: nr.day.kind === "walk" ? { kind: "walk" } : { kind: nr.day.kind === "long" ? "long" : "easy", distance_mi: Math.max(1, nr.day.distance_mi) } }], deviation_reason: "Test." }, today);
  const cands = await S.notificationCandidates();
  const mine = cands.find((c) => c.proposal_id === np.id);
  check("pending proposal is a candidate with the learned run hour", [Boolean(mine), mine?.typical_hour], [true, 18]);
  check("claim is once-only", [await S.claimProposalNotification(np.id), await S.claimProposalNotification(np.id)], [true, false]);
  const sentNone = await N.sendRunPlanProposalNotifications(new Date());
  check("no run_plans_v2 device ⇒ nothing sent", sentNone.sent, 0);

  console.log("\n— admin Coach tab reads");
  const usage = await Admin.coachUsage(30);
  check("usage aggregates include the Apple daily-limit hit", usage.apple_limit_hits.reduce((a, r) => a + r.users, 0) >= 1, true);
  const det = await Admin.coachUserDetail(PLUS);
  check("user detail: plan, proposals, calls", [Boolean(det.plan), det.proposals.length > 0, det.calls.length > 0], [true, true, true]);
  const note = await Admin.createReviewNote(ADMIN, { user_id: PLUS, body: "Adjustment ignored the spike margin." }, "overseer");
  check("review note created (source overseer) and listed", [(await Admin.listReviewNotes("open")).some((n) => n.id === note.id), note.source], [true, "overseer"]);
  check("plans list for the overseer", (await Admin.listRunPlansForAdmin()).some((p) => p.user_id === PLUS), true);

  console.log("\n— service: primary + secondary goals, estimates, shoes, effort setting");
  const v26s = Math.round(E.vdotFromRace(E.DISTANCE_MI["5k"], 1560) * 10) / 10;
  await S.putProfile(GOAL, { ...PROFILE, vdot: v26s, longest_run_30d_mi: 8, longest_run_mi: 8, weekly_miles_4w: 18 }, today);
  const G2 = [{ type: "distance_time", distance: "half", target_s: 9439, role: "primary" }, { type: "distance_time", distance: "5k", target_s: 1199, role: "secondary", target_date: null }];
  await rejects("two primaries → invalid_goals", () => S.previewPlan(GOAL, { goals: [{ ...G2[0] }, { ...G2[1], role: "primary" }], runs_per_week: 5, difficulty: 3, walk_mode: "built_in" }, today), "invalid_goals");
  await rejects("secondary date < 14 days after the start → invalid_target_date", () => S.previewPlan(GOAL, { goals: [G2[0], { ...G2[1], target_date: E.addDays(today, 7) }], runs_per_week: 5, difficulty: 3, walk_mode: "built_in" }, today), "invalid_target_date");
  await rejects("plan target_date contradicting the primary's → invalid_target_date", () => S.previewPlan(GOAL, { goals: [{ ...G2[0], target_date: E.addDays(today, 70) }, G2[1]], target_date: E.addDays(today, 80), runs_per_week: 5, difficulty: 3, walk_mode: "built_in" }, today), "invalid_target_date");
  const legacyDate = await S.previewPlan(GOAL, { goals: [{ type: "distance_time", distance: "half" }], target_date: E.addDays(today, 70), runs_per_week: 4, difficulty: 2, walk_mode: "built_in" }, today);
  check("legacy plan-level target_date becomes the primary's", [legacyDate.plan.target_date, legacyDate.plan.goals[0].role, legacyDate.plan.goals[0].target_date], [E.addDays(today, 70), "primary", E.addDays(today, 70)]);
  const gp = await S.createPlan(GOAL, { goals: G2, runs_per_week: 5, difficulty: 3, walk_mode: "built_in", shoe_assignments: { easy: null, walk: "not-a-shoe" } }, today);
  check("served goals carry role, target_date and an estimate", gp.plan.goals.map((g) => [g.role, g.target_date, g.estimate.limiter]), [["primary", null, "endurance"], ["secondary", null, "speed"]]);
  check("primary estimate: ~5–7 weeks, projected date served; secondary checkpoints sub-24, sub-22", [gp.plan.goals[0].estimate.weeks, typeof gp.plan.goals[0].estimate.projected_date, gp.plan.goals[1].estimate.checkpoints.map((c) => c.label)], [[5, 7], "string", ["sub-24 5K", "sub-22 5K"]]);
  check("plan.checkpoints (legacy) derived from the estimates", gp.plan.checkpoints.map((c) => [c.goal_index, c.label]), [[1, "sub-24 5K"], [1, "sub-22 5K"]]);
  check("a sent walk shoe is ignored (no invalid_shoe) and walk is served null", [gp.plan.shoe_assignments.walk, "walk" in gp.plan.shoe_assignments], [null, true]);
  check("5 runs → 2 hard sessions; volume summary served", [gp.plan.hard_sessions_per_week, gp.plan.volume.label, gp.plan.volume.weekly_growth_pct], [2, "Push", 10]);
  const gdays = await S.getDays(GOAL, today, E.addDays(today, 27), today);
  check("the 5K secondary has its session in the plan (for_goal: secondary)", gdays.some((d) => d.spec.for_goal === "secondary"), true);
  check("walk days have no shoe", gdays.filter((d) => d.kind === "walk").every((d) => d.shoe === null), true);
  const eased = await S.updatePlan(GOAL, { difficulty: 1 }, today);
  check("difficulty 4 → 1 keeps the hard-session count", [eased.plan.hard_sessions_per_week, eased.plan.volume.label], [2, "Easy does it"]);
  await S.updatePlan(GOAL, { difficulty: 3 }, today);
  const shoeRow = await db.query(`SELECT shoe_assignments FROM run_plans WHERE user_id = $1 AND status = 'active'`, [GOAL]);
  check("stored assignments never hold walk", "walk" in shoeRow[0].shoe_assignments, false);

  console.log("\n— effort guess: submit, rate, calibrate, signals (proposals only)");
  // Fixture: yesterday is a plan day with a run (so a grade + effort can be posted for it).
  const yday = E.addDays(today, -1);
  const futureHard = (await S.getDays(GOAL, E.addDays(today, 1), E.addDays(today, 13), today)).find((d) => d.kind === "intervals" || d.kind === "tempo");
  await db.query(`UPDATE run_plans SET start_date = $2::date WHERE user_id = $1 AND status = 'active'`, [GOAL, yday]);
  await db.query(
    `INSERT INTO run_plan_days (plan_id, local_date, kind, day, note, source) SELECT plan_id, $2::date, 'easy', $3::jsonb, NULL, 'formula' FROM run_plans WHERE user_id = $1 AND status = 'active'`,
    [GOAL, yday, JSON.stringify(E.buildDay({ kind: "easy", distance_mi: 3 }, bctx))],
  );
  await uploadWorkouts(GOAL, [workout("rp2-g-y", yday, 3)]);
  await rejects("raw_guess out of range → invalid_effort", () => S.submitEffort(GOAL, { local_date: yday, workout_id: "rp2-g-y", raw_guess: 11 }, today), "invalid_effort");
  await rejects("unknown workout → effort_not_found", () => S.getEffort(GOAL, "nope"), "effort_not_found");
  const e1 = await S.submitEffort(GOAL, { local_date: yday, workout_id: "rp2-g-y", raw_guess: 6.4, features: { has_hr: true, avg_hr_zone: 2.1, peak_hr_zone: 3, pace_vs_predicted_pct: 1, duration_s: 1900, walk_fraction: 0 } }, today);
  check("run type from the plan day, guess = raw (no calibration yet)", [e1.effort.run_type, e1.effort.effort_type, e1.effort.raw_guess, e1.effort.guess, e1.effort.guess_label, e1.effort.user_rating], ["easy", "easy", 6.4, 6, "moderate", null]);
  check("all three calibration types listed", e1.calibration.map((c) => [c.effort_type, c.applied]), [["easy", false], ["long", false], ["quality", false]]);
  const daysBeforeRating = await daysSnapshot(GOAL);
  const rt = await S.rateEffort(GOAL, "rp2-g-y", { rating: 8, today }, today);
  check("rated 8 vs guess 6 → effort_fatigue proposal for the next hard day", [rt.effort.user_rating, rt.effort.delta, rt.proposals.map((p) => p.kind), rt.proposals[0]?.changes[0].local_date], [8, 2, ["effort_fatigue"], futureHard?.local_date]);
  check("…pending; the plan days did not change", [rt.proposals[0]?.status, (await daysSnapshot(GOAL)) === daysBeforeRating], ["pending", true]);
  check("re-rating the same run doesn't repeat the proposal", (await S.rateEffort(GOAL, "rp2-g-y", { rating: 8, today }, today)).proposals.length, 0);
  await rejects("rating must be 1–10", () => S.rateEffort(GOAL, "rp2-g-y", { rating: 0 }, today), "invalid_effort");
  const g = await S.submitGrade(GOAL, { local_date: yday, workout_id: "rp2-g-y2", actual_distance_mi: 3, effort: { raw_guess: 5, features: { has_hr: false, duration_s: 1800 } } }, today);
  check("POST /grades with effort → grade + effort for that workout", [typeof g.grade.score, g.effort?.workout_id, g.effort?.guess, g.effort?.reason], ["number", "rp2-g-y2", 5, "No heart rate, so this is from pace and time."]);
  // Easy runs repeatedly rated 2+ easier than guessed → progression proposal.
  const progs = [];
  for (const [i, raw] of [[3, 6], [4, 6], [5, 6]]) {
    await S.submitEffort(GOAL, { local_date: yday, workout_id: `rp2-g-e${i}`, run_type: "easy", raw_guess: raw }, today);
    progs.push(...(await S.rateEffort(GOAL, `rp2-g-e${i}`, { rating: 3 }, today)).proposals);
  }
  check("3 of the last 4 easy runs rated ≥ 2 below → one effort_progression proposal (paces 3% faster)", [progs.map((p) => p.kind), progs[0]?.plan_patch?.pace_factor], [["effort_progression"], 0.97]);
  const cals = await S.effortCalibration(GOAL);
  const easyCal = cals.find((c) => c.effort_type === "easy");
  check("easy calibration now applied and negative", [easyCal.applied, easyCal.offset < -1, easyCal.samples], [true, true, 4]);
  const e6 = await S.submitEffort(GOAL, { local_date: yday, workout_id: "rp2-g-e6", run_type: "easy", raw_guess: 6 }, today);
  check("next easy guess is shifted by the calibration", [e6.effort.offset === easyCal.offset, e6.effort.guess, Math.round(6 + easyCal.offset)], [true, Math.round(6 + easyCal.offset), e6.effort.guess]);
  const listed = await S.listEfforts(GOAL, E.addDays(today, -7), today);
  check("GET /effort lists them newest first with calibration", [listed.efforts.length, listed.calibration.length], [6, 3]);
  const ctxE = await S.getCoachContext(GOAL, today);
  check("coach context carries recent ratings, calibration and signals", [ctxE.effort.recent.length, ctxE.effort.calibration.length, typeof ctxE.effort.signals.fatigue, Boolean(ctxE.goals[0].estimate)], [6, 3, "boolean", true]);
  const adm = await Admin.coachUserDetail(GOAL);
  check("admin drilldown includes ratings + calibration", [adm.efforts.length, adm.effort_calibration.length, adm.efforts.some((e) => e.user_rating === 8)], [6, 3, true]);
  const ce = await callCtl(Ctl.rateEffort, GOAL, { params: { workoutId: "rp2-g-y" }, body: { rating: 7, today } });
  check("POST /effort/:workoutId/rating via the controller", [ce.status, ce.body?.effort?.user_rating], [200, 7]);
  const cg = await callCtl(Ctl.getEffort, GOAL, { params: { workoutId: "nope" }, method: "GET" });
  check("GET /effort/:workoutId unknown → 404 effort_not_found", [cg.status, cg.body?.error], [404, "effort_not_found"]);

  console.log("\n— primary achieved → proposal to promote the secondary");
  const goalDaysBefore = await daysSnapshot(GOAL);
  await uploadWorkouts(GOAL, [workout("rp2-g-half", today, 13.2)]); // 13.2 mi at 10:00/mi ⇒ a 2:11 half, under 2:37
  const pp = await S.runFormulaPass(GOAL, today, "first_open");
  const promo = pp.find((p) => p.kind === "goal_promotion");
  check("goal_promotion proposed (pending), with the new goals in plan_patch", [promo?.status, promo?.plan_patch?.goals?.map((x) => [x.distance, x.role])], ["pending", [["5k", "primary"]]]);
  check("…the plan days did not change", (await daysSnapshot(GOAL)) === goalDaysBefore, true);
  const curA = await S.getCurrent(GOAL, today);
  check("primary estimate shows achieved", [curA.plan.goals[0].estimate.achieved, curA.plan.goals[0].estimate.achieved_by?.workout_id], [true, "rp2-g-half"]);
  check("the pass doesn't propose it twice", (await S.runFormulaPass(GOAL, today, "first_open")).filter((p) => p.kind === "goal_promotion").length, 0);
  const apP = await S.applyProposal(GOAL, promo.id, today);
  const curB = await S.getCurrent(GOAL, today);
  check("apply → the 5K is the primary, its own phases from tomorrow", [apP.proposal.status, curB.plan.goals.map((x) => [x.distance, x.role]), curB.plan.target_date], ["applied", [["5k", "primary"]], null]);
  const after28 = await S.getDays(GOAL, E.addDays(today, 1), E.addDays(today, 27), today);
  check("days after the change window regenerate for the new primary (no secondary sessions)", [after28.length, after28.some((d) => d.spec.for_goal === "secondary")], [27, false]);
  await S.undoProposal(GOAL, promo.id, today);
  const curC = await S.getCurrent(GOAL, today);
  check("undo → both goals back, half primary", curC.plan.goals.map((x) => [x.distance, x.role]), [["half", "primary"], ["5k", "secondary"]]);
}

main()
  .then(async () => {
    if (savedEnv.key === undefined) delete process.env.ANTHROPIC_API_KEY;
    else process.env.ANTHROPIC_API_KEY = savedEnv.key;
    await db.query(`DELETE FROM coach_spend_monthly WHERE month = $1`, [month]);
    if (savedSpend) await db.query(`INSERT INTO coach_spend_monthly (month, spent_usd, calls, warned_low_at, warned_high_at, stopped_at) VALUES ($1, $2, $3, $4, $5, $6)`, [savedSpend.month, savedSpend.spent_usd, savedSpend.calls, savedSpend.warned_low_at, savedSpend.warned_high_at, savedSpend.stopped_at]);
    await db.query(`DELETE FROM app_settings WHERE key = 'coach' AND updated_by = $1`, [ADMIN]);
    await cleanup();
    console.log(failures ? `\n${failures} check(s) FAILED` : "\nAll Run Plans v2 checks passed");
    process.exit(failures ? 1 : 0);
  })
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
