# Nightshift — Injury Pause (Recovery Mode)

Branch: `feat/injury-pause` (off `origin/main` @ 490861e)
Task: build the injury-pause streak feature designed earlier in session. **Backend first.**

## The agreed ruleset (this is the spec)

| Rule | Value |
|---|---|
| Unlock | current streak >= **90 days** |
| Backdate | up to **7 days**; may reattach an already-broken streak inside that window |
| Minimum length | **30 days** (end button disabled until then) |
| Max length (cap) | **180 days** -> converts to `longest_streak`, streak ends |
| Re-earn | **90 consecutive days counted from the day the streak restarts** (NOT the restored number) |
| During pause | streak frozen, no growth even if you run/walk |
| Pure flame | lost (`natural_streak = false`) |
| Leaderboard | paused users out of streak rankings |
| Label | explicit "injury" — status badge by name, "Paused X days for injury" |

Research basis for the 180-day cap: time-to-walk-a-mile (app counts WALKS, so the bar is
walking not running). ACL recon 8-12wk, Achilles rupture 4-6mo, broken ankle 12-16wk.
180d covers ~85-90% of realistic cases. Sources: AAOS, Cleveland Clinic, MGH/OSU protocols.

## Status

- [ ] Recon: streak core, sweep, payload, leaderboard
- [ ] Migration 0056: `streak_pauses` table + `streak_coverage` kind
- [ ] Service: `injuryPauseService` (start/end/eligibility/status)
- [ ] Sweep branch: paused -> write coverage row, do NOT recordBreak
- [ ] Streak walk: paused days count as covered; no growth during pause
- [ ] Payload: additive `injury_pause` fields on stats
- [ ] Leaderboard: exclude paused from streak rankings
- [ ] Controller + routes + client feature gate
- [ ] Verify: scratch-DB e2e proving all 9 rules
- [ ] `npm run build` + `drizzle-kit check` + migrator-twice idempotence
- [ ] codex review --uncommitted
- [ ] Commit

## Decisions (autonomous)

- Backend only this run. iOS (crutches flame, name badge) is UI that wants mockup
  approval; human is asleep. Backend ships independently and old clients just see a
  preserved number, which is correct.

## How to run / verify

TBD — filled in as it lands.

## Resume pointer

If context compacted: read this file top to bottom, then `git log --oneline origin/main..HEAD`
to see what already landed. Continue at the first unchecked box. Do NOT restart.
