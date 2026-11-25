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

console.log("\n— runs/week + difficulty → hard sessions (rule 3)");
const G5 = settings().goals;
check("Steady, 4 runs, experienced → 1", E.hardSessionsFor(4, 2, "experienced", G5), 1);
check("Push, 4 runs → 2", E.hardSessionsFor(4, 3, "experienced", G5), 2);
check("All in, 6 runs → cap 3", E.hardSessionsFor(6, 4, "experienced", G5), 3);
check("All in, 4 runs → 2 (runs limit)", E.hardSessionsFor(4, 4, "experienced", G5), 2);
check("Easy does it → 0 (strides)", E.hardSessionsFor(5, 1, "experienced", G5), 0);
check("new runner → 0", E.hardSessionsFor(5, 4, "new", G5), 0);
check("novice → max 1", E.hardSessionsFor(5, 4, "novice", G5), 1);
check("1 run/week → 0", E.hardSessionsFor(1, 4, "experienced", G5), 0);
check("calorie goal → ≤ 1 interval session (rule 22)", E.hardSessionsFor(6, 4, "experienced", [{ type: "burn_calories", weekly_minutes: 150 }]), 1);

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

// ─── S. Service (DB) ──────────────────────────────────────────────────────

const PLUS = "rp2-plus";
const FREE = "rp2-free";
const ADMIN = "rp2-admin";
const AI = "rp2-ai";
const ALL = [PLUS, FREE, ADMIN, AI];
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
  for (const id of [PLUS, ADMIN, AI]) {
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
