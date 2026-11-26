/**
 * Laundry: power readings from a smart plug -> what the machine is doing.
 *
 * Pure (no database, no clock): laundryService.ts feeds it the readings each
 * plug sends (one every 2 s, timestamped by the server on arrival) and stores
 * the state it hands back. Everything is in seconds and watts.
 *
 * How the two machines look on a power meter:
 *  - Washer (top-load, Whirlpool): a few watts for the panel; the fill valve
 *    adds a little; agitating is the motor kicking on and off every second or
 *    two (a jagged line); draining is the pump, low and steady; spinning is
 *    the motor held on, high and steady. A rinse is agitating after a spin.
 *    Quiet spells (filling, soaking) are normal mid-load, so "done" needs a
 *    few quiet minutes after the final spin, or a long quiet spell otherwise.
 *  - Dryer (gas, Samsung): the drum motor, steady; the igniter adds a few
 *    hundred watts each time the burner lights. Burner relighting = drying;
 *    the motor alone for the last few minutes = cooling down; the motor
 *    stopping = done. Wrinkle Release tumbles it for a moment now and then
 *    afterwards, which isn't a new load.
 *
 * Time left is learned from this machine's own finished loads (the tail of a
 * load - final spin, cool down - is the predictable part), with fixed guesses
 * until there's history. `sure` says when the number is worth trusting.
 */

export type Machine = "washer" | "dryer";
export type Stage =
  | "idle" // nothing running (and nothing waiting)
  | "fill"
  | "wash"
  | "rinse"
  | "drain"
  | "spin"
  | "dry"
  | "cool"
  | "tumble" // dryer with no heat (air fluff)
  | "done"; // finished, clothes still in (until a new load or it times out)

export const SAMPLE_S = 2;
const WINDOW_S = 20; // features over the last 20 s
const STAGE_HOLD_S = 16; // a new stage must show this long before it's taken
const DONE_SHOW_S = 3 * 3600; // "done" fades back to idle after 3 h
export const REMIND_AFTER_S = 45 * 60; // one "still in there" nudge
const MAX_HISTORY = 20;
const MOTOR_GUESS = 250; // dryer drum motor (W) until it's learned

export interface Tuning {
  /** Watts above standby that count as the machine doing something. */
  active: number;
  /** Washer: the motor (agitate / spin). Dryer: the drum turning. */
  motor: number;
  /** Dryer: watts above the drum motor that mean the igniter is on. */
  heat: number;
  /** Washer: quiet this long after the final spin = done. */
  doneAfterSpin: number;
  /** Washer: quiet this long without a final spin = done anyway (a soak). */
  doneQuiet: number;
  /** Dryer: the drum off this long = done. */
  dryerStop: number;
  /** A load must run this long to count (knob turned, a test spin...). */
  minLoad: number;
}

export const TUNING: Record<Machine, Tuning> = {
  washer: { active: 4, motor: 90, heat: 0, doneAfterSpin: 150, doneQuiet: 25 * 60, dryerStop: 0, minLoad: 5 * 60 },
  dryer: { active: 15, motor: 80, heat: 150, doneAfterSpin: 0, doneQuiet: 0, dryerStop: 60, minLoad: 4 * 60 },
};

/** Before this machine has history: typical lengths (s). */
const PRIOR = {
  washer: { total: 50 * 60, tail: 9 * 60 }, // tail: final spin start -> end
  dryer: { total: 55 * 60, tail: 6 * 60 }, //  tail: cool down start -> end
};

export interface LoadRecord {
  start: number;
  end: number;
  /** Seconds from the start of the predictable tail to the end, if seen. */
  tail: number | null;
}

export interface MachineState {
  machine: Machine;
  stage: Stage;
  standby: number; // learned standby watts
  win: [number, number][]; // [t, watts] for the last WINDOW_S
  cand: Stage | null; // stage waiting out STAGE_HOLD_S
  candAt: number;
  loadStart: number | null;
  lastBusy: number | null; // last time it drew more than standby
  stageAt: number | null;
  spins: number;
  rinsed: boolean; // agitated after a spin
  tailAt: number | null; // final spin / cool down started
  heatAt: number | null; // dryer: last time the burner lit
  motorBase: number | null; // dryer: the drum motor's own draw
  doneAt: number | null;
  doneLen: number | null; // that load's length (s)
  remindedAt: number | null;
  /** The load is real (the motor ran, or it kept drawing for 3 min); until
   *  then nothing is announced and it can quietly be forgotten. */
  confirmed: boolean;
  lastAt: number | null; // last reading
  history: LoadRecord[];
}

