# Mile A Day — Code Audit (Bugs, Security, Performance, UX)

A cross-app deep dive across the **backend** (TypeScript/Express/PostgreSQL),
the **iOS app** (SwiftUI), and the **widgets**. Findings are ranked by priority
so they can be turned straight into tickets.

This document is a **findings list only** — no fixes have been applied as part of
producing it.

## How to read this

- **Priority tiers:** `P0` (critical, fix first) → `P3` (low / cleanup).
- **Confidence:**
  - ✅ **Verified** — confirmed by reading the actual code.
  - ⚠️ **Reported** — surfaced by an automated pass, plausible, but not yet
    hand-verified. Confirm when scoping the ticket.
- **Locations** are `path:line` where known. Line numbers drift as the code
  changes — treat them as starting points, not gospel.

Each item explains **what it is**, **why it matters**, and **the direction of a
fix** (not a prescriptive patch).

---

## P0 — Critical (fix first)

### 1. Per-second writes of full workout state to UserDefaults during active workouts ✅
- **Where:** `app/Mile A Day/Core/State/InProgressWorkoutStore.swift` (`save` + `synchronize()`); driven by the 1 Hz timer / `flushRoutePoints` in `app/Mile A Day/Views/Dashboard/WorkoutTrackingView.swift`.
- **What:** On every GPS tick / timer tick the entire in-progress workout state — including up to 5,000 route points (hundreds of KB once JSON-encoded) — is re-encoded and written to `UserDefaults`, followed by a forced `synchronize()`.
- **Why it matters:** `UserDefaults` is a property-list store, not a database. Re-serializing a large blob once per second and force-flushing it: blocks the main thread (jank), drains battery on long outdoor runs, wears flash storage, and risks silent write failures / state corruption as the blob grows. This is the single highest-impact reliability issue in the app.
- **Fix direction:** Stop persisting the full route on every tick. Persist a small "resume header" (start time, elapsed, cumulative distance) frequently, and append route points to a separate append-only store (file/SQLite) on a throttled cadence. Remove `synchronize()` (deprecated and unnecessary since iOS 13).

### 2. IDOR — workout endpoints have no self/friend authorization ✅
- **Where:** `backend/src/routes/workoutRoutes.ts:9-12` → `getStreak`, `getRecentWorkouts`, `getUserStats` in `backend/src/controllers/workoutController.ts`.
- **What:** These routes are mounted after `authenticateToken` but only check that the target user *exists* — not that the requester is that user or a friend. Any authenticated user can read anyone's workout history, distances, dates, and streak by supplying another `userId`.
- **Why it matters:** Private fitness data is exposed to any logged-in account. It's also an internal inconsistency: the daily-challenge endpoint already gates non-self access with `areFriends` (`dailyChallengeController.ts:23-26`), so these endpoints simply weren't given the same treatment.
- **Fix direction:** Add `requireSelfAccess('userId')` where only the owner should read, or an explicit "self-or-friend" check (mirroring the challenge controller) where friends are meant to see the data.

### 3. Manual workout entry lets users fabricate data (cheating vector) ✅ (backend gap) / ⚠️ (client)
- **Where:** `app/Mile A Day/Views/Dashboard/ManualWorkoutEntryView.swift` (validation ~lines 86-90); upload path in `app/Mile A Day/Services/WorkoutService.swift`; backend `uploadWorkouts`.
- **What:** Client validation only requires `0 < distance < 100` and `duration > 0`, and allows back-dating up to 30 days. "99 miles in 1 second" passes. The backend upload path performs no plausibility validation either.
- **Why it matters:** Streaks, total miles, leaderboards, and pace PRs can be arbitrarily inflated — corrupting the core competitive loop and any social comparisons built on it.
- **Fix direction:** Enforce server-side plausibility bounds (max distance per workout, minimum pace floor, date window, per-day caps). Client validation is UX nicety; the authoritative check must live in the backend since the client is untrusted.

