# Daily Steps Tracking — Design

**Date:** 2026-04-28
**Branch:** `feature/daily-steps-tracking`

## Problem

The `ten_k_steps` daily challenge falsely shows as completed when a user has fewer than 10,000 actual steps but has logged multiple workouts in the same local day.

Root cause: iOS attaches the *full daily* HealthKit step count to *every* workout it syncs (`WorkoutSyncService.fetchDailySteps`, `WorkoutSyncService.swift:514, 594-615`), and the backend computes challenge progress with `SUM(workouts.steps) WHERE local_date = $2` (`dailyChallengeService.ts:170-177, 266-274`). Two workouts on the same day → `7,500 + 7,500 = 15,000` → clamped to 1.0 → `completed: true`.

The schema is also conceptually wrong: daily steps are a per-day fact, not a per-workout fact. Step totals belong on the day, not on each run.

## Goals

1. Fix the double-count: `ten_k_steps` reflects the user's true daily HealthKit step total.
2. Make daily step totals first-class on the backend so future features (step streaks, badges, future leaderboards) have a clean source.
3. Notify the user the moment they hit 10,000 steps, even when the app is backgrounded.
4. Keep network and battery cost low — no spamming the endpoint per step sample.
5. Respect a per-user notification preference, mirroring the existing Hype-reactions pattern.

## Non-Goals

- Backfilling historical days. New table starts empty; old `challenge_completions` rows are not re-evaluated.
- User-configurable step goal. Stays hardcoded at 10,000.
- Watch-app step writes. iPhone is the sole writer; HealthKit aggregates samples across devices.
- Server-side push notifications for step goal. The notification fires locally on the device, no APNs round-trip.
- Step-based competitions or friend leaderboards. Not designed for now; the schema and endpoint are general enough that they can be added later without rework.

## Architecture

A new `daily_steps` table replaces `workouts.steps` as the source of truth. iOS owns the sync via HealthKit background delivery + foreground sync + post-workout-sync hooks. The backend stores what it's told and never decreases a stored value. The `ten_k_steps` challenge reads from `daily_steps`.

```
HealthKit (device)
   │ (HKObserverQuery, scenePhase, post-workout)
   ▼
DailyStepsSyncService (iOS)  ── 10k crossing ──▶ Local UNNotification
   │ (PUT /users/:id/daily-steps, throttled)
   ▼
daily_steps (Postgres)
   │ (SELECT)
   ▼
dailyChallengeService.evaluateProgress / evaluatePredicate (ten_k_steps)
```

## Backend

### Schema changes

Run manually against prod (no migration system):

```sql
CREATE TABLE daily_steps (
  user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  local_date DATE NOT NULL,
  steps INT NOT NULL CHECK (steps >= 0),
  timezone_offset INT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, local_date)
);

CREATE INDEX idx_daily_steps_user_date ON daily_steps (user_id, local_date DESC);

ALTER TABLE workouts DROP COLUMN steps;

ALTER TABLE notification_settings
  ADD COLUMN step_goal_enabled BOOLEAN NOT NULL DEFAULT TRUE;
```

`user_id` is `TEXT` — the existing `users` table uses a `crypto.randomUUID()`-derived TEXT PK (`backend/scripts/badges-schema.sql` confirms this pattern). The `workouts.steps` DROP must be paired with removing the column from `workoutService.ts`'s INSERT/UPDATE in the same release, or the workout sync endpoint breaks.

### New endpoint

`PUT /users/:userId/daily-steps`

- Auth: `authenticateToken` + `requireSelfAccess('userId')`.
- Body:
  ```json
  { "localDate": "2026-04-28", "steps": 7500, "timezoneOffset": -300 }
  ```
- Validation: `localDate` must match `YYYY-MM-DD`; `steps >= 0`; `timezoneOffset` is integer minutes from UTC.
- SQL:
  ```sql
  INSERT INTO daily_steps (user_id, local_date, steps, timezone_offset)
  VALUES ($1, $2, $3, $4)
  ON CONFLICT (user_id, local_date)
  DO UPDATE SET
    steps = GREATEST(daily_steps.steps, EXCLUDED.steps),
    timezone_offset = EXCLUDED.timezone_offset,
    updated_at = NOW()
  RETURNING steps, updated_at;
  ```
