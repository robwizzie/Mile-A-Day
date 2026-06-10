# Mile A Day — Audit Issues (copy-paste ready)

One block per finding. Copy the **Title** into the issue title and everything under **Body** into the description. Suggested labels are included. Source: `AUDIT.md`.

Confidence: ✅ verified in code · ⚠️ reported, confirm when scoping.

---

## P0 — Critical

### Issue 1
**Title:** `[P0] Active workout writes full state to UserDefaults every second (disk thrashing / jank)`

**Body:**
> **Labels:** bug, performance, ios, P0
> **Confidence:** ✅ verified
>
> **Summary**
> During an active workout, the entire in-progress state — including up to 5,000 route points (hundreds of KB once JSON-encoded) — is re-encoded and written to `UserDefaults` on every GPS/timer tick, followed by a forced `synchronize()`.
>
> **Why it matters**
> `UserDefaults` is a plist store, not a database. Re-serializing a large blob ~1×/sec and force-flushing it blocks the main thread (jank), drains battery on long outdoor runs, wears flash storage, and risks silent write failures / state corruption as the blob grows. Highest-impact reliability issue in the app.
>
> **Where**
> - `app/Mile A Day/Core/State/InProgressWorkoutStore.swift` (`save` + `synchronize()`)
> - `app/Mile A Day/Views/Dashboard/WorkoutTrackingView.swift` (1 Hz timer / `flushRoutePoints`)
>
> **Fix direction**
> Persist only a small "resume header" (start time, elapsed, cumulative distance) frequently; append route points to a separate append-only store (file/SQLite) on a throttled cadence. Remove `synchronize()`.
>
> **Acceptance criteria**
> - [ ] No full-state encode+write on every tick.
> - [ ] Route persistence throttled and/or moved off `UserDefaults`.
> - [ ] Workout still fully recoverable after force-quit mid-run.
> - [ ] No measurable main-thread stalls during a 60-min GPS run.

---

### Issue 2
**Title:** `[P0] IDOR: workout endpoints (streak/recent/stats) have no self/friend authorization`

**Body:**
> **Labels:** security, backend, P0
> **Confidence:** ✅ verified
>
> **Summary**
> `getStreak`, `getRecentWorkouts`, and `getUserStats` are mounted after `authenticateToken` but only check the target user *exists* — not that the requester is that user or a friend. Any authenticated user can read anyone's workout history, distances, dates, and streak by supplying another `userId`.
>
> **Why it matters**
> Private fitness data is exposed to any logged-in account. Internally inconsistent: the daily-challenge endpoint already gates non-self access via `areFriends` (`dailyChallengeController.ts:23-26`).
>
> **Where**
> - `backend/src/routes/workoutRoutes.ts:9-12`
> - `backend/src/controllers/workoutController.ts` (`getStreak`, `getRecentWorkouts`, `getUserStats`)
>
> **Fix direction**
> Add `requireSelfAccess('userId')` where only the owner should read, or a "self-or-friend" check mirroring `dailyChallengeController` where friends are meant to see the data.
>
> **Acceptance criteria**
> - [ ] Requesting another user's workout data without the required relationship returns 403.
> - [ ] Self and (where intended) friends still succeed.
> - [ ] Consistent policy documented for all `/workouts/:userId/*` reads.

---

### Issue 3
**Title:** `[P0] Manual workout entry allows fabricated distance/pace/date (cheating vector)`