### 4. Stacked NotificationCenter observers / un-invalidated timers ⚠️
- **Where:** `app/Mile A Day/Views/Dashboard/DashboardView.swift` (~351-398) registers `WorkoutIndexReady` and `MAD_OpenWorkoutFromLiveActivity` observers in `onAppear` with no removal; `app/Mile A Day/Views/Dashboard/WorkoutLocationManager.swift` (~234) starts a 1 Hz `Timer` in `onAppear` with no `onDisappear` invalidate.
- **What:** Every time these views appear (tab switch, navigation pop) a fresh observer/timer is added. Nothing tears the old ones down.
- **Why it matters:** Observers stack, so a single event fires its handler N times — duplicate celebrations, repeated expensive index rebuilds, and the workout view flipping open unexpectedly. The 1 Hz banner timer keeps running (and reloading state from disk every second) after the banner is gone — battery drain plus a retain cycle.
- **Fix direction:** Pair every `addObserver`/`scheduledTimer` with cleanup in `onDisappear` (or use the `.onReceive`/structured-concurrency equivalents that auto-cancel). Store observer tokens and remove them.

---

## P1 — High

### 5. 30-day access tokens ✅
- **Where:** `backend/src/services/tokenService.ts:5` (`ACCESS_TOKEN_EXPIRY = '30d'`).
- **What:** Access tokens are valid for 30 days and are not checked against the database on each request (stateless verify only).
- **Why it matters:** A leaked access token is usable for a month and is effectively unrevocable — the refresh-token rotation/revocation system can't help because access tokens never consult server state.
- **Fix direction:** Shorten access-token lifetime to minutes/hours and lean on the existing refresh flow for renewal.

### 6. Error handler leaks internals to clients ✅
- **Where:** `backend/src/server.ts:86-92` returns raw `err.message`; many controllers also do `'...: ' + error.message`.
- **What:** 500 responses include the underlying error text (DB errors, file paths, library internals).
- **Why it matters:** Information disclosure that helps an attacker map the system; also leaks implementation details to ordinary clients.
- **Fix direction:** Return a generic message + a correlation id to clients; log full details server-side only.

### 7. JWT secret used with no validation ✅
- **Where:** `backend/src/services/tokenService.ts:4` (`process.env.APP_JWT_SECRET!`); `backend/src/middleware/auth.ts` encodes it unchecked.
- **What:** The non-null assertion hides a missing-env-var case. If `APP_JWT_SECRET` is ever unset, `TextEncoder().encode(undefined)` yields the literal bytes of `"undefined"`, and every token is signed/verified with that as the key.
- **Why it matters:** A silent, catastrophic auth weakness — anyone who guesses the misconfiguration can forge tokens.
- **Fix direction:** Validate required secrets at boot and crash fast if absent. Never sign/verify with a fallback.

### 8. Unbounded query limits (DoS lever) ✅
- **Where:** `backend/src/controllers/workoutController.ts:187-201` (`getRecentWorkouts` passes a `null` limit → unbounded rows); `backend/src/controllers/inAppNotificationController.ts:100-101` (`parseInt(limit)` with no cap, no negative/NaN handling).
- **What:** Clients control result size with no ceiling. `?limit=99999999` (or a negative value) is accepted.
- **Why it matters:** Memory pressure / DoS, and odd SQL behavior on negative/NaN inputs.
- **Fix direction:** A `clampLimit`/`clampOffset` helper already exists elsewhere in the codebase — apply it consistently and reject non-numeric/negative input.

### 9. Non-transactional multi-write operations ✅
- **Where:** `backend/src/services/competitionService.ts:74-91` (`createCompetition` inserts the competition then the owner membership as two separate statements); same class of issue in `backend/src/services/friendshipService.ts` accept-request double-write.
- **What:** Related writes aren't wrapped in a transaction.
- **Why it matters:** A failure between statements leaves corrupt partial state — e.g. a competition with no members, or a one-directional friendship.
- **Fix direction:** Wrap each multi-statement mutation in `db.transaction()` so it's all-or-nothing.