- Response: `{ "steps": 7500, "updatedAt": "..." }`.
- `GREATEST` ensures stale/out-of-order POSTs can never roll the value backward — HealthKit can deliver late samples.

### Files (new)

- `backend/src/services/dailyStepsService.ts` — `upsertDailySteps(userId, localDate, steps, timezoneOffset)`, `getDailySteps(userId, localDate)`.
- `backend/src/controllers/dailyStepsController.ts` — request/response shaping, validation.
- `backend/src/routes/dailyStepsRoutes.ts` — wires `PUT /users/:userId/daily-steps` to controller, uses `requireSelfAccess('userId')`.

### Files (modified)

- `backend/src/server.ts` — mount `dailyStepsRoutes` after `authenticateToken`.
- `backend/src/services/dailyChallengeService.ts` — replace both `ten_k_steps` SUM queries (lines 170-177 and 266-274) with:
  ```sql
  SELECT steps FROM daily_steps WHERE user_id = $1 AND local_date = $2
  ```
  Treat missing row as 0 steps.
- `backend/src/services/notificationSettingsService.ts` — add `step_goal_enabled: boolean` to `NotificationPreferences` interface, `DEFAULT_PREFERENCES`, the `getNotificationPreferences` mapping, and the `updateNotificationPreferences` field list. (No `shouldSendNotification` change — the gate is enforced on the device, not the server, since this is a local notification.)
- `backend/src/services/workoutService.ts` — remove `steps` from the INSERT column list (line 20), the VALUES placeholder (line 22 — drops `$12`), the UPDATE clause (line 33), and the params array (line 68). Required because the column is being dropped in the same release.
- `backend/src/types/workouts.ts` — remove `steps` from the `Workout` interface.

## iOS

### New service: `DailyStepsSyncService.swift`

Location: `app/Mile A Day/Services/`.

Responsibilities:

1. Register `HKObserverQuery` on `.stepCount` and call `enableBackgroundDelivery(.immediate)` once at app launch.
2. On observer fire, foreground transition, or post-workout-sync trigger: query today's HealthKit step total, decide whether to POST (throttle below), check goal crossing, fire local notification if appropriate.
3. Post yesterday's count too on first foreground after a day rollover (handles phone-offline-overnight).

### Persisted state (UserDefaults keys)

- `dailySteps.lastPostedSteps: Int`
- `dailySteps.lastPostTimestamp: Date`
- `dailySteps.lastPostedDate: String` (YYYY-MM-DD)
- `dailySteps.goalNotifiedDate: String` (YYYY-MM-DD — last day a 10k notification fired)
- `dailySteps.stepGoalNotificationsEnabled: Bool` (mirrored from server, default true)

### Sync triggers

| Trigger | Throttled? | Notes |
| --- | --- | --- |
| `HKObserverQuery` wake-up | Yes | Coalesced ~5–15 min by iOS |
| `scenePhase == .active` / app launch | No | Always POST today |
| `lastPostedDate != today` on foreground | No | Also POST yesterday's final count once |
| Post-workout sync completed | No | Hook into `WorkoutSyncService` success |
| 10k threshold crossed | No | Always POST + fire notification |

### Throttle (background only)

POST if **any** of:

- `Date() - lastPostTimestamp >= 15 min` AND `currentSteps != lastPostedSteps`
- `currentSteps - lastPostedSteps >= 500`
- `currentSteps >= 10000` AND `lastPostedSteps < 10000` (goal crossing)
- `localDate != lastPostedDate` (new day)

Otherwise no-op.

On successful POST, update `lastPostedSteps`, `lastPostTimestamp`, `lastPostedDate`. POST failures are silently dropped — next trigger retries with the latest count.

### Goal-hit notification

When local count crosses 10,000 and `goalNotifiedDate != today` and `stepGoalNotificationsEnabled == true`:

```swift
let content = UNMutableNotificationContent()
content.title = "🎉 You hit 10,000 steps!"
content.body = "Daily step goal complete — keep moving!"
content.sound = .default
let request = UNNotificationRequest(
    identifier: "step-goal-\(todayLocalDate)",
    content: content,
    trigger: nil  // fires immediately
)
UNUserNotificationCenter.current().add(request)
```