**Body:**
> **Labels:** security, bug, backend, ios, P0
> **Confidence:** ✅ backend gap verified · ⚠️ client specifics
>
> **Summary**
> Client validation only requires `0 < distance < 100` and `duration > 0`, and allows back-dating up to 30 days ("99 miles in 1 second" passes). The backend upload path performs no plausibility validation.
>
> **Why it matters**
> Streaks, total miles, leaderboards, and pace PRs can be arbitrarily inflated — corrupting the core competitive loop and all social comparisons.
>
> **Where**
> - `app/Mile A Day/Views/Dashboard/ManualWorkoutEntryView.swift` (~86-90)
> - `app/Mile A Day/Services/WorkoutService.swift` (upload)
> - backend `uploadWorkouts`
>
> **Fix direction**
> Enforce server-side plausibility bounds (max distance/workout, minimum pace floor, date window, per-day caps). Treat client validation as UX only.
>
> **Acceptance criteria**
> - [ ] Backend rejects implausible distance/pace/date with a clear error.
> - [ ] Bounds documented and shared with the client for matching UX validation.
> - [ ] Existing legitimate manual entries unaffected.

---

### Issue 4
**Title:** `[P0] Stacked NotificationCenter observers & un-invalidated timers on Dashboard`

**Body:**
> **Labels:** bug, performance, ios, P0
> **Confidence:** ⚠️ reported
>
> **Summary**
> Observers (`WorkoutIndexReady`, `MAD_OpenWorkoutFromLiveActivity`) are added in `onAppear` with no removal; a 1 Hz banner `Timer` is started in `onAppear` with no `onDisappear` invalidate. Each appear (tab switch / nav pop) adds another.
>
> **Why it matters**
> Handlers fire N times for one event — duplicate celebrations, repeated expensive index rebuilds, the workout view flipping open unexpectedly. The banner timer keeps reloading state from disk every second after dismissal (battery + retain cycle).
>
> **Where**
> - `app/Mile A Day/Views/Dashboard/DashboardView.swift` (~351-398)
> - `app/Mile A Day/Views/Dashboard/WorkoutLocationManager.swift` (~234)
>
> **Fix direction**
> Pair every `addObserver`/`scheduledTimer` with cleanup in `onDisappear` (or use auto-cancelling `.onReceive`/structured concurrency). Store and remove observer tokens.
>
> **Acceptance criteria**
> - [ ] Re-appearing the dashboard does not multiply observer callbacks.
> - [ ] Banner timer stops when the banner disappears.
> - [ ] No duplicate celebrations after repeated tab switches.

---

## P1 — High

### Issue 5
**Title:** `[P1] Access tokens live 30 days and are effectively unrevocable`

**Body:**
> **Labels:** security, backend, P1
> **Confidence:** ✅ verified
>
> **Summary**
> `ACCESS_TOKEN_EXPIRY = '30d'` and access tokens aren't checked against the DB on each request (stateless verify only).
>
> **Why it matters**
> A leaked access token works for a month and can't be revoked via the refresh-token rotation system, which never consults server state for access tokens.
>
> **Where**
> - `backend/src/services/tokenService.ts:5`
>
> **Fix direction**
> Shorten access-token lifetime to minutes/hours; rely on the existing refresh flow for renewal.
>
> **Acceptance criteria**
> - [ ] Access-token TTL reduced to a short window.
> - [ ] Client refresh flow verified to renew transparently.

---

### Issue 6
**Title:** `[P1] Global error handler leaks internal error messages to clients`

**Body:**
> **Labels:** security, backend, P1
> **Confidence:** ✅ verified
>
> **Summary**
> 500 responses include raw `err.message` (DB errors, file paths, library internals); several controllers also concatenate `error.message` into responses.
>
> **Why it matters**
> Information disclosure that helps map the system and leaks implementation detail to ordinary clients.
>
> **Where**
> - `backend/src/server.ts:86-92` (+ various controllers)
>
> **Fix direction**
> Return a generic message + correlation id to clients; log full detail server-side only.
>
> **Acceptance criteria**
> - [ ] 5xx responses contain no raw internal error text.
> - [ ] Full errors still logged server-side with a correlatable id.

---

### Issue 7
**Title:** `[P1] JWT secret used without validation (silent auth failure if unset)`

