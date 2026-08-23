# Nightshift — Injury Pause (Recovery Mode)

Branch: `feat/injury-pause` (off `origin/main` @ 490861e) — **backend complete, not pushed.**
Commits: `f7fba5a` (feature), `4f4481a` (review fixes).

## The agreed ruleset (the spec)

| Rule | Value |
|---|---|
| Unlock | current streak >= **90 days** |
| Backdate | up to **7 days**; reattaches an already-stamped break |
| Minimum length | **30 days** (`can_end` false until then) |
| Max length (cap) | **180 days** -> expires, converts to `longest_streak` |
| Re-earn | **90 consecutive days from the resume** (not the restored number) |
| During pause | streak frozen; a logged walk earns nothing |
| Pure flame | lost (`natural_streak = false`) |
| Leaderboard | paused users out of streak rankings (streak only) |
| Label | explicit "injury" |

180-day cap is from time-to-walk-a-mile (the goal counts WALKS): ACL recon 8-12wk,
broken ankle 12-16wk, Achilles rupture 4-6mo. Covers ~85-90%. Sources: AAOS,
Cleveland Clinic, MGH/OSU rehab protocols.

## Status — backend DONE

- [x] Migration 0056 `streak_pauses` (metadata-only, safe at boot)
- [x] `injuryPauseService` — eligibility, start, end, cap expiry, status
- [x] Streak walk elides pauses (`streakFeatureCore`)
- [x] Sweep skips paused users; no break, no friend pushes
- [x] Payload `injury_pause` + `natural_streak` false while paused
- [x] Leaderboard excludes paused (page, count, and own-rank fallback)
- [x] `GET/POST/DELETE /streak/pause`
- [x] 66-assertion e2e + 13 HTTP tests + ci-smoke + migrate-twice
- [x] 4 rounds of `codex review` — final pass clean
- [x] iOS: injured flame figure, both paused heroes, Recovery Mode screen,
      injury chip component, TEMPORARY preview toggle (`InjuryPausePreview`)
- [ ] Friend-facing injury chip — component built, but NO endpoint serves a
      paused flag for friends yet (see Next)

## The one idea worth keeping in your head

A pause **elides** days; it does not **cover** them. A `streak_coverage` row
COUNTS as a day in the walk, so covering a 90-day injury would have handed out
90 free streak days — the exact opposite of "the streak can't increase". Eliding
removes the days from the calendar so the runs either side join up.

That splits in two once a pause expires at the cap:
- **suppress** ("earned nothing") — every pause, forever
- **bridge** ("days either side join up") — only live ones

Without the split, walks logged during recovery spring back when the pause
expires and carry the streak through the cap.

## Decisions (autonomous)

- **Backend only.** iOS is the crutches flame + name badge — UI that wants
  mockup approval, and you were asleep. Backend ships independently; old
  clients just see a preserved number, which is correct.
- **Kill switch stops new pauses, never un-bridges open ones.** Both
  `INJURY_PAUSE_DISABLED` and `STREAK_FEATURES_DISABLED`. If flipping a switch
  dropped pause awareness, the morning sweep would stamp real breaks on every
  injured user — an unrecoverable write from the switch meant to be safe.
  Hence walks gate on `needsFeatureWalk`, not `coverageActiveFor`.
- **No `CLIENT_FEATURES` string yet.** Add it in the iOS build that declares
  it, per the house rule; nothing server-side needs gating (payload additions
  are ignored by old decoders).
- **`reason: "rebuilding"` is checked before `"streak_too_short"`** — they
  overlap constantly and rebuilding is the actionable one.
- **Assist reason for a paused friend stays `gap_too_wide`.** `available:false`
  is right; a new reason string could break strict client decoding.
- e2e script committed to `backend/scripts/` (matches `ci-smoke.mjs`; repo has
  no unit runner).

## How to run / verify

```bash
cd backend && npm run build
sudo -u postgres psql -c "CREATE DATABASE mad_injury_test OWNER wo"
sudo -u postgres psql -d mad_injury_test -c "CREATE EXTENSION pg_trgm; CREATE EXTENSION pgcrypto;"
DATABASE_URL=postgres://wo:wo@localhost:5432/mad_injury_test \
  APP_JWT_SECRET=testsecret PORT=3987 node dist/server.js &   # applies migrations
node scripts/injury-pause-e2e.mjs        # 66 assertions
```
Needs a FRESH DB each run (fixed user ids, no cleanup).

## Not mine, but flagged

`.claude/db-roles-check.sh` + `.claude/db-roles-setup.sql` are untracked in your
working tree (pre-existing, not part of this branch, deliberately not committed).
`codex review` flagged the checker twice as **P1**: its "want blocked" probes
actually execute `DELETE` / `TRUNCATE` / `DROP` against the first real table when
a role is over-privileged — i.e. exactly the misconfiguration it's meant to
detect, and the docs say to run it against prod. Worth wrapping those probes in
a rolled-back transaction before it's ever pointed at prod.

## Next

**Friend-facing badge needs a backend field.** `InjuryStatusChip` /
`InjuryNameRow` exist and are layout-safe, but nothing serves "is this friend
paused" — `pausedUserIds()` was written and never wired into a response. The
feed/friends payloads need an additive `injury_paused` bool before the chip can
appear next to anyone but yourself. Recovery Mode copy deliberately promises
nothing about friend visibility until that lands.

Original client notes, still true:
- crutches flame as a 4th `StreakFlamePhase` — NOT `.coal` (coal means the
  streak actually died; `ReignitingFlameView` would tell a returning 400-day
  user their flame went out). Lives in `FlameBuddyFigure` + both widget copies.
- injury badge beside the name: build as `ViewThatFits { HStack; VStack }`.
  `.fixedSize()` on a chip next to a username is the collab-header overflow bug.
- `GET /streak/pause` returns every limit (`min_streak`, `min_days`, `max_days`,
  `max_backdate_days`, `reearn_progress`/`reearn_target`) so no number is
  hardcoded client-side.