export type LaundryEvent =
  | { kind: "started"; machine: Machine; at: number }
  | { kind: "done"; machine: Machine; at: number; seconds: number }
  | { kind: "remind"; machine: Machine; at: number; waiting: number };

export function newState(machine: Machine): MachineState {
  return {
    machine,
    stage: "idle",
    standby: 2,
    win: [],
    cand: null,
    candAt: 0,
    loadStart: null,
    lastBusy: null,
    stageAt: null,
    spins: 0,
    rinsed: false,
    tailAt: null,
    heatAt: null,
    motorBase: null,
    doneAt: null,
    doneLen: null,
    remindedAt: null,
    confirmed: false,
    lastAt: null,
    history: [],
  };
}

function median(xs: number[]): number | null {
  if (!xs.length) return null;
  const s = [...xs].sort((a, b) => a - b);
  const m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}

interface Features {
  mean: number;
  max: number;
  min: number;
  motorFrac: number; // share of readings with the motor on
  cv: number; // how jagged (std / mean)
}

function features(win: [number, number][], motor: number): Features {
  const w = win.map((p) => p[1]);
  const n = w.length || 1;
  const mean = w.reduce((a, b) => a + b, 0) / n;
  const sd = Math.sqrt(w.reduce((a, b) => a + (b - mean) ** 2, 0) / n);
  return {
    mean,
    max: Math.max(0, ...w),
    min: Math.min(...w),
    motorFrac: w.filter((x) => x >= motor).length / n,
    cv: mean > 0 ? sd / mean : 0,
  };
}

/** Washer: what the last 20 s look like (before hysteresis). */
function washerLooks(f: Features, s: MachineState, t: Tuning): Stage | "quiet" {
  const base = s.standby;
  if (f.motorFrac >= 0.85 && f.cv < 0.35) return "spin";
  if (f.motorFrac >= 0.1) return s.spins > 0 ? "rinse" : "wash";
  if (f.mean - base >= 20 && f.max < t.motor) return "drain";
  if (f.mean - base >= t.active) return "fill";
  return "quiet";
}

/** Dryer: what the last 20 s look like. */
function dryerLooks(f: Features, s: MachineState, t: Tuning, now: number): Stage | "quiet" {
  if (f.mean < t.motor) return "quiet";
  if (f.max >= (s.motorBase ?? MOTOR_GUESS) + t.heat) return "dry";
  if (s.heatAt !== null && now - s.heatAt < 5 * 60) return "dry"; // between relights
  if (s.heatAt !== null) return "cool";
  return "tumble";
}

function confirm(s: MachineState, at: number, ev: LaundryEvent[]) {
  if (s.confirmed || s.loadStart === null) return;
  // A real wash always gets to the motor (agitating, draining or spinning)
  // within a few minutes of filling. A steady few watts on its own is just
  // the machine sitting there (some panels idle at 8-10 W), never a load.
  const motorRan = s.machine === "dryer" || s.stage !== "fill";
  if (!motorRan) return;
  s.confirmed = true;
  ev.push({ kind: "started", machine: s.machine, at: s.loadStart });
}