**Body:**
> **Labels:** security, backend, P1
> **Confidence:** ✅ verified
>
> **Summary**
> `process.env.APP_JWT_SECRET!` and the middleware encode the secret unchecked. If unset, `TextEncoder().encode(undefined)` produces the bytes of `"undefined"`, and all tokens are signed/verified with that key.
>
> **Why it matters**
> Catastrophic, silent auth weakness — a known misconfiguration lets anyone forge tokens.
>
> **Where**
> - `backend/src/services/tokenService.ts:4`
> - `backend/src/middleware/auth.ts`
>
> **Fix direction**
> Validate required secrets at boot; crash fast if absent. Never sign/verify with a fallback.
>
> **Acceptance criteria**
> - [ ] App refuses to start if `APP_JWT_SECRET` is missing/empty.
> - [ ] No code path encodes an undefined secret.

---

### Issue 8
**Title:** `[P1] Unbounded query limits enable DoS / huge payloads`

**Body:**
> **Labels:** security, performance, backend, P1
> **Confidence:** ✅ verified
>
> **Summary**
> `getRecentWorkouts` passes a `null` limit → unbounded rows; notification inbox uses `parseInt(limit)` with no cap and no negative/NaN handling. `?limit=99999999` is accepted.
>
> **Why it matters**
> Memory pressure / DoS and odd SQL behavior on negative/NaN inputs.
>
> **Where**
> - `backend/src/controllers/workoutController.ts:187-201`
> - `backend/src/controllers/inAppNotificationController.ts:100-101`
>
> **Fix direction**
> Apply the existing `clampLimit`/`clampOffset` helpers consistently; reject non-numeric/negative input.
>
> **Acceptance criteria**
> - [ ] All list endpoints enforce a max page size.
> - [ ] Negative/NaN limit/offset rejected or clamped.

---

### Issue 9
**Title:** `[P1] Multi-write operations are not transactional (createCompetition, accept friend)`

**Body:**
> **Labels:** bug, data-integrity, backend, P1
> **Confidence:** ✅ verified
>
> **Summary**
> `createCompetition` inserts the competition then the owner membership as two separate statements; the friend-accept double-write has the same shape. No transaction.
>
> **Why it matters**
> A failure between statements leaves corrupt partial state — a competition with no members, or a one-directional friendship.
>
> **Where**
> - `backend/src/services/competitionService.ts:74-91`
> - `backend/src/services/friendshipService.ts` (accept-request)
>
> **Fix direction**
> Wrap each multi-statement mutation in `db.transaction()` (all-or-nothing).
>
> **Acceptance criteria**
> - [ ] Competition creation is atomic.
> - [ ] Friend-accept is atomic.
> - [ ] Simulated mid-operation failure leaves no partial rows.

---

### Issue 10
**Title:** `[P1] User search returns full rows including email (PII / enumeration)`

**Body:**
> **Labels:** security, backend, P1
> **Confidence:** ✅ verified
>
> **Summary**
> `SELECT * FROM users WHERE username ILIKE $1 OR email ILIKE $1 LIMIT 50` returns all columns and matches on email.
>
> **Why it matters**
> Email/PII disclosure and user enumeration via search.
>
> **Where**
> - `backend/src/controllers/usersController.ts:32`
>
> **Fix direction**
> Select only public columns; stop matching on email (or move exact-email lookup behind a separate, rate-limited path).
>
> **Acceptance criteria**
> - [ ] Search results exclude email and other private fields.
> - [ ] Username search behavior unchanged for users.

---

### Issue 11
**Title:** `[P1] Auth tokens persisted in plaintext UserDefaults (and sent to watch)`

**Body:**
> **Labels:** security, ios, P1
> **Confidence:** ⚠️ reported
>
> **Summary**
> `TokenStore` writes Keychain **and** mirrors tokens to `UserDefaults`; legacy readers and the watch bridge read the plaintext copy. The access token is shipped to the watch via application context.
>
> **Why it matters**
> Plaintext tokens land in device/iCloud backups; a compromised backup or watch yields working credentials.
>
> **Where**
> - `app/Mile A Day/Services/TokenStore.swift`
> - `FriendService`, `WorkoutService`, `ProfileImageService`, `DailyStepsSyncService`
> - `app/Mile A Day/Models/HealthKitManager.swift` (watch bridge)
>
> **Fix direction**
> Make Keychain the single source of truth; delete the `UserDefaults` mirror; stop sending the access token to the watch.
>
> **Acceptance criteria**
> - [ ] No token written to `UserDefaults`.
> - [ ] All readers use Keychain via `TokenStore`.
> - [ ] Watch no longer receives the access token.

