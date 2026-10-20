/**
 * Run Plans check — the rules engine and the Plus-gated /run-plans API.
 *
 * The engine sets every number in a plan and polices every change from
 * anyone (Flamey, Claude, the user). A broken rule here ships a plan that
 * stacks hard days, drops below the daily mile, or lets a coach blow past the
 * caps — and nobody would notice until someone got hurt or quit. Pinned:
 *
 *   1. Engine (pure): effort → hard days, the 1–7 override + warning at ≥5, no
 *      two hard days back to back while hard_days ≤ 3 (across week edges
 *      too), every day ≥ 1 mi, recovery week every 4th (−20%), growth ≤ the
 *      effort cap, long run ≤ the longest-recent rule, checkpoints (26:00 →
 *      sub-20 ⇒ sub-24 first; keep improving; multiple goals), adaptation,
 *      missed-day moves, check-in mappings, the action caps.
 *   2. Service (seeded workouts, fixed dates): baseline from real runs, plan
 *      creation, derived day status + completion, a missed hard day moving,
 *      harder capped at +2 reps, back-to-back + week-total refusals, set_day
 *      Claude-only and capped, proposals apply / decline / go stale, check-in
 *      → proposal, performance adaptation on read, Claude auto-apply, PATCH
 *      regenerating engine days only, multiple goals + keep-improving
 *      checkpoints, archive.
 *   3. HTTP: plus_required for non-Plus (revoking Claude still allowed),
 *      400s on bad input, the response shape incl. `claude` and `warning`.
 *
 * Users are created AFTER FOUNDING_CUTOFF (else they'd be Founding Runners,
 * Plus for life); Plus comes from a lifetime `plus_purchases` row.
 *
 * Usage (same env as ci-smoke):  DATABASE_URL=... node scripts/run-plans-check.mjs
 */
import express from "express";
import { PostgresService } from "../dist/services/DbService.js";
import { authenticateToken } from "../dist/middleware/auth.js";
import runPlansRoutes from "../dist/routes/runPlansRoutes.js";
import { generateAccessToken } from "../dist/services/tokenService.js";
import { FOUNDING_CUTOFF } from "../dist/services/plusCatalog.js";
import * as E from "../dist/services/runPlans/engine.js";
import * as S from "../dist/services/runPlans/runPlanService.js";

const db = PostgresService.getInstance();

const PLUS = "00000000000000000000000000e0a001"; // seeded runner, fixed dates
const FRESH = "00000000000000000000000000e0a002"; // Plus, no workouts
const FREE = "00000000000000000000000000e0a003"; // not Plus
const HTTP = "00000000000000000000000000e0a004"; // Plus, HTTP round-trips
const ALL = [PLUS, FRESH, FREE, HTTP];

let failures = 0;
function check(label, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  const ok = a === e;
  if (!ok) failures++;
  console.log(`${ok ? "ok  " : "FAIL"}  ${label} → ${a}${ok ? "" : ` (expected ${e})`}`);
}
const truthy = (label, v) => check(label, !!v, true);

async function cleanup() {
  await db.query(`DELETE FROM run_plans WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM plus_purchases WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1)`, [ALL]);
}

let wseq = 0;
async function workout(user, date, miles, paceS, { type = "running", splits = [] } = {}) {
  const id = `rpc-${user.slice(-4)}-${++wseq}`;
  await db.query(
    `INSERT INTO workouts (workout_id, user_id, distance, local_date, date, timezone_offset,
                           workout_type, device_end_date, calories, total_duration)
     VALUES ($1, $2, $3, $4::date, $4::date, 0, $5, $4::date + time '12:00', 100, $6)`,
    [id, user, miles, date, type, miles * paceS],
  );
  for (const [i, s] of splits.entries()) {
    await db.query(
      `INSERT INTO workout_splits (workout_id, split_number, split_duration, split_distance, split_pace)
       VALUES ($1, $2, $3, $4, $5)`,
      [id, i + 1, s.d * s.p, s.d, s.p],
    );
  }
  return id;
}

async function expectError(label, fn, code) {
  try {
    await fn();
    check(label, "no error", code);
    return null;
  } catch (e) {
    check(label, e?.code ?? String(e), code);
    return e;
  }
}