### 10. User search returns full rows incl. email ✅
- **Where:** `backend/src/controllers/usersController.ts:32` — `SELECT * FROM users WHERE username ILIKE $1 OR email ILIKE $1 LIMIT 50`.
- **What:** Search returns every column, including email, and matches on email too.
- **Why it matters:** Email/PII disclosure and user-enumeration via search.
- **Fix direction:** Select only public columns; don't match on email (or only allow exact-email lookups behind a separate, rate-limited path).

### 11. Auth tokens persisted in plaintext UserDefaults ⚠️
- **Where:** `app/Mile A Day/Services/TokenStore.swift` writes Keychain **and** mirrors to `UserDefaults`; legacy readers (`FriendService`, `WorkoutService`, `ProfileImageService`, `DailyStepsSyncService`) and the watch bridge in `Models/HealthKitManager.swift` read the plaintext copy.
- **What:** The Keychain migration is half-done; tokens still live unencrypted in `UserDefaults`, and the access token is shipped to the watch via application context.
- **Why it matters:** Plaintext tokens land in device/iCloud backups; a compromised backup or watch yields working credentials.
- **Fix direction:** Finish the migration — make Keychain the single source of truth, delete the UserDefaults mirror, and stop sending the access token to the watch (send a device-scoped hint or refresh on the watch separately).

### 12. Widget refresh-budget exhaustion + no midnight rollover ✅
- **Where:** `app/Mile A Day/Widgets/TodayProgressWidget.swift:48` (60s refresh request); `app/Mile A Day/Shared/WidgetDataStore.swift` (double reload, immediate + 0.5s).
- **What:** The timeline asks WidgetKit to refresh every 60 seconds. WidgetKit caps the number of refreshes per day, so the budget is spent quickly and the widget then freezes unpredictably. There's no timeline entry scheduled at local midnight, so the widget shows yesterday's miles after midnight. `WidgetDataStore` also triggers two timeline reloads per save.
- **Why it matters:** Widgets look broken/stale — a visible, everyday UX failure.
- **Fix direction:** Use a realistic refresh cadence, add an explicit timeline entry at the next local midnight (reset to 0), and de-dup the reload calls.

### 13. Duplicate refresh storms on launch/foreground ✅
- **Where:** `app/Mile A Day/Views/MainTabView.swift` — `.task` and `.onChange(of: scenePhase == .active)` both call `competitionService.refreshAllData()` + `friendService.refreshAllData()` + unread count.
- **What:** Cold launch runs the `.task`; the first `.active` transition then runs the identical set again. No de-duplication.
- **Why it matters:** Doubles network/battery on every foreground and can delay the first paint behind redundant requests.
- **Fix direction:** Add a minimum-interval / in-flight guard per service so overlapping triggers coalesce.

### 14. Main-thread O(n) stat recomputation on launch ⚠️
- **Where:** `app/Mile A Day/Models/HealthKitManager+DataFetching.swift` calls `recalculateStatsWithAllWorkouts()` on the main queue after updating cached workouts.
- **What:** A linear pass over the full cached-workout array runs on the main thread.
- **Why it matters:** With large histories this blocks UI for 100-500ms during cold launch and stutters animations.
- **Fix direction:** Move the computation off-main and publish results back; consider incremental updates instead of full recompute.

### 15. Unbounded cron fan-outs ✅ (logic) / ⚠️ (scale)
- **Where:** `backend/src/cron/silentSyncCron.ts` iterates `SELECT DISTINCT user_id` and awaits each push serially; `backend/src/services/notificationService.ts` `checkCompetitionsEndingSoon` / `checkStreaksBroken` scan unbounded sets and re-query per row.
- **What:** Cron jobs iterate the entire user/competition base one row at a time with no pagination or bounded concurrency.
- **Why it matters:** Fine today, but a single slow push blocks the rest, and runtime grows linearly with users — these will choke as the base grows.
- **Fix direction:** Page through users and fan out in bounded-concurrency batches; pre-aggregate where possible.

