// Laundry engine check: replays made-up but realistic power traces for the
// washer (top-load) and the dryer (gas) through the engine and checks the
// stages, "done", the reminder and the time-left estimate. No database.
// Run: node scripts/laundry-check.mjs   (after npm run build)
import assert from "node:assert/strict";
import { newState, step, view, SAMPLE_S } from "../dist/services/laundryEngine.js";

let seed = 7;
const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
const jit = (w, p = 0.06) => Math.max(0, w * (1 + (rnd() * 2 - 1) * p));

/** [seconds, fn(t) -> watts] segments -> readings every 2 s. */
function trace(segments) {
  const out = [];
  for (const [len, fn] of segments) for (let t = 0; t < len; t += SAMPLE_S) out.push(fn(t));
  return out;
}
const standby = (len, w = 1.5) => [len, () => jit(w, 0.1)];
const fill = (len) => [len, () => jit(7)];
const agitate = (len) => [len, () => (rnd() < 0.5 ? jit(360, 0.15) : jit(12, 0.3))];
const drain = (len) => [len, () => jit(45)];
const spin = (len) => [len, (t) => jit(t < 30 ? 120 + t * 4 : 240, 0.08)];
const soak = (len) => [len, () => jit(2, 0.1)];

const washer = (opts = {}) => [
  standby(120), fill(240), agitate(opts.wash ?? 720), ...(opts.soak ? [soak(opts.soak)] : []),
  drain(120), spin(300), fill(240), agitate(360), drain(120), spin(420), standby(opts.after ?? 3600),
];
const dryer = (dryMin = 40, opts = {}) => {
  const segs = [standby(120, 0.5)];
  for (let m = 0; m < dryMin; m += 4) segs.push([40, () => jit(640)], [200, () => jit(230, 0.04)]);
  segs.push([360, () => jit(230, 0.04)]); // cool down
  const after = opts.after ?? 3600;
  for (let t = 0; t < after; t += 300) segs.push([20, () => jit(230, 0.04)], [280, () => jit(0.5, 0.2)]);
  return segs;
};

function run(machine, segs, s = newState(machine), t0 = 1_800_000_000) {
  const events = [];
  const stages = [];
  const views = [];
  let at = t0;
  for (const w of trace(segs)) {
    for (const e of step(s, at, w)) events.push(e);
    if (stages.at(-1) !== s.stage) stages.push(s.stage);
    if (at % 60 === 0) views.push([at - t0, view(s, at)]);
    at += SAMPLE_S;
  }
  return { s, events, stages, views, end: at };
}

// ── washer: stages in order, done shortly after the final spin ──
{
  const r = run("washer", washer());
  assert.deepEqual(
    r.stages.filter((x) => x !== "idle"),
    ["fill", "wash", "drain", "spin", "fill", "rinse", "drain", "spin", "fill", "done"],
    "washer stages: " + r.stages.join(" > "),
  );
  const kinds = r.events.map((e) => e.kind);
  assert.deepEqual(kinds, ["started", "done", "remind"], "washer events: " + kinds.join(","));
  const done = r.events.find((e) => e.kind === "done");
  const loadLen = 240 + 720 + 120 + 300 + 240 + 360 + 120 + 420;
  assert.ok(Math.abs(done.seconds - loadLen) < 60, `washer length ${done.seconds} vs ${loadLen}`);
  // reported "done" within 3 min of the drum stopping
  const stopAt = 1_800_000_000 + 120 + loadLen;
  const doneView = r.views.find(([, v]) => v.stage === "done");
  assert.ok(doneView[0] + 1_800_000_000 - stopAt <= 180 + 60, "washer done late");
  console.log("washer:", r.stages.join(" > "), "| took", Math.round(done.seconds / 60), "min");
}

// ── washer with a long soak: not "done" in the middle of it ──
{
  const r = run("washer", washer({ soak: 15 * 60 }));
  const kinds = r.events.map((e) => e.kind);
  assert.equal(kinds.filter((k) => k === "done").length, 1, "soak ended the load early: " + r.stages.join(">"));
  console.log("washer + 15 min soak: one load, ok");
}

