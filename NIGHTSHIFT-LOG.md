# NIGHTSHIFT LOG

Run started: 2026-08-26 (overnight, unattended).

## Brief

1. Push the two pending branches to `main`.
2. **Ghost run**: allow distances > 1 mile; set either a TOTAL pace or a PER-MILE pace.
3. **Coach mode**:
   - keep announcing against goal pace AFTER the goal is met (mile 2, 3, 4…);
   - announcements on a configurable interval (0.2 / 0.5 mi etc): "you are at 1.25 miles running at an 8:12 pace";
   - on each completed mile: overall average pace AND that mile's split pace;
   - announce every transition between ahead / on / behind goal pace;
   - announce the halfway point (for out-and-back runs).

## Status

- [x] 1. Push to `main` — merged both branches, pushed as `f39ac59`
- [x] 2. Recon: mapped GhostCoach / race ghost / BestEffortStore / tracker wiring
- [x] 3. Ghost run: distance selection > 1 mile + total-vs-per-mile pace
- [x] 4. Coach: interval announcements + past-goal continuation
- [x] 5. Coach: mile splits (overall avg + this mile)
- [x] 6. Coach: ahead/on/behind transitions
- [x] 7. Coach: halfway announcement
- [x] 8. Settings UI for the new prefs
- [ ] 9. codex review + fix findings
- [ ] 10. Commit + final log update

## Decisions

- **Pushed straight to `main`** as asked. Both merged branches are iOS-only, so the
  Coolify backend auto-deploy was not triggered. **No `gh` token on this VM** (`~/sandbox/.env`
  has an empty `GH_TOKEN`), so I could NOT watch the CI type-check afterwards — that is the
  one thing worth a glance in the morning.
- **Distance > 1 mile applies to the CUSTOM/pace target only.** Racing your recorded best,
  your PR or a friend over a 5K would mean extrapolating a *mile* effort to 3.1 miles, which
  invents a number nobody ran. Those stay at 1.0 mi; the custom target carries the distance.
- **Coach now runs on every workout**, not only when a ghost is armed. Splits, the interval
  line and the halfway turnaround are properties of the run; gating them on arming a ghost
  made coaching an opt-in of an opt-in. Race-only lines still require a ghost.
- **`isActive` (workout) split from `isRacing` (ghost)** in GhostCoach. Folding them together
  is exactly why the coach fell silent at 1.0 mi — `finish()` killed the whole thing. Now
  `finish()` ends only the race and mile 2, 3, 4 keep getting called against the same goal pace.
- **Pace-state hysteresis**: `on` inside ±6 s/mi, must reach ±10 s/mi to claim ahead/behind.
  A single dead band made a runner hovering on the boundary get narrated every few strides.
- **Halfway with no ghost uses the day's goal distance** as the intended run length. It is
  measured over THIS workout's distance (not the day's total), which is what an out-and-back
  turnaround actually wants.
- **Interval default 0.5 mi**, choices Off / 0.1 / ¼ / ½ / 1. Stored via `object(forKey:)`
  not `double(forKey:)` so that 0 can mean OFF rather than "never set" — otherwise a fresh
  install comes up with the feature disabled.
- **Mile splits are `force: true`** (bypass the speech floor) — they carry two numbers that
  can't be reconstructed later. Everything else respects the floor.
- Mile-split crossing re-anchors the interval marker, so "Mile 2" and an interval call can't
  fire a stride apart.

## How to run / verify

- **No Swift compiler on this VM** (Linux; HealthKit/SwiftUI unavailable). iOS type-check is
  CI-only: `.github/workflows/ios.yml` type-checks `app/Mile A Day/**` as ONE module.
  Local verification = structural checks (brace/decl-order scripts), pure-logic ports to
  Python for math, and `codex review`.
- Backend/website untouched by this work.

## Resume pointer

If context compacted: re-read this file + the Status list. Continue at the first unchecked
item. Do NOT restart. Branch for feature work: `feat/ghost-coach-upgrades`.