const app = express();
app.use(express.json({ limit: "2mb" }));
app.use(authenticateToken);
app.use("/run-plans", runPlansRoutes);
const server = await new Promise((resolve) => {
  const s = app.listen(0, "127.0.0.1", () => resolve(s));
});
const base = `http://127.0.0.1:${server.address().port}`;
async function call(method, p, userId, body) {
  const token = await generateAccessToken(userId);
  const res = await fetch(base + p, {
    method,
    headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let json = null;
  try {
    json = await res.json();
  } catch {}
  return { status: res.status, json };
}

const hardOf = (days) => days.filter((d) => E.isHard(d.kind));

try {
  await cleanup();
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, username, apple_sub, email, first_name)
       VALUES ($1::text, 'rpc_' || right($1::text, 3), $1::text, $1::text || '@example.com', 'R')`,
      [id],
    );
  }
  const afterCutoff = new Date(Date.parse(FOUNDING_CUTOFF) + 86_400_000).toISOString();
  await db.query(`UPDATE users SET created_at = GREATEST(now(), $2::timestamptz) WHERE user_id = ANY($1)`, [ALL, afterCutoff]);
  for (const id of [PLUS, FRESH, HTTP]) {
    await db.query(
      `INSERT INTO plus_purchases (original_transaction_id, user_id, product_id, transaction_id, kind,
                                   ownership, environment, purchased_at)
       VALUES ($1, $2, 'mad.plus.lifetime', $1, 'lifetime', 'PURCHASED', 'Sandbox', now())`,
      [`rpc-${id}`, id],
    );
  }

  // ── 1. Engine (pure) ────────────────────────────────────────────────
  console.log("\n— engine —");
  check("effort → hard days", [1, 2, 3, 4].map((e) => E.hardDaysFor(e, null)), [1, 2, 3, 3]);
  check("override wins", E.hardDaysFor(1, 6), 6);
  check("warning only at ≥5", [4, 5, 7].map((h) => E.hardDaysWarning(h) != null), [false, true, true]);

  const fitness = E.computeFitness({
    as_of: "2026-11-02", best_mile_s: 450, best_mile_90d_s: 450, best_5k_s: 1560, run_count_90d: 30,
    weekly_miles: [10, 11, 10, 11],
    recent_runs: [{ workout_id: "x", local_date: "2026-10-30", workout_type: "running", distance_mi: 5, duration_s: 2700, moving_s: null, is_indoor: false, splits: [] }],
  });
  check("long-run cap = max(L×1.25, L+1)", E.longRunCap(fitness), 6.2);
  const mk = (over = {}) => ({ goals: [{ type: "5k", target_seconds: 1200 }], effort: 2, hard_days: null, run_daily_mile: true, finish_by: null, start_date: "2026-11-02", baseline: fitness, ...over });
  const ctxFor = (s) => ({ settings: s, fitness, checkpoints: E.computeCheckpoints({ ...s, fitness }) });

  let b2b = 0, belowMile = 0, overCap = 0, wrongCount = 0;
  for (const type of E.GOAL_TYPES) {
    for (const effort of [1, 2, 3, 4]) {
      for (const hd of [null, 1, 2, 3, 4, 5, 6, 7]) {
        const s = mk({ goals: [{ type }], effort, hard_days: hd });
        const ctx = ctxFor(s);
        const H = E.hardDaysFor(effort, hd);
        let prevSunHard = false;
        for (let w = 0; w < 10; w++) {
          const week = E.generateWeek(ctx, E.addDays("2026-11-02", 7 * w));
          if (hardOf(week.map((d) => d.day)).length !== H) wrongCount++;
          for (let i = 0; i < 7; i++) {
            const d = week[i].day;
            if (d.distance_mi < 1) belowMile++;
            if (d.distance_mi > E.longRunCap(fitness) + 1e-9) overCap++;
            const prevHard = i === 0 ? prevSunHard : E.isHard(week[i - 1].day.kind);
            if (H <= 3 && prevHard && E.isHard(d.kind)) b2b++;
          }
          prevSunHard = E.isHard(week[6].day.kind);
        }
      }
    }
  }
  check("every week has exactly hard_days hard days (all goals × efforts × overrides)", wrongCount, 0);
  check("no back-to-back hard days while hard_days ≤ 3 (incl. Sun→Mon)", b2b, 0);
  check("every day ≥ 1 mi", belowMile, 0);
  check("no day over the long-run cap", overCap, 0);

  const s5 = mk();
  check("recovery weeks are every 4th", [0, 1, 2, 3, 4, 7].map(E.isRecoveryWeek), [false, false, false, true, false, true]);
  check("recovery week = 80% of the week before", E.weekVolume(s5, 3), E.round2(E.weekVolume(s5, 2) * 0.8));
  check("week after recovery climbs past it", E.weekVolume(s5, 4) > E.weekVolume(s5, 2), true);
  check("volume starts at baseline (min 7)", [E.weekVolume(s5, 0), E.weekVolume(mk({ baseline: { ...fitness, weekly_miles_4w: 2 } }), 0)], [10.5, 7]);
  let growthOk = true;
  for (const effort of [1, 2, 3, 4]) {
    const s = mk({ effort });
    for (let w = 1; w < 12; w++) {
      if (E.isRecoveryWeek(w) || E.isRecoveryWeek(w - 1)) continue;
      if (E.weekVolume(s, w) > E.weekVolume(s, w - 1) * (1 + E.EFFORT[effort].growth) + 0.011) growthOk = false;
    }
  }
  check("weekly growth ≤ the effort cap (5/7/8/10%)", growthOk, true);
  const strides = E.generateWeek(ctxFor(mk({ effort: 4, baseline: { ...fitness, weekly_miles_4w: 20 } })), "2026-11-02").some((d) => d.day.kind === "easy" && d.day.segments.some((s) => s.kind === "work"));
  check("effort 4 adds strides on easy days", strides, true);

  // Checkpoints.
  const at26 = { ...fitness, best_5k_s: 1560, current_5k_s: 1560 };
  const cps = E.computeCheckpoints({ goals: [{ type: "5k", target_seconds: 1200 }], effort: 2, start_date: "2026-11-02", finish_by: null, fitness: at26, baseline: at26 });
  check("26:00 → sub-20: sub-24 first, then sub-22, then the goal", cps.map((c) => [c.target_seconds, c.is_goal]), [[1440, false], [1320, false], [1200, true]]);
  const multi = E.computeCheckpoints({ goals: [{ type: "10k" }, { type: "faster_mile", target_seconds: 400 }, { type: "more_miles", distance_mi: 20 }], effort: 3, start_date: "2026-11-02", finish_by: null, fitness, baseline: fitness });
  const keep = multi.filter((c) => c.goal_type === "10k");
  check("no target ⇒ three keep-improving checkpoints, each faster", [keep.length, keep.every((c, i) => !c.is_goal && c.target_seconds < (i ? keep[i - 1].target_seconds : fitness.predicted["10k_s"]))], [3, true]);
  check("multiple goals each get checkpoints", [...new Set(multi.map((c) => c.goal_type))], ["10k", "faster_mile", "more_miles"]);
  check("more_miles ends at its weekly target", multi.filter((c) => c.goal_type === "more_miles").at(-1)?.weekly_mi, 20);
  const reached = E.computeCheckpoints({ goals: [{ type: "5k", target_seconds: 1700 }], effort: 2, start_date: "2026-11-02", finish_by: null, fitness: at26, baseline: at26 });
  check("goal already beaten ⇒ reached goal + keep improving", reached.map((c) => [c.is_goal, c.reached]), [[true, true], [false, false], [false, false], [false, false]]);
  const fb = E.computeCheckpoints({ goals: [{ type: "5k", target_seconds: 1200 }], effort: 2, start_date: "2026-11-02", finish_by: "2027-05-02", fitness: at26, baseline: at26 });
  check("finish_by spreads checkpoints up to the finish line", [fb.at(-1).eta, fb[0].eta < fb[1].eta && fb[1].eta < fb.at(-1).eta], ["2027-05-02", true]);

  // Status.
  const comp = (mi) => ({ workout_ids: ["w"], distance_mi: mi, avg_pace_s: 600, walk_fraction: 0 });
  check("status: done ≥90% (streak ≥95%), partial, missed, today, planned", [
    E.dayStatus("easy", 3, "2026-11-02", "2026-11-03", comp(2.7)),
    E.dayStatus("easy", 3, "2026-11-02", "2026-11-03", comp(2.6)),
    E.dayStatus("streak", 1, "2026-11-02", "2026-11-03", comp(0.94)),
    E.dayStatus("streak", 1, "2026-11-02", "2026-11-03", comp(0.95)),
    E.dayStatus("easy", 3, "2026-11-02", "2026-11-03", null),
    E.dayStatus("easy", 3, "2026-11-03", "2026-11-03", comp(1)),
    E.dayStatus("easy", 3, "2026-11-04", "2026-11-03", null),
  ], ["done", "partial", "partial", "done", "missed", "today", "planned"]);

  // Adaptation.
  const segs = [{ kind: "work", distance_mi: 3, target_pace_s: 500 }];
  const sess = (date, pace, wf = 0) => ({ local_date: date, segments: segs, status: "done", completed: { workout_ids: ["w"], distance_mi: 3, avg_pace_s: pace, walk_fraction: wf } });
  check("> 5% slower ⇒ ease next hard", E.computeAdaptation([sess("2026-11-01", 530)]).ease?.after, "2026-11-01");
  check("walk-heavy ⇒ ease", E.computeAdaptation([sess("2026-11-01", 500, 0.4)]).ease != null, true);
  check("on target ⇒ nothing", E.computeAdaptation([sess("2026-11-01", 510)]), { ease: null, tighten: null });
  check("two ≥3% faster ⇒ tighten", E.computeAdaptation([sess("2026-11-01", 480), sess("2026-10-29", 482)]).tighten?.factor, E.TIGHTEN_PACE);
  check("one fast session isn't enough", E.computeAdaptation([sess("2026-11-01", 480), sess("2026-10-29", 500)]).tighten, null);

  // Check-in mappings.
  check("check-in mapping", [
    E.checkinAction("tired", false)?.action,
    E.checkinAction("sore", false)?.action,
    E.checkinAction("sore", false)?.params.soften_next_hard,
    E.checkinAction("great", false)?.action,
    E.checkinAction("normal", false),
    E.checkinAction("normal", true)?.action,
  ], ["easier", "just_mile", true, "harder", null, "just_mile"]);

  // Missed moves (week Mon 11-02: Wed intervals, Sun long; today Thu).
  const week = E.generateWeek(ctxFor(s5), "2026-11-02").map((d) => ({ ...d.day, local_date: d.local_date, source: "engine", original: null, moved_from: null, status: d.local_date < "2026-11-05" ? "missed" : d.local_date === "2026-11-05" ? "today" : "planned" }));
  check("layout for 5K / effort 2: Wed intervals, Sun long", hardOf(week).map((d) => [E.weekdayName(d.local_date), d.kind]), [["Wed", "intervals"], ["Sun", "long"]]);
  check("missed Wed intervals → Thu", E.planMissedMoves(week, "2026-11-05", 2), [{ from: "2026-11-04", to: "2026-11-05" }]);
  const satToday = week.map((d) => ({ ...d, status: d.local_date < "2026-11-07" ? "missed" : d.status }));
  check("no room (only Sat, next to Sun long) ⇒ dropped", E.planMissedMoves(satToday, "2026-11-07", 2), []);
  check("hard_days > 3 ⇒ spacing doesn't block the move", E.planMissedMoves(satToday, "2026-11-07", 5), [{ from: "2026-11-04", to: "2026-11-07" }]);

  // Action caps on the pure engine.
  const actx = (days, over = {}) => ({ today: "2026-11-03", days, hard_days: 2, run_daily_mile: true, effort: 2, long_cap: 6.2, paces: E.pacesFor(1560, 2), source: "flamey", ...over });
  const live = week.map((d) => ({ ...d, status: d.local_date > "2026-11-03" ? "planned" : d.local_date === "2026-11-03" ? "today" : "done" }));
  const wed = live.find((d) => d.local_date === "2026-11-04");
  const repsOf = (d) => d.segments.find((s) => s.kind === "work")?.reps;
  const harder = E.planAction(actx(live), "harder", { local_date: "2026-11-04", reps: 5 });
  check("harder: at most +2 reps, with cap_note", [repsOf(harder.changes[0].after) - repsOf(wed), harder.cap_note != null], [2, true]);
  const sun = live.find((d) => d.local_date === "2026-11-08");
  const harderLong = E.planAction(actx(live), "harder", { local_date: "2026-11-08", percent: 50 });
  check("harder: at most +20% distance (or the long cap), with cap_note", [harderLong.changes[0].after.distance_mi <= Math.min(E.round2(sun.distance_mi * 1.2), 6.2), harderLong.cap_note != null], [true, true]);
  let err = null;
  try { E.planAction(actx(live), "move", { from: "2026-11-04", to: "2026-11-07" }); } catch (e) { err = e; }
  check("move next to Sun long ⇒ refused (back to back)", err instanceof E.ActionError, true);
  const twoWeeks = [...live, ...E.generateWeek(ctxFor(s5), "2026-11-09").map((d) => ({ ...d.day, local_date: d.local_date, source: "engine", original: null, moved_from: null, status: "planned" }))];
  err = null;
  try { E.planAction(actx(twoWeeks, { hard_days: 5 }), "move", { from: "2026-11-08", to: "2026-11-09" }); } catch (e) { err = e; }
  check("swap across weeks past planned total + 0.5 ⇒ refused", [err instanceof E.ActionError, /planned total/.test(err?.cap_note ?? "")], [true, true]);
  const swap = E.planAction(actx(live), "swap_hard_today", {});
  check("swap_hard_today: today ↔ next hard day this week", swap.changes.map((c) => [c.local_date, c.after.kind]), [["2026-11-03", "intervals"], ["2026-11-04", live.find((d) => d.local_date === "2026-11-03").kind]]);
  const just = E.planAction(actx(live), "just_mile", { local_date: "2026-11-04" });
  check("just_mile → a 1 mi streak day", [just.changes[0].after.kind, just.changes[0].after.distance_mi], ["streak", 1]);
  err = null;
  try { E.planAction(actx(live), "shorter", { local_date: "2026-11-02" }); } catch (e) { err = e; }
  check("past days can't change", err?.cap_note, "That day is already in the past.");
  const streakDay = live.find((d) => d.kind === "streak" && d.local_date >= "2026-11-03");
  err = null;
  try { E.planAction(actx(live), "shorter", { local_date: streakDay.local_date }); } catch (e) { err = e; }
  check("never below a mile (shorter on a streak day is refused)", /at least a mile/.test(err?.cap_note ?? ""), true);
  err = null;
  try { E.planAction(actx(live), "set_day", { local_date: "2026-11-06", kind: "easy", distance_mi: 3 }); } catch (e) { err = e; }
  check("set_day is Claude only", err?.cap_note, "Only Claude can set a whole day.");
  const setDay = E.planAction(actx(live, { source: "claude" }), "set_day", { local_date: "2026-11-06", kind: "easy", distance_mi: 40 });
  const fri = live.find((d) => d.local_date === "2026-11-06");
  check("set_day (Claude) is capped too", [setDay.changes[0].after.distance_mi <= Math.max(fri.distance_mi * 1.2, fri.distance_mi + 0.5) + 1e-9, setDay.cap_note != null], [true, true]);

  // ── 2. Service (seeded workouts, fixed dates) ──────────────────────
  console.log("\n— service —");
  const T0 = "2026-11-02"; // Monday
  const d = (n) => E.addDays(T0, n);
  // 8 weeks of 4 mi every other day at 9:00, one 3.2 mi effort at 8:00 (a
  // 25:35 5K once normalized), a 7 mi long run, one run with a 7:30 mile split.
  for (let n = 56; n >= 2; n -= 2) await workout(PLUS, d(-n), 4, 540);
  await workout(PLUS, d(-9), 3.2, 480);
  await workout(PLUS, d(-7), 7, 570);
  await workout(PLUS, d(-5), 2, 500, { splits: [{ d: 1, p: 450 }, { d: 1, p: 550 }] });
  await workout(PLUS, d(-3), 2, 600, { type: "walking" });

  const fit = await S.getFitness(PLUS, T0);
  check("baseline from real runs: best mile split, longest 8w, 5K-sourced", [fit.best_mile_s, fit.longest_run_8w_mi, fit.current_source], [450, 7, "5k"]);
  check("best 5K effort ≈ 3.2 mi @ 8:00 normalized", Math.abs(fit.best_5k_s - Math.round(3.2 * 480 * (3.10686 / 3.2) ** 1.06)) <= 1, true);
  check("weekly_miles is the 4-week mean (a number)", [typeof fit.weekly_miles, fit.weekly_miles], ["number", E.round2(fit.weekly_miles_by_week.reduce((a, b) => a + b, 0) / 4)]);
  check("best mile date + indoor flag", [fit.best_mile_date, fit.best_mile_indoor, fit.longest_run_mi], [d(-5), null, 7]);
  const freshFit = await S.getFitness(FRESH, T0);
  check("no runs ⇒ default fitness", [freshFit.current_source, freshFit.longest_run_8w_mi, freshFit.weekly_miles_4w], ["default", 0, 0]);

  let cur = await S.createPlan(PLUS, { goals: [{ type: "5k", target_seconds: 1200 }], effort: 2, run_daily_mile: true }, T0);
  console.log("      week:", cur.days.slice(0, 7).map((x) => `${E.weekdayName(x.local_date)} ${x.title}`).join(" · "));
  check("plan created: 14 days (this + next week), effort 2 ⇒ 2 hard days", [cur.days.length, cur.plan.hard_days_effective, hardOf(cur.days.slice(0, 7)).length], [14, 2, 2]);
  check("plan baseline is the fitness snapshot", cur.plan.baseline.best_5k_s, fit.best_5k_s);
  check("plan carries claude status + no warning", [cur.claude, cur.warning], [{ connected: false, last_used_at: null }, null]);
  check("checkpoints from a 24:49 5K toward sub-20: ≤ 8% steps", cur.checkpoints.map((c) => c.label), ["Sub-23:00 5K", "Sub-21:00 5K", "Sub-20:00 5K"]);
  check("every served day ≥ 1 mi; today is a Day", [cur.days.every((x) => x.distance_mi >= 1), cur.today?.local_date, cur.today?.status], [true, T0, "today"]);
  check("Wed intervals, Sun long", hardOf(cur.days.slice(0, 7)).map((x) => [x.local_date, x.kind]), [[d(2), "intervals"], [d(6), "long"]]);
  const again = await S.getCurrentPlan(PLUS, T0);
  check("re-reading doesn't re-materialize", (await db.query(`SELECT count(*)::int AS n FROM run_plan_days rd JOIN run_plans rp USING (plan_id) WHERE rp.user_id = $1`, [PLUS]))[0].n, 14);
  void again;

  // Day status from workouts.
  const monId = await workout(PLUS, T0, 1.0, 560);
  await workout(PLUS, d(1), 0.4, 900, { type: "walking" });
  cur = await S.getCurrentPlan(PLUS, d(1));
  const mon = cur.days.find((x) => x.local_date === T0);
  check("Mon streak mile run ⇒ done, with completion", [mon.status, mon.completed?.workout_ids, mon.completed?.distance_mi, mon.completed?.avg_pace_s], ["done", [monId], 1, 560]);
  cur = await S.getCurrentPlan(PLUS, d(3));
  const tue = cur.days.find((x) => x.local_date === d(1));
  check("Tue 0.4 mi walk ⇒ partial, walk_fraction 1", [tue.status, tue.completed?.walk_fraction], ["partial", 1]);

  // Missed Wed intervals → Thu.
  const wedS = cur.days.find((x) => x.local_date === d(2));
  const thu = cur.days.find((x) => x.local_date === d(3));
  check("missed Wed intervals moved to Thu", [wedS.status, thu.kind, thu.moved, wedS.note], ["missed", "intervals", true, "Missed. Moved to Thu."]);
  cur = await S.getCurrentPlan(PLUS, d(3));
  check("the move happens once", cur.days.filter((x) => x.moved).length, 1);

  // Harder: +2 reps max.
  const thuReps = thu.segments.find((s) => s.kind === "work").reps;
  let prop = await S.createProposal(PLUS, d(3), { action: "harder", params: { reps: 6 } }, "flamey");
  check("harder proposal: pending, +2 reps, cap_note", [prop.status, prop.changes[0].after.segments.find((s) => s.kind === "work").reps - thuReps, prop.cap_note != null, prop.source], ["pending", 2, true, "flamey"]);
  cur = await S.applyProposal(PLUS, prop.id, d(3));
  const thu2 = cur.days.find((x) => x.local_date === d(3));
  check("applied: Thu has the extra reps, source flamey", [thu2.segments.find((s) => s.kind === "work").reps, thu2.source], [thuReps + 2, "flamey"]);
  const orig = await db.query(`SELECT rd.original FROM run_plan_days rd JOIN run_plans rp USING (plan_id) WHERE rp.user_id = $1 AND rd.local_date = $2`, [PLUS, d(3)]);
  check("original keeps the engine's pre-move Thu (not the moved intervals)", ["streak", "easy"].includes(orig[0].original?.kind), true);
  await expectError("applying twice ⇒ proposal_not_pending", () => S.applyProposal(PLUS, prop.id, d(3)), "proposal_not_pending");

  // Refusals.
  const e1 = await expectError("move Thu intervals to Sat (next to Sun long) ⇒ refused", () => S.createProposal(PLUS, d(3), { action: "move", params: { from: d(3), to: d(5) } }, "flamey"), "action_not_possible");
  truthy("refusal carries a cap_note", e1?.extra?.cap_note);
  const e2 = await expectError("Sun long → next Mon (week total + 0.5 rule) ⇒ refused", () => S.createProposal(PLUS, d(3), { action: "move", params: { from: d(6), to: d(7) } }, "flamey"), "action_not_possible");
  check("…because of the week total", /planned total/.test(e2?.extra?.cap_note ?? ""), true);
  await expectError("set_day from Flamey ⇒ refused", () => S.createProposal(PLUS, d(3), { action: "set_day", params: { local_date: d(4), kind: "easy", distance_mi: 3 } }, "flamey"), "action_not_possible");

  // Decline + stale.
  check("layout: Sat easy, next Mon (after the long run) streak", [cur.days.find((x) => x.local_date === d(5)).kind, cur.days.find((x) => x.local_date === d(7)).kind], ["easy", "streak"]);
  await expectError("easier on a streak day ⇒ refused", () => S.createProposal(PLUS, d(3), { action: "easier", params: { local_date: d(7) } }, "flamey"), "action_not_possible");
  prop = await S.createProposal(PLUS, d(3), { action: "easier", params: { local_date: d(5) }, summary: "Ease Saturday" }, "flamey");
  check("custom summary kept", prop.summary, "Ease Saturday");
  check("decline ⇒ ok", await S.declineProposal(PLUS, prop.id), { ok: true });
  check("declined shows in the list", (await S.listProposals(PLUS, { status: "declined" })).map((p) => p.id), [prop.id]);
  await expectError("apply a declined proposal ⇒ 409", () => S.applyProposal(PLUS, prop.id, d(3)), "proposal_not_pending");
  await expectError("someone else can't decline it", () => S.declineProposal(FRESH, prop.id), "proposal_not_found");
  const stale = await S.createProposal(PLUS, d(3), { action: "shorter", params: { local_date: d(5) } }, "flamey");
  const adj = await S.adjustDay(PLUS, d(5), "just_mile", d(3));
  check("adjust applies at once, source user", [adj.days.find((x) => x.local_date === d(5)).kind, adj.days.find((x) => x.local_date === d(5)).source], ["streak", "user"]);
  check("…and the now-stale proposal expired on read", adj.pending_proposals.some((p) => p.id === stale.id), false);
  await expectError("applying the stale proposal ⇒ 409", () => S.applyProposal(PLUS, stale.id, d(3)), "proposal_not_pending");
  check("stale proposal status", (await S.listProposals(PLUS, { status: "expired" })).some((p) => p.id === stale.id), true);

  // Check-ins (today Thu = intervals, next hard = Sun long).
  const ci = async (body) => (await S.recordCheckin(PLUS, d(3), body)).proposal;
  const tired = await ci({ feeling: "tired" });
  check("tired → easier today", [tired?.action, tired?.changes[0]?.local_date, tired?.changes[0]?.after.kind], ["easier", d(3), "easy"]);
  const sore = await ci({ feeling: "sore", message: "calves" });
  check("sore → just_mile today + soften next hard (Sun)", [sore?.action, sore?.changes.map((c) => [c.local_date, c.after.kind])], ["just_mile", [[d(3), "streak"], [d(6), "long"]]]);
  check("…softened = shorter", sore.changes[1].after.distance_mi < sore.changes[1].before.distance_mi, true);
  const great = await ci({ feeling: "great" });
  check("great → harder", great?.action, "harder");
  check("normal → no proposal", await ci({ feeling: "normal" }), null);
  const pain = await ci({ feeling: "normal", pain_flag: true });
  check("pain → just_mile", pain?.action, "just_mile");
  check("check-ins are listed", (await S.listCheckins(PLUS, T0, d(6))).length, 5);
  // Decline them so they don't linger.
  for (const p of [tired, sore, great, pain]) await S.declineProposal(PLUS, p.id);

  // Performance adaptation: Thu intervals run 10% slow ⇒ Sun long eased on read.
  const thuNow = (await S.getCurrentPlan(PLUS, d(3))).days.find((x) => x.local_date === d(3));
  const exp = E.expectedAvgPace(thuNow.segments);
  await workout(PLUS, d(3), thuNow.distance_mi, Math.round(exp * 1.1));
  cur = await S.getCurrentPlan(PLUS, d(4));
  const sunS = cur.days.find((x) => x.local_date === d(6));
  const sunStored = await db.query(`SELECT distance_mi::float8 AS mi FROM run_plan_days rd JOIN run_plans rp USING (plan_id) WHERE rp.user_id = $1 AND rd.local_date = $2`, [PLUS, d(6)]);
  check("Thu done (slow)", cur.days.find((x) => x.local_date === d(3)).status, "done");
  check("next hard (Sun long) eased on read: −10%, note, adapted", [sunS.adapted, sunS.distance_mi < sunStored[0].mi, /slower than target/.test(sunS.note ?? "")], [true, true, true]);
  check("adaptation is read-only (stored day untouched)", sunStored[0].mi > sunS.distance_mi, true);

  // Claude auto-apply.
  cur = await S.updatePlan(PLUS, { claude_auto_apply: true }, d(4));
  check("claude_auto_apply on", cur.plan.claude_auto_apply, true);
  const cl = await S.createProposal(PLUS, d(4), { action: "easier", params: { local_date: d(8) }, rationale: "Long week" }, "claude");
  check("Claude proposal auto-applied", [cl.status, cl.source], ["applied", "claude"]);
  cur = await S.getCurrentPlan(PLUS, d(4));
  check("…day source claude", cur.days.find((x) => x.local_date === d(8)).source, "claude");

  // PATCH regenerates engine-owned future days only.
  const userDay = cur.days.find((x) => x.local_date === d(5));
  cur = await S.updatePlan(PLUS, { effort: 3 }, d(4));
  const nextWeek = cur.days.filter((x) => x.local_date >= d(7));
  check("effort 3 ⇒ 3 hard days; user + Claude days kept", [cur.plan.hard_days_effective, cur.days.find((x) => x.local_date === d(5)).source, cur.days.find((x) => x.local_date === d(8)).source], [3, userDay.source, "claude"]);
  check("next week regenerated: Thu tempo, Sun long", [nextWeek.find((x) => x.local_date === d(10)).kind, nextWeek.find((x) => x.local_date === d(13)).kind], ["tempo", "long"]);
  cur = await S.updatePlan(PLUS, { hard_days: 5 }, d(4));
  check("override 5 ⇒ warning", [cur.plan.hard_days_effective, cur.warning != null], [5, true]);
  cur = await S.updatePlan(PLUS, { hard_days: null }, d(4));
  check("override cleared ⇒ from effort, no warning", [cur.plan.hard_days_effective, cur.warning], [3, null]);

  // Multiple goals + keep improving.
  cur = await S.updatePlan(PLUS, { goals: [{ type: "5k" }, { type: "faster_mile", target_seconds: 400 }] }, d(4));
  const k5 = cur.checkpoints.filter((c) => c.goal_type === "5k");
  check("5K without target ⇒ 3 keep-improving checkpoints below today's best", [k5.length, k5.every((c) => !c.is_goal && !c.reached && c.target_seconds < fit.best_5k_s)], [3, true]);
  check("faster mile goal checkpoint", cur.checkpoints.filter((c) => c.goal_type === "faster_mile").at(-1)?.target_seconds, 400);

  const range = await S.getPlanDays(PLUS, T0, d(13), d(4));
  check("getPlanDays serves the range", range.length, 14);
  const runs = await S.getRuns(PLUS, d(-5), d(-5));
  check("getRuns: splits, pace, walk fraction", [runs.length, runs[0]?.splits.length, runs[0]?.avg_pace_s, runs[0]?.walk_fraction], [1, 2, 500, 0]);
  await expectError("getRuns range capped", () => S.getRuns(PLUS, "2025-01-01", "2026-01-01"), "range_too_large");

  check("archive", await S.archivePlan(PLUS), { ok: true, archived: true });
  cur = await S.getCurrentPlan(PLUS, d(4));
  check("no plan after archive", [cur.plan, cur.days.length, cur.recent_runs.length > 0], [null, 0, true]);
  await expectError("no plan ⇒ check-in 404", () => S.recordCheckin(PLUS, d(4), { feeling: "tired" }), "no_active_plan");

  // ── 3. HTTP ─────────────────────────────────────────────────────────
  console.log("\n— http —");
  const today = new Date().toISOString().slice(0, 10);
  for (const [m, p] of [["GET", `/run-plans/current?today=${today}`], ["GET", "/run-plans/fitness"], ["POST", "/run-plans"], ["POST", "/run-plans/checkins"]]) {
    const r = await call(m, p, FREE, m === "POST" ? { today } : undefined);
    check(`non-Plus ${m} ${p.split("?")[0]} ⇒ 403 plus_required`, [r.status, r.json], [403, { error: "plus_required" }]);
  }
  const rv = await call("DELETE", "/run-plans/claude", FREE);
  check("revoking Claude works without Plus", [rv.status, rv.json?.ok], [200, true]);

  let r = await call("GET", "/run-plans/fitness", HTTP);
  check("GET /fitness without a plan", [r.status, typeof r.json?.current_5k_s], [200, "number"]);
  r = await call("GET", "/run-plans/current", HTTP);
  check("missing ?today ⇒ 400", [r.status, r.json?.error], [400, "invalid_today"]);
  r = await call("GET", "/run-plans/current?today=2020-01-01", HTTP);
  check("far-off today ⇒ 400", r.status, 400);
  r = await call("GET", `/run-plans/current?today=${today}`, HTTP);
  check("no plan ⇒ plan null + claude", [r.status, r.json?.plan, r.json?.claude], [200, null, { connected: false, last_used_at: null }]);
  const good = { goals: [{ type: "10k" }], effort: 2, run_daily_mile: true, today };
  for (const [label, body, code] of [
    ["bad effort", { ...good, effort: 5 }, "invalid_effort"],
    ["bad goals", { ...good, goals: [{ type: "ultra" }] }, "invalid_goals"],
    ["empty goals", { ...good, goals: [] }, "invalid_goals"],
    ["hard_days 8", { ...good, hard_days: 8 }, "invalid_hard_days"],
    ["hard_days 0", { ...good, hard_days: 0 }, "invalid_hard_days"],
    ["finish_by in the past", { ...good, finish_by: "2020-01-01" }, "invalid_finish_by"],
    ["target on more_miles", { ...good, goals: [{ type: "more_miles", target_seconds: 100 }] }, "invalid_goals"],
  ]) {
    r = await call("POST", "/run-plans", HTTP, body);
    check(`POST /run-plans ${label} ⇒ 400`, [r.status, r.json?.error], [400, code]);
  }
  r = await call("POST", "/run-plans", HTTP, { ...good, hard_days: 7, goals: [{ type: "10k" }, { type: "more_miles", distance_mi: 25 }] });
  check("hard_days 7 accepted, with warning", [r.status, r.json?.plan?.hard_days_effective, typeof r.json?.warning], [200, 7, "string"]);
  check("response shape", Object.keys(r.json ?? {}).sort(), ["checkpoints", "claude", "days", "latest_checkin", "pending_proposals", "plan", "recent_runs", "today", "today_date", "warning", "week_done_mi", "week_total_mi"]);
  check("plan.week is 1-based; checkpoints carry by_date", [r.json?.plan?.week, r.json?.checkpoints?.every((c) => "by_date" in c && "goal_type" in c && "label" in c && "target_seconds" in c)], [1, true]);
  r = await call("POST", "/run-plans", HTTP, good);
  check("POST again archives the old plan", [r.status, (await db.query(`SELECT count(*)::int AS n FROM run_plans WHERE user_id = $1 AND status = 'archived'`, [HTTP]))[0].n], [200, 1]);
  const dayKeys = Object.keys(r.json.days[0]).sort();
  check("Day shape", dayKeys, ["adapted", "completed", "distance_mi", "kind", "local_date", "moved", "note", "segments", "source", "status", "target_pace_s", "title"]);
  r = await call("POST", "/run-plans/checkins", HTTP, { today });
  check("empty check-in ⇒ 400", [r.status, r.json?.error], [400, "empty_checkin"]);
  r = await call("POST", "/run-plans/checkins", HTTP, { today, feeling: "meh" });
  check("bad feeling ⇒ 400", r.json?.error, "invalid_feeling");
  r = await call("POST", "/run-plans/checkins", HTTP, { today, feeling: "tired", message: "long day" });
  check("check-in ⇒ { checkin, proposal }", [r.status, r.json?.checkin?.feeling, r.json?.proposal?.action ?? "none"].slice(0, 2), [200, "tired"]);
  r = await call("POST", "/run-plans/checkins", HTTP, { today, message: "just saying hi" });
  check("message-only check-in ⇒ feeling null, proposal null", [r.status, r.json?.checkin?.feeling, r.json?.proposal], [200, null, null]);
  r = await call("GET", `/run-plans/current?today=${today}`, HTTP);
  check("latest_checkin is today's newest", r.json?.latest_checkin?.message, "just saying hi");
  const fitHttp = await call("GET", "/run-plans/fitness", HTTP);
  check("fitness: numbers are JSON numbers", ["best_mile_s", "best_5k_s", "easy_pace_s"].every((k) => fitHttp.json[k] === null) && typeof fitHttp.json.weekly_miles === "number" && typeof fitHttp.json.longest_run_mi === "number" && typeof fitHttp.json.walk_heavy === "boolean", true);
  r = await call("POST", "/run-plans/proposals", HTTP, { today, action: "fly" });
  check("unknown action ⇒ 400", [r.status, r.json?.error], [400, "invalid_action"]);
  r = await call("POST", "/run-plans/proposals", HTTP, { today, action: "set_day", params: { local_date: today, kind: "easy", distance_mi: 2 } });
  check("set_day from the app ⇒ 422 with cap_note", [r.status, r.json?.error, typeof r.json?.cap_note], [422, "action_not_possible", "string"]);
  const nonStreak = (await call("GET", `/run-plans/current?today=${today}`, HTTP)).json.days.find((x) => x.local_date > today && x.kind !== "streak");
  r = await call("POST", "/run-plans/proposals", HTTP, { today, action: "just_mile", params: { local_date: nonStreak.local_date } });
  const pr = r.json?.proposal;
  check("proposal created, wrapped as { proposal } (pending, flamey)", [r.status, pr?.status, pr?.source], [200, "pending", "flamey"]);
  if (pr) {
    r = await call("POST", `/run-plans/proposals/${pr.id}/apply`, HTTP, { today });
    check("apply ⇒ current", [r.status, Array.isArray(r.json?.days)], [200, true]);
  }
  r = await call("POST", "/run-plans/proposals/not-a-uuid/decline", HTTP, {});
  check("bad proposal id ⇒ 404", r.status, 404);
  r = await call("POST", "/run-plans/proposals/00000000-0000-4000-8000-000000000000/decline", HTTP, {});
  check("unknown proposal ⇒ 404", [r.status, r.json?.error], [404, "proposal_not_found"]);
  r = await call("POST", `/run-plans/days/${today}/adjust`, HTTP, { today, action: "harder" });
  check("adjust only takes easier|shorter|just_mile", [r.status, r.json?.error], [400, "invalid_action"]);
  r = await call("POST", `/run-plans/days/not-a-date/adjust`, HTTP, { today, action: "easier" });
  check("adjust bad date ⇒ 400", r.json?.error, "invalid_date");
  const cur2 = (await call("GET", `/run-plans/current?today=${today}`, HTTP)).json;
  const target = cur2.days.find((x) => x.local_date >= today && x.kind !== "streak");
  r = await call("POST", `/run-plans/days/${target.local_date}/adjust`, HTTP, { today, action: "just_mile" });
  const adjusted = r.json?.days?.find((x) => x.local_date === target.local_date);
  check("adjust just_mile ⇒ same body as /current, day is the streak mile, source user", [r.status, "latest_checkin" in (r.json ?? {}), adjusted?.kind, adjusted?.source], [200, true, "streak", "user"]);
  r = await call("POST", `/run-plans/days/${cur2.days.find((x) => x.local_date >= today && x.kind === "streak").local_date}/adjust`, HTTP, { today, action: "just_mile" });
  check("adjust a streak day to just_mile ⇒ 422 cap_note", [r.status, typeof r.json?.cap_note], [422, "string"]);
  r = await call("PATCH", "/run-plans/current", HTTP, { today, effort: 4, claude_auto_apply: true });
  check("PATCH effort + auto-apply", [r.status, r.json?.plan?.effort, r.json?.plan?.claude_auto_apply], [200, 4, true]);
  r = await call("PATCH", "/run-plans/current", HTTP, { today, run_daily_mile: "yes" });
  check("PATCH bad bool ⇒ 400", r.status, 400);
  r = await call("DELETE", "/run-plans/current", HTTP);
  check("DELETE /current archives", [r.status, r.json], [200, { ok: true, archived: true }]);
  r = await call("POST", "/run-plans/checkins", HTTP, { today, feeling: "tired" });
  check("no plan ⇒ 404 no_active_plan", [r.status, r.json?.error], [404, "no_active_plan"]);
  const noAuth = await fetch(base + "/run-plans/current");
  check("auth required", noAuth.status, 401);
} catch (err) {
  failures++;
  console.error("FAIL  threw:", err);
} finally {
  await cleanup().catch(() => {});
  server.close();
  await db.end?.();
}

console.log(failures ? `\n${failures} failure(s)` : "\nall run plans checks passed");
process.exit(failures ? 1 : 0);