// ── dryer: dry > cool > done; wrinkle tumbles don't start a new load ──
{
  const r = run("dryer", dryer());
  const kinds = r.events.map((e) => e.kind);
  assert.deepEqual(kinds, ["started", "done", "remind"], "dryer events: " + kinds.join(",") + " " + r.stages.join(">"));
  assert.deepEqual(r.stages.filter((x) => x !== "idle"), ["dry", "cool", "done"], "dryer stages: " + r.stages.join(" > "));
  console.log("dryer:", r.stages.join(" > "), "| took", Math.round(r.events[1].seconds / 60), "min");
}

// ── time left: guesses at first, learns, and is sure in the tail ──
{
  const s = newState("washer");
  let t0 = 1_800_000_000;
  for (let k = 0; k < 3; k++) t0 = run("washer", washer({ after: 600 }), s, t0).end;
  assert.equal(s.history.length, 3);
  const r = run("washer", washer({ after: 600 }), s, t0);
  const mid = r.views.find(([sec]) => sec === 120 + 20 * 60)[1]; // 20 min in
  const loadMin = (240 + 720 + 120 + 300 + 240 + 360 + 120 + 420) / 60;
  assert.ok(Math.abs(mid.left - (loadMin - 20)) <= 3, `20 min in: ${mid.left} left, expected ~${loadMin - 20}`);
  assert.equal(mid.sure, false);
  const tail = r.views.find(([sec, v]) => v.sure);
  assert.ok(tail, "never sure in the final spin");
  assert.ok(tail[1].left <= 8, `final spin: ${tail[1].left} left`);
  console.log(`washer after 3 loads: 20 min in -> ${mid.left} min left; final spin -> ${tail[1].left} min left (sure)`);
}
{
  const s = newState("dryer");
  let t0 = 1_800_000_000;
  for (let k = 0; k < 2; k++) t0 = run("dryer", dryer(40, { after: 600 }), s, t0).end;
  const r = run("dryer", dryer(40, { after: 600 }), s, t0);
  const cool = r.views.find(([, v]) => v.stage === "cool");
  assert.ok(cool && cool[1].sure && cool[1].left <= 6, "dryer cool-down estimate: " + JSON.stringify(cool?.[1]));
  console.log(`dryer cool-down -> ${cool[1].left} min left (sure)`);
}

// ── a knob turned / panel lit for a minute is not a load ──
{
  const r = run("washer", [standby(300), [60, () => jit(9)], standby(900)]);
  assert.equal(r.events.filter((e) => e.kind === "done").length, 0);
  assert.equal(r.s.stage, "idle");
  console.log("washer: a minute of panel light is not a load, ok");
}

// ── plug offline: the view says so ──
{
  const r = run("washer", [standby(60)]);
  assert.equal(view(r.s, r.end + 20 * 60).stage, "offline");
  console.log("offline after 15 min of silence, ok");
}
// ── a washer that idles at 8.5 W (its panel): never a phantom load, and real loads still work ──
{
  const idle85 = (len) => [len, () => jit(8.5, 0.03)];
  const segs = [idle85(30 * 60), ...washer({ after: 0 }).slice(1, -1), idle85(3600)];
  const r = run("washer", segs);
  const kinds = r.events.map((e) => e.kind);
  assert.deepEqual(kinds.filter((k) => k !== "remind"), ["started", "done"], "8.5 W idle: " + kinds.join(",") + " " + r.stages.join(">"));
  const first = r.views.find(([sec]) => sec === 20 * 60)[1];
  assert.equal(first.stage, "idle", "8.5 W idle shows as " + first.stage);
  assert.ok(r.s.standby > 7 && r.s.standby < 10, "learned standby " + r.s.standby);
  console.log("washer idling at 8.5 W: no phantom load, real load found, standby learned", r.s.standby.toFixed(1), "W");
}
console.log("laundry-check: all good");