/** Feed one reading. Returns any events it caused. Mutates and returns `s`. */
export function step(s: MachineState, at: number, watts: number): LaundryEvent[] {
  const t = TUNING[s.machine];
  const ev: LaundryEvent[] = [];
  const w = Number.isFinite(watts) && watts >= 0 ? Math.min(watts, 4000) : 0;
  // A long gap (plug offline): forget the window, don't invent readings.
  if (s.lastAt !== null && at - s.lastAt > 5 * 60) s.win = [];
  s.lastAt = at;
  s.win.push([at, w]);
  while (s.win.length && s.win[0][0] <= at - WINDOW_S) s.win.shift();

  // Standby: the lowest steady reading while nothing runs (slowly learned).
  if (s.loadStart === null && s.win.length >= 5) {
    const f0 = features(s.win, t.motor);
    if (f0.max - f0.min < 2 && f0.mean < s.standby + t.active * 0.6) s.standby = s.standby * 0.9 + f0.mean * 0.1;
  }
  const busy = w - s.standby >= t.active;
  if (busy) s.lastBusy = at;
  if (s.win.length < 4) return ev;

  const f = features(s.win, t.motor);
  const looks = s.machine === "washer" ? washerLooks(f, s, t) : dryerLooks(f, s, t, at);
  if (s.machine === "dryer" && looks !== "quiet") {
    // The drum alone (learned from readings without the igniter), then any
    // reading well above it is the igniter: the burner is lighting.
    const motorOnly = s.motorBase ?? MOTOR_GUESS;
    for (const [, x] of s.win.slice(-1)) {
      if (x >= t.motor && x < motorOnly + t.heat * 0.6) s.motorBase = motorOnly * 0.97 + x * 0.03;
    }
    if (w >= (s.motorBase ?? MOTOR_GUESS) + t.heat) s.heatAt = at;
  }

  // ── not running: does a load start? ──
  if (s.loadStart === null) {
    const starting = looks !== "quiet" && (s.machine === "dryer" || f.mean - s.standby >= t.active);
    if (!starting) {
      s.cand = null;
      if (s.stage === "done" && s.doneAt !== null) {
        if (at - s.doneAt >= DONE_SHOW_S) s.stage = "idle";
        else if (s.remindedAt === null && at - s.doneAt >= REMIND_AFTER_S) {
          s.remindedAt = at;
          ev.push({ kind: "remind", machine: s.machine, at, waiting: at - s.doneAt });
        }
      }
      return ev;
    }
    // Wrinkle Release: short tumbles after a dry, no heat. Not a new load.
    if (s.machine === "dryer" && s.stage === "done" && looks !== "dry") {
      if (s.cand !== "tumble") (s.cand = "tumble"), (s.candAt = at);
      if (at - s.candAt < 3 * 60) return ev;
    } else if (s.cand === null) {
      s.cand = looks as Stage;
      s.candAt = at;
      return ev;
    } else if (at - s.candAt < STAGE_HOLD_S) {
      return ev;
    }
    // A new load (any earlier "done" is over: someone emptied it).
    const start = s.candAt - WINDOW_S / 2;
    Object.assign(s, {
      loadStart: start, stage: looks as Stage, stageAt: s.candAt, spins: looks === "spin" ? 1 : 0,
      rinsed: false, tailAt: null, heatAt: s.machine === "dryer" && looks === "dry" ? at : null,
      doneAt: null, doneLen: null, remindedAt: null, cand: null, confirmed: false,
    });
    confirm(s, at, ev);
    return ev;
  }

  // ── a start not yet confirmed: the panel lit for a moment is not a load ──
  if (!s.confirmed) {
    confirm(s, at, ev);
    if (!s.confirmed && at - (s.lastBusy ?? at) >= 2 * 60) {
      Object.assign(s, { loadStart: null, stage: "idle", stageAt: null, cand: null, spins: 0 });
      return ev;
    }
    // "Filling" for 12 min with no motor: that level is this machine's idle
    // draw. Learn it and forget the start.
    if (!s.confirmed && at - (s.loadStart ?? at) >= 12 * 60) {
      const f = features(s.win, t.motor);
      if (f.max - f.min < 4) s.standby = f.mean;
      Object.assign(s, { loadStart: null, stage: "idle", stageAt: null, cand: null, spins: 0 });
      return ev;
    }
  }

  // ── running: has it finished? ──
  const quietFor = at - (s.lastBusy ?? at);
  let finished = false;
  if (s.machine === "washer") {
    // Quiet right after the final spin (one that followed a rinse) = done
    // soon; any other quiet spell could be a fill or a soak.
    const afterSpin = s.tailAt !== null && (s.stage === "spin" || s.stage === "fill");
    finished = quietFor >= (afterSpin ? t.doneAfterSpin : t.doneQuiet);
  } else {
    finished = looks === "quiet" && quietFor >= t.dryerStop;
  }
  if (finished) {
    const end = s.lastBusy ?? at;
    const len = end - s.loadStart;
    const real = len >= t.minLoad;
    if (real) {
      s.history = [...s.history, { start: s.loadStart, end, tail: s.tailAt !== null ? end - s.tailAt : null }]
        .slice(-MAX_HISTORY);
      ev.push({ kind: "done", machine: s.machine, at: end, seconds: Math.round(len) });
    }
    Object.assign(s, {
      stage: real ? "done" : "idle", doneAt: real ? end : null, doneLen: real ? Math.round(len) : null,
      remindedAt: null, loadStart: null, stageAt: null, cand: null, tailAt: null, spins: 0, rinsed: false,
    });
    return ev;
  }

  // ── running: which stage? (quiet spells keep a sensible label) ──
  let next: Stage;
  if (looks === "quiet") {
    if (s.machine === "dryer") next = s.stage;
    // Washer: quiet after a spin or a drain is the next fill; quiet while
    // washing or rinsing is a soak (keep the label).
    else next = s.stage === "spin" || s.stage === "drain" ? "fill" : s.stage;
  } else next = looks;
  if (next === s.stage) {
    s.cand = null;
    return ev;
  }
  if (s.cand !== next) {
    s.cand = next;
    s.candAt = at;
    return ev;
  }
  if (at - s.candAt < STAGE_HOLD_S) return ev;
  // Washer: a spin after a rinse is the final one (the predictable tail).
  if (next === "spin") {
    s.spins += 1;
    if (s.rinsed && s.tailAt === null) s.tailAt = s.candAt;
  }
  if (next === "rinse") s.rinsed = true;
  if (next === "cool" && s.tailAt === null) s.tailAt = s.candAt;
  if (next === "dry") s.tailAt = null; // relit after a pause: not cooling after all
  s.stage = next;
  s.stageAt = s.candAt;
  s.cand = null;
  return ev;
}

