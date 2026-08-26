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
- [x] 9. Review + fix findings (3 codex passes, then 2 independent reviewer agents)
- [x] 10. Commit + final log update

## Known remaining issue (NOT fixed — read this one)

**The coach is driven by the tracker's foreground 1 Hz `Timer`, which suspends when the
app is backgrounded or the screen locks.** So on a locked-screen run — most of a real run —
the coach goes quiet. This is PRE-EXISTING (the ghost coach always rode that timer) and is
not a regression, but this branch makes it matter much more, because the whole premise is
now "a coach for the entire workout".

The fix is to drive `GhostCoach.update()` from the location/pedometer callback path (the way
`LivePresenceService.tick()` and the tracking watchdog already do) and let it self-throttle
to ~1 Hz, keeping the view timer as a foreground supplement. I deliberately did NOT do this
overnight: it touches `WorkoutLocationManager`'s callback chain, which per
`.claude/rules/ios.md` is the most failure-prone code in the app, and I have no compiler to
check it with. It wants a real device test.

Second, smaller: `GhostCoach.swift` notes that audibility on a locked screen also needs
`audio` in `UIBackgroundModes` — that lives in the off-limits `project.pbxproj`, so it has
to be set in Xcode.

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
- **Halfway** is half of the target, measured over THIS workout's distance (not the day's
  total). ~~With no ghost it uses the day's goal.~~ **Superseded by review finding 5:** the
  turnaround cue now requires a distance the runner actually CHOSE, because half of a 1-mile
  daily goal is not the halfway point of a six-mile run. With no explicit distance it says
  "Half way to your goal." instead.
- **Interval default 0.5 mi**, choices Off / 0.1 / ¼ / ½ ~~/ 1~~ (1 mi removed — review
  finding 8: the per-mile split re-anchors the marker, so it was identical to Off). Stored via
  `object(forKey:)` not `double(forKey:)` so that 0 can mean OFF rather than "never set" —
  otherwise a fresh install comes up with the feature disabled.
- ~~**Mile splits are `force: true`**~~ **Superseded by review findings 1 and 2:** forcing put
  two lines in one breath when a race finished on the same tick, and flooring dropped the split
  outright. They are now HELD — re-offered until the floor clears, which is safe because a
  split is still true a few seconds later.
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

## Review findings addressed (from 2 independent reviewer agents)

1. **Dropped announcements** — every producer committed its "already said it" state before
   the speech floor got a vote, so a floored line was gone forever ("announce EVERY pace
   transition" was silently violated). Added `hold(_:urgency:)`: lines that stay true while
   they wait are re-offered on later ticks with a 90s expiry.
2. **A one-mile race win ate mile 1's split** — `finish()` speaks the verdict on the same
   tick that crosses the mile. Now held, not forced/dropped.
3. **Relaunch mid-workout killed the coach permanently** — `isActive` is process-lifetime and
   the recovery path never called `start()`. It does now (ghostless; the armed race isn't in
   the persisted workout state).
4. **Peeking at the dashboard re-scaled the target mid-race** — the tracker is a
   fullScreenCover whose @State dies, so `raceGhost` went nil and milestones re-scaled to the
   daily goal ("Three quarters." a quarter into a 5K), while `isRacing` stayed true forever and
   spoke whitespace-only lines. Target is now LATCHED at `start()`, and a race that loses its
   ghost is treated as finished. This one was a regression introduced by calling `update()`
   unconditionally.
5. **Halfway used the DAILY GOAL** — told someone half a mile into a six-mile run to turn
   around. The turnaround wording now requires an explicitly chosen distance; otherwise it's
   "Half way to your goal."
6. **First pace-state line was a transition that never happened**, and the dead-zone fallback
   claimed "on pace" for a runner 6–10 s/mi down. Seeded silently; fallback names the real side.
7. **Multi-mile jumps mislabelled the split** (mile 3's "split" covering miles 2 and 3).
   Re-anchors silently instead.
8. **The "1 mi" interval chip was a no-op** (the mile split re-anchors the marker every time).
   Removed from the choices.
9. **`averagePace` had no plausibility band** — a recovered workout restarts the moving clock
   at 0 with miles already banked, which spoke "0 minute pace" and read as wildly ahead.
10. **Spoken-text**: "1.50 miles" → "1.5 miles"; "8 minute" → "8 minutes"; a half-marathon
    target no longer announced as "117:59".

Also fixed earlier from codex: mile-only ghost stamps (the server validates
`ghostTargetSeconds` as a MILE time and nulls the whole stamp otherwise), the on-screen coach
echo was gated on having a ghost (it's the accessibility path for the whole feature), and a
>1-mile win rendered in the mile-shaped celebration.

## Verification performed

- No Swift compiler exists on this VM (Linux; HealthKit/SwiftUI unavailable), so:
  - the coach's announcement state machine was ported to Python and simulated over
    multi-mile runs — that is what caught the wording bugs and proved ordering, one-shot
    milestones, hysteresis and past-goal continuation (`/tmp/coachsim2.py`);
  - brace/paren balance and closure declaration order checked programmatically per file;
  - `codex review` run 3× until it stopped finding issues (it then hit its usage limit);
  - one reviewer agent did an exhaustive compile-error hunt (every symbol, argument label,
    enum pattern match, Codable/memberwise-init default) — came back clean;
  - a second reviewer agent audited the logic and found the 10 items above.
- **CI is the first real compile.** `ios.yml` only runs on push-to-main or a PR, and there is
  no `gh` token on this VM, so I pushed to main to get the type-check to run — and I could
  not watch the result. Check it first thing.