Set `goalNotifiedDate = today` so it never duplicates within the day, even if HealthKit revises the count down then back up.

### Files (new)

- `app/Mile A Day/Services/DailyStepsSyncService.swift`

### Files (modified)

- `app/Mile A Day/MileADayApp.swift` (or current `@main` app entry) — instantiate `DailyStepsSyncService` and register the observer at launch; trigger `syncToday()` on `scenePhase` `.active`.
- `app/Mile A Day/Services/WorkoutSyncService.swift` — delete `fetchDailySteps(on:)` (lines 592-615), delete the `let steps = await fetchDailySteps(on: workout.startDate)` assignment (line 514), delete the `if let steps { workoutDict["steps"] = steps }` block (lines 529-531). On successful sync, call `DailyStepsSyncService.shared.syncToday()`.
- `app/Mile A Day/Views/Settings/NotificationSettingsView.swift` (or wherever Hype toggle lives) — add a "Step goal" toggle bound to `step_goal_enabled`. Update the local `stepGoalNotificationsEnabled` flag whenever prefs are fetched/updated.

## Edge cases

- **HealthKit revises down.** Backend `GREATEST` keeps the higher value; UI may briefly show a higher backend value than HealthKit until next sample push catches up. Acceptable.
- **Step count fluctuates around 10k after notification.** `goalNotifiedDate == today` blocks duplicate notifications.
- **Day rollover at midnight.** Next observer wake-up sees `localDate != lastPostedDate` → forced POST creates new row. `goalNotifiedDate` is per-day so the new day can re-trigger.
- **Timezone change mid-day.** Whichever date the device computes is the date that gets written. `GREATEST` per-row prevents corruption; could result in two rows for two adjacent local dates after a flight. Acceptable.
- **Multiple devices.** Watch app does not run this service. iPhone is sole writer. HealthKit aggregates across devices, so iPhone reads the union.
- **Offline.** POST failures are silently retried on next trigger. No queue — HealthKit is the source of truth.
- **First launch after update.** No backfill (per Q2). First observer fire / foreground creates today's row. Older days remain absent.
- **Notification permission not granted.** `UNUserNotificationCenter.add` silently fails — acceptable. The toggle is a no-op until system permission is granted.

## Testing & verification

No automated test runner exists. Verification is manual:

1. **Backend build clean** (`cd backend && npm run build`).
2. **DB schema applied manually** in dev DB — create `daily_steps`, drop `workouts.steps`, add `step_goal_enabled`.
3. **iOS build clean** (Xcode).
4. **End-to-end manual scenarios:**
   - Walk to ~5k → confirm `daily_steps.steps` updates within ~15 min via `psql`.
   - Cross 10k → confirm local notification fires + DB row updates immediately.
   - Open app cold next morning → confirm yesterday's row is final and today's row exists with morning count.
   - Toggle "Step goal" off → cross 10k → no notification fires.
   - Hit 10k → `GET /users/:id/challenges/today` returns `progress: 1.0, completed: true`.
   - Run two short workouts in one day with <10k steps → challenge does NOT auto-complete (regression test for the bug).

## Rollout

Single-phase rollout — old iOS clients sending `steps` in the workout sync JSON body have that field silently ignored by the new backend (Express does not 4xx on unknown JSON fields).

Order matters because old-backend + dropped-column = broken INSERT. Safe sequence:

1. **Apply additive DB changes** in prod: `CREATE TABLE daily_steps`, `CREATE INDEX idx_daily_steps_user_date`, `ALTER TABLE notification_settings ADD COLUMN step_goal_enabled`. These are safe while the old backend is running.
2. **Deploy backend** with: new daily-steps endpoint, updated `workoutService.ts` (no `steps` references), updated `dailyChallengeService.ts` (reads `daily_steps`), updated `notificationSettingsService.ts` (`step_goal_enabled` field).
3. **Drop the dead column**: `ALTER TABLE workouts DROP COLUMN steps`. Now safe — no code path references it.
4. **Ship iOS update** with `DailyStepsSyncService`, `WorkoutSyncService` cleanup, and Step-goal toggle. Old iOS clients continue to function (their extra `steps` JSON field is ignored).