---

### Issue 12
**Title:** `[P1] Widget exhausts refresh budget and has no midnight rollover`

**Body:**
> **Labels:** bug, ux, ios, widgets, P1
> **Confidence:** ✅ verified
>
> **Summary**
> The timeline requests refreshes every 60s (WidgetKit caps daily refreshes, so it freezes), has no entry at local midnight (shows yesterday's miles after midnight), and `WidgetDataStore` triggers two reloads per save.
>
> **Why it matters**
> Widgets look broken/stale — a visible, everyday UX failure.
>
> **Where**
> - `app/Mile A Day/Widgets/TodayProgressWidget.swift:48`
> - `app/Mile A Day/Shared/WidgetDataStore.swift`
>
> **Fix direction**
> Use a realistic refresh cadence; add an explicit timeline entry at next local midnight (reset to 0); de-dup reload calls.
>
> **Acceptance criteria**
> - [ ] Widget no longer freezes from budget exhaustion.
> - [ ] Widget resets to 0 at local midnight.
> - [ ] Single reload per data change.

---

### Issue 13
**Title:** `[P1] Duplicate refresh storms on launch/foreground (MainTabView)`

**Body:**
> **Labels:** performance, ios, P1
> **Confidence:** ✅ verified
>
> **Summary**
> `.task` and `.onChange(of: scenePhase == .active)` both call `competitionService.refreshAllData()` + `friendService.refreshAllData()` + unread count. Cold launch + first foreground runs each twice.
>
> **Why it matters**
> Doubles network/battery on every foreground; can delay first paint behind redundant requests.
>
> **Where**
> - `app/Mile A Day/Views/MainTabView.swift`
>
> **Fix direction**
> Add a minimum-interval / in-flight guard per service so overlapping triggers coalesce.
>
> **Acceptance criteria**
> - [ ] Each dataset fetched at most once per launch/foreground burst.
> - [ ] No regression in freshness on tab switch.

---

### Issue 14
**Title:** `[P1] O(n) stat recomputation runs on the main thread at launch`

**Body:**
> **Labels:** performance, ios, P1
> **Confidence:** ⚠️ reported
>
> **Summary**
> `recalculateStatsWithAllWorkouts()` runs on the main queue over the full cached-workout array after updates.
>
> **Why it matters**
> Large histories block UI 100-500ms during cold launch and stutter animations.
>
> **Where**
> - `app/Mile A Day/Models/HealthKitManager+DataFetching.swift`
>
> **Fix direction**
> Move computation off-main and publish results back; consider incremental updates.
>
> **Acceptance criteria**
> - [ ] No main-thread stall attributable to stat recompute on launch.
> - [ ] Stats values unchanged.

---

### Issue 15
**Title:** `[P1] Cron jobs fan out serially over unbounded user/competition sets`

**Body:**
> **Labels:** performance, scalability, backend, P1
> **Confidence:** ✅ logic · ⚠️ scale
>
> **Summary**
> `silentSyncCron` iterates `SELECT DISTINCT user_id` awaiting each push serially; `checkCompetitionsEndingSoon` / `checkStreaksBroken` scan unbounded sets and re-query per row.
>
> **Why it matters**
> One slow push blocks the rest; runtime grows linearly with users — will choke as the base grows.
>
> **Where**
> - `backend/src/cron/silentSyncCron.ts`
> - `backend/src/services/notificationService.ts`
>
> **Fix direction**
> Page through users; fan out in bounded-concurrency batches; pre-aggregate where possible.
>
> **Acceptance criteria**
> - [ ] Cron uses pagination + bounded concurrency.
> - [ ] One slow recipient no longer blocks the batch.

---

## P2 — Medium

### Issue 16
**Title:** `[P2] Fire-and-forget async IIFE in upload path swallows errors`

**Body:**
> **Labels:** bug, backend, P2
> **Confidence:** ✅ verified
>
> **Summary**
> An un-awaited async IIFE runs `checkLeadChanges` / `checkCompetitionMilestones`; rejections escape the surrounding try, so failures are invisible while upload returns 200.
>
> **Where**
> - `backend/src/controllers/workoutController.ts:95-103`
>
> **Fix direction**
> Await and handle, or hand off to a job queue with its own error handling.
>
> **Acceptance criteria**
> - [ ] Lead-change/milestone failures are logged/handled, not silently dropped.

---

### Issue 17
**Title:** `[P2] Invalid push-token cleanup errors silently ignored`

**Body:**
> **Labels:** bug, backend, P2
> **Confidence:** ⚠️ reported
>
> **Summary**
> `removeInvalidToken(...).catch(() => {})` — dead device tokens accumulate forever; APNs/FCM failures are masked.
>
> **Where**
> - `backend/src/services/pushNotificationService.ts:162,377`
>
> **Fix direction**
> Log failures; surface to the cron error handler.
>
> **Acceptance criteria**
> - [ ] Cleanup failures are logged.
> - [ ] Dead tokens are actually removed.

---

### Issue 18
**Title:** `[P2] Sensitive data logged via print() (tokens, full responses, APNs token)`

**Body:**
> **Labels:** security, ios, P2
> **Confidence:** ⚠️ reported
>
> **Summary**
> Raw API responses (up to 2000 chars), "auth token present", and APNs token prefix are logged.
>
> **Where**
> - `app/Mile A Day/Services/APIClient.swift` (~203)
> - `TokenRefreshService`, `FriendService`, `AppDelegate`
>
> **Fix direction**
> Gate verbose logs behind `#if DEBUG`; never log token material or full bodies.
>
> **Acceptance criteria**
> - [ ] Release builds emit no token/PII/response-body logs.

---

### Issue 19
**Title:** `[P2] Hard-coded backend user id + ungated Developer Settings`

**Body:**
> **Labels:** security, ios, P2
> **Confidence:** ⚠️ reported
>
> **Summary**
> A real backend user id is hard-coded in dev settings, and the Developer Settings screen is reachable in release builds.
>
> **Where**
> - `app/Mile A Day/Views/Settings/DeveloperSettingsView.swift` (~480)
>
> **Fix direction**
> Remove the hard-coded id; wrap Developer Settings in `#if DEBUG`.
>
> **Acceptance criteria**
> - [ ] No hard-coded user id in source.
> - [ ] Developer Settings absent from release builds.

---

### Issue 20
**Title:** `[P2] Concurrent UserDefaults writes can drop synced-workout ids`

**Body:**
> **Labels:** bug, data-integrity, ios, P2
> **Confidence:** ⚠️ reported
>
> **Summary**
> `markWorkoutsAsSynced` does read-union-write with no mutual exclusion across concurrent batches; `uploadedWorkoutIds` also grows unbounded.
>
> **Where**
> - `app/Mile A Day/Services/WorkoutSyncService.swift`
>
> **Fix direction**
> Serialize updates (actor/queue); store sync state in a DB keyed by workout id rather than one growing array.
>
> **Acceptance criteria**
> - [ ] Concurrent batch completion can't drop ids.
> - [ ] Sync-state storage is bounded.

---

### Issue 21
**Title:** `[P2] updateFriendSettings doesn't verify the friendship`

**Body:**
> **Labels:** security, backend, P2
> **Confidence:** ⚠️ reported
>
> **Summary**
> Takes `:friendId` and writes per-friend notification settings without confirming a friendship exists.
>
> **Where**
> - `backend/src/controllers/notificationSettingsController.ts`
>
> **Fix direction**
> Validate the friendship before writing.
>
> **Acceptance criteria**
> - [ ] Writing settings for a non-friend id is rejected.

---

### Issue 22
**Title:** `[P2] Nudge/flex logging has no idempotency`

**Body:**
> **Labels:** bug, backend, P2
> **Confidence:** ⚠️ reported
>
> **Summary**
> Inserts without a unique constraint; rapid double-taps double-log and can double-count against rate limits.
>
> **Where**
> - `backend/src/services/pushNotificationService.ts:544,584`
>
> **Fix direction**
> Add a unique constraint (e.g. per sender/target/day) with `ON CONFLICT DO NOTHING`.
>
> **Acceptance criteria**
> - [ ] Duplicate nudge/flex in the same window is a no-op.

---

### Issue 23
**Title:** `[P2] Workout tracking view stops timer but not location on disappear`

**Body:**
> **Labels:** bug, performance, ios, P2
> **Confidence:** ⚠️ reported
>
> **Summary**
> `onDisappear` invalidates the timer but doesn't stop location tracking; dismissing without ending a workout can leave GPS running.
>
> **Where**
> - `app/Mile A Day/Views/Dashboard/WorkoutTrackingView.swift`
>
> **Fix direction**
> Stop location tracking on disappear unless an explicit background-tracking state is intended.
>
> **Acceptance criteria**
> - [ ] GPS stops when the tracking view is dismissed without an active background workout.

---

### Issue 24
**Title:** `[P2] Remove deprecated UserDefaults.synchronize() calls`

**Body:**
> **Labels:** cleanup, performance, ios, P2
> **Confidence:** ⚠️ reported
>
> **Summary**
> Multiple `synchronize()` call sites; unnecessary since iOS 13 and adds main-thread stalls.
>
> **Where**
> - `InProgressWorkoutStore`, `WorkoutSyncService`, others
>
> **Fix direction**
> Remove the calls; rely on automatic persistence.
>
> **Acceptance criteria**
> - [ ] No `synchronize()` calls remain.

---

### Issue 25
**Title:** `[P2] N+1 in checkCompetitionMilestones`

**Body:**
> **Labels:** performance, backend, P2
> **Confidence:** ⚠️ reported
>
> **Summary**
> Full `getCompetition()` per competition in a loop — one aggregation round-trip each; slow for users in many competitions.
>
> **Where**
> - `backend/src/services/notificationService.ts:286-291`
>
> **Fix direction**
> Batch the needed data in a single query or parallelize with a bound.
>
> **Acceptance criteria**
> - [ ] No per-competition full fetch in the loop.

---

### Issue 26
**Title:** `[P2] Stale celebrations replay on foreground`

**Body:**
> **Labels:** bug, ux, ios, P2
> **Confidence:** ⚠️ reported
>
> **Summary**
> Celebrations queued while backgrounded replay on return even when no longer relevant.
>
> **Where**
> - `app/Mile A Day/Managers/CelebrationManager.swift`
>
> **Fix direction**
> Timestamp queued celebrations; drop stale ones on foreground.
>
> **Acceptance criteria**
> - [ ] No outdated celebration shown after returning to foreground.

---

### Issue 27
**Title:** `[P2] Device-token registration auth depends on route mount order`

**Body:**
> **Labels:** security, backend, P2
> **Confidence:** ✅ verified (not currently exploitable)
>
> **Summary**
> The endpoint is protected only because it's mounted after `authenticateToken`; a future reorder silently opens unauthenticated token registration.
>
> **Where**
> - `backend/src/routes/deviceRoutes.ts` + `server.ts` mount order
>
> **Fix direction**
> Add an explicit auth guard on the route so safety doesn't depend on ordering.
>
> **Acceptance criteria**
> - [ ] Route enforces auth independently of mount order.

---

## P3 — Low / cleanup

### Issue 28
**Title:** `[P3] Wildcard CORS + no rate limit on /public/profile-image/:username`

**Body:**
> **Labels:** security, backend, P3 · **Confidence:** ✅
> Public endpoint sets `Access-Control-Allow-Origin: *` with no rate limiting → enumeration surface.
> **Where:** `backend/src/server.ts:49-67`
> **Fix:** Restrict origins; add rate limiting.
> - [ ] Origins restricted and/or endpoint rate-limited.

---

### Issue 29
**Title:** `[P3] No rate limiting on /auth/* endpoints`

**Body:**
> **Labels:** security, backend, P3 · **Confidence:** ✅
> Mitigated by Sign in with Apple, but a limiter is still good practice.
> **Where:** `backend/src/routes/authRoutes.ts`
> **Fix:** Add request throttling.
> - [ ] Auth endpoints rate-limited.

---

### Issue 30
**Title:** `[P3] Dead code: empty getWorkoutRange() still wired to a route`

**Body:**
> **Labels:** cleanup, backend, P3 · **Confidence:** ✅
> **Where:** `backend/src/controllers/workoutController.ts:182` (+ `workoutRoutes.ts:10`)
> **Fix:** Remove or implement.
> - [ ] Empty handler/route removed or implemented.

---

### Issue 31
**Title:** `[P3] refreshData() clears isRefreshing before async work finishes`

**Body:**
> **Labels:** bug, ux, ios, P3 · **Confidence:** ⚠️
> Pull-to-refresh spinner dismisses early.
> **Where:** `app/Mile A Day/Views/Dashboard/DashboardView.swift`
> **Fix:** Tie the flag to async completion.
> - [ ] Spinner persists until data actually loads.

---

### Issue 32
**Title:** `[P3] Location accuracy gate uses strict >0 && <50 bounds`

**Body:**
> **Labels:** bug, ios, P3 · **Confidence:** ⚠️
> Drops exactly-0/50m readings; no negative-sentinel handling.
> **Where:** `app/Mile A Day/Views/Dashboard/WorkoutLocationManager.swift`
> **Fix:** Use `<=` bounds; handle invalid (negative) accuracy explicitly.
> - [ ] Valid edge-case readings no longer dropped.

---

### Issue 33
**Title:** `[P3] APIClient 15s timeout hardcoded for all endpoints`

**Body:**
> **Labels:** enhancement, ios, P3 · **Confidence:** ⚠️
> No per-call override for legitimately slow operations.
> **Where:** `app/Mile A Day/Services/APIClient.swift`
> **Fix:** Allow per-request timeout override.
> - [ ] Callers can specify a timeout.

---

### Issue 34
**Title:** `[P3] updateUser mass-assignment whitelist lacks field validation`

**Body:**
> **Labels:** security, backend, P3 · **Confidence:** ✅
> Whitelisted but unvalidated (no length/format checks).
> **Where:** `backend/src/controllers/usersController.ts` (`updateUser`)
> **Fix:** Add per-field validation (lengths, formats).
> - [ ] Invalid field values rejected.

---

### Issue 35
**Title:** `[P3] Refresh-token reuse detection has a small pre-revocation race window`

**Body:**
> **Labels:** security, backend, P3 · **Confidence:** ⚠️
> Low risk given short token lifetimes (see Issue 5).
> **Where:** `backend/src/services/refreshTokenService.ts`
> **Fix:** Tighten rotation/revocation ordering.
> - [ ] Reused token can't be replayed in the race window.

---

## Not issues — confirmed false positives (do not file)

- **Daily challenge IDOR** — gated by `areFriends` (`dailyChallengeController.ts:23-26`).
- **`checkStreakLifeLoss` undefined** — defined at `notificationService.ts:775`.
- **`/dev/*` unauthenticated** — every dev controller self-gates on `NODE_ENV === 'production'`. (Optional: add a boot assertion that `NODE_ENV` is set in prod.)
- **Device registration auth bypass** — mounted behind `authenticateToken`.
- **SQL injection / committed secrets** — none found; queries parameterized throughout.