---

## P2 — Medium

### 16. Fire-and-forget error swallowing in the upload path ✅
- **Where:** `backend/src/controllers/workoutController.ts:95-103` — an un-awaited async IIFE runs `checkLeadChanges` / `checkCompetitionMilestones`; rejections escape the surrounding try.
- **Why it matters:** Notification/competition side effects can fail invisibly while the upload returns 200, so users silently miss lead-change/milestone alerts.
- **Fix direction:** Await and handle, or hand off to a job queue with its own error handling.

### 17. Invalid push-token cleanup silently ignored ⚠️
- **Where:** `backend/src/services/pushNotificationService.ts:162,377` — `removeInvalidToken(...).catch(() => {})`.
- **Why it matters:** Dead device tokens accumulate forever; APNs/FCM failures get masked.
- **Fix direction:** Log failures; let them surface to the cron error handler.

### 18. Sensitive data in `print()` logs ⚠️
- **Where:** `app/Mile A Day/Services/APIClient.swift` (~203, raw response bodies up to 2000 chars); `TokenRefreshService`, `FriendService` ("auth token present"), `AppDelegate` (APNs token prefix).
- **Why it matters:** Tokens/PII can end up in device console and crash logs.
- **Fix direction:** Gate verbose logs behind `#if DEBUG`; never log token material or full response bodies.

### 19. Hard-coded backend user id in dev settings ⚠️
- **Where:** `app/Mile A Day/Views/Settings/DeveloperSettingsView.swift` (~480).
- **Why it matters:** Ships a real user id in the binary; the whole Developer Settings screen is reachable in release builds.
- **Fix direction:** Remove the hard-coded id; wrap Developer Settings in `#if DEBUG`.

### 20. Concurrent UserDefaults writes can drop synced-workout ids ⚠️
- **Where:** `app/Mile A Day/Services/WorkoutSyncService.swift` — `markWorkoutsAsSynced` does read-union-write with no mutual exclusion across concurrent batches; the `uploadedWorkoutIds` set also grows unbounded.
- **Why it matters:** Two batches finishing together can clobber each other's additions → duplicate uploads; the ever-growing set eventually strains UserDefaults.
- **Fix direction:** Serialize updates (actor/queue); store sync state in a database keyed by workout id rather than one growing array.

### 21. `updateFriendSettings` doesn't verify the relationship ⚠️
- **Where:** `backend/src/controllers/notificationSettingsController.ts` — takes `:friendId` and writes settings without confirming a friendship exists.
- **Why it matters:** Lets a user write per-friend notification settings for arbitrary ids.
- **Fix direction:** Validate the friendship before writing.

### 22. Nudge/flex logging has no idempotency ⚠️
- **Where:** `backend/src/services/pushNotificationService.ts:544,584` — inserts without a unique constraint.
- **Why it matters:** Rapid double-taps double-log and can double-count against rate limits.
- **Fix direction:** Add a unique constraint (e.g. per sender/target/day) with `ON CONFLICT DO NOTHING`.

### 23. Workout tracking view stops timer but not location on disappear ⚠️
- **Where:** `app/Mile A Day/Views/Dashboard/WorkoutTrackingView.swift` `onDisappear`.
- **Why it matters:** Dismissing without ending a workout can leave GPS running — battery drain.
- **Fix direction:** Stop location tracking on disappear unless an explicit "keep running in background" state is intended.

### 24. Deprecated `UserDefaults.synchronize()` ⚠️
- **Where:** multiple call sites (`InProgressWorkoutStore`, `WorkoutSyncService`, …).
- **Why it matters:** Unnecessary since iOS 13; adds main-thread stalls.
- **Fix direction:** Remove the calls; rely on automatic persistence.