export interface MachineView {
  machine: Machine;
  stage: Stage | "offline";
  /** Running: minutes since it started. Done: minutes since it finished. */
  minutes: number;
  /** Running: estimated minutes left (null = no idea yet). */
  left: number | null;
  /** The estimate comes from the predictable end of a load. */
  sure: boolean;
  /** Done: how long that load took (minutes). */
  took: number | null;
  /** How many finished loads it has learned from. */
  learned: number;
}

const OFFLINE_S = 15 * 60;

/** What the box, the remote and notifications show right now. */
export function view(s: MachineState, now: number): MachineView {
  const learned = s.history.length;
  const base = { machine: s.machine, learned, left: null as number | null, sure: false, took: null as number | null };
  if (s.lastAt === null || now - s.lastAt > OFFLINE_S) return { ...base, stage: "offline", minutes: 0 };
  if (s.loadStart === null || !s.confirmed) {
    if (s.stage === "done" && s.doneAt !== null) {
      return { ...base, stage: "done", minutes: Math.max(0, Math.floor((now - s.doneAt) / 60)),
        took: s.doneLen !== null ? Math.round(s.doneLen / 60) : null };
    }
    return { ...base, stage: "idle", minutes: 0 };
  }
  const elapsed = now - s.loadStart;
  const prior = PRIOR[s.machine];
  const totals = s.history.map((h) => h.end - h.start);
  const tails = s.history.map((h) => h.tail).filter((x): x is number => x !== null);
  const total = learned >= 2 ? median(totals)! : prior.total;
  const tail = tails.length >= 2 ? median(tails)! : prior.tail;
  let left: number;
  let sure = false;
  if (s.tailAt !== null) {
    left = tail - (now - s.tailAt);
    sure = true;
  } else {
    left = total - elapsed;
    // Never promise less than the tail still to come.
    left = Math.max(left, tail);
  }
  return {
    ...base,
    stage: s.stage,
    minutes: Math.floor(elapsed / 60),
    left: Math.max(1, Math.round(left / 60)),
    sure,
  };
}