### 25. N+1 in `checkCompetitionMilestones` ⚠️
- **Where:** `backend/src/services/notificationService.ts:286-291` — full `getCompetition()` per competition in a loop.
- **Why it matters:** One full aggregation round-trip per competition; slow for users in many competitions.
- **Fix direction:** Batch the needed data in a single query or parallelize with a bound.

### 26. Stale celebrations on foreground ⚠️
- **Where:** `app/Mile A Day/Managers/CelebrationManager.swift`.
- **Why it matters:** Celebrations queued while backgrounded replay on return even when no longer relevant.
- **Fix direction:** Timestamp queued celebrations and drop stale ones on foreground.

### 27. Push-token registration auth is order-fragile ✅ (not currently exploitable)
- **Where:** `backend/src/routes/deviceRoutes.ts` + `server.ts` mount order.
- **Why it matters:** It's protected only because it's mounted after `authenticateToken`; a future reorder silently opens unauthenticated token registration.
- **Fix direction:** Add an explicit auth guard on the route so safety doesn't depend on mount order.

---

## P3 — Low / cleanup

- **28. Wildcard CORS + no rate limit on `/public/profile-image/:username`** ✅ — `backend/src/server.ts:49-67`. Enumeration surface. Restrict origins; add rate limiting.
- **29. No rate limiting on `/auth/*`** ✅ — mitigated by Sign in with Apple, but still worth a limiter.
- **30. Dead code: empty `getWorkoutRange()`** ✅ — `backend/src/controllers/workoutController.ts:182`, still wired to a route. Remove or implement.
- **31. `refreshData()` clears `isRefreshing` before async work finishes** ⚠️ — `app/Mile A Day/Views/Dashboard/DashboardView.swift`. Spinner dismisses early. Tie the flag to the async completion.
- **32. Location accuracy gate uses strict `>0 && <50`** ⚠️ — `WorkoutLocationManager.swift`. Drops exactly-0/50m readings and doesn't special-case negative sentinels. Use `<=` bounds and handle invalid accuracy explicitly.
- **33. APIClient 15s timeout hardcoded for all endpoints** ⚠️ — no per-call override for legitimately slow operations.
- **34. Mass-assignment surface in `updateUser`** ✅ — whitelisted but unvalidated (no length/format checks). Add per-field validation.
- **35. Refresh-token reuse detection has a small pre-revocation race window** ⚠️ — `backend/src/services/refreshTokenService.ts`. Low risk given short token lifetimes (see #5).

---

## Confirmed false positives — do **not** ticket these

These were raised by automated passes and disproven during verification:

- **"Daily challenge endpoint is an unprotected IDOR."** False — `backend/src/controllers/dailyChallengeController.ts:23-26` gates non-self access with `areFriends`.
- **"`checkStreakLifeLoss` is undefined → cron crashes."** False — defined at `backend/src/services/notificationService.ts:775`.
- **"`/dev/*` mints tokens / sends pushes unauthenticated."** False — every dev controller self-gates on `NODE_ENV === 'production'`. (Residual: this relies on `NODE_ENV` actually being `production` in prod — worth a boot-time assertion, but the endpoints are not open.)
- **"Device registration auth bypass."** False — it's mounted behind `authenticateToken`.
- **SQL injection / committed secrets.** None found — queries are parameterized throughout, and no hardcoded secrets/keys were found in source. (Good.)

---

## Suggested sequencing

1. **P0 #1** (disk thrashing) and **P0 #2** (workout IDOR) — biggest reliability/security wins for the least code.
2. **Auth-hardening cluster** (#5, #7, #8, #10) — small, mechanical, high value; batch into one backend PR.
3. **iOS lifecycle cluster** (#4, #13, #20, #23, #24) — naturally one PR.
4. Then work down P1 → P3 by area.

---

_Generated from a read-only audit. Line numbers reflect the state of the code at
audit time and may have shifted since._
