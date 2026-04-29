# Daily Steps Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the buggy `SUM(workouts.steps)` daily step total with a dedicated `daily_steps` table written by a throttled iOS sync service, and notify the user the moment they hit their 10k step goal.

**Architecture:** New `daily_steps (user_id, local_date, steps, …)` table with `GREATEST` UPSERT semantics. iOS owns the sync via HKObserverQuery + foreground hook + post-workout hook, with a throttle to keep network cost low. The `ten_k_steps` daily challenge reads from `daily_steps`. The `workouts.steps` column is dropped. Step-goal local notification is gated by a new `step_goal_enabled` preference.

**Tech Stack:** Express 5.1 + TypeScript (ESM, `.js` import suffix) on the backend; PostgreSQL via the `PostgresService` singleton; SwiftUI + HealthKit on iOS. No test runners — verification is `npm run build` + Xcode build + manual scenarios.

---

## Spec reference

Implements `docs/superpowers/specs/2026-04-28-daily-steps-tracking-design.md`.

Read the spec for context before starting. This plan implements every section: schema, endpoint, challenge fix, iOS sync service, notification toggle, rollout.

---

## Conventions

- **Backend imports** end in `.js` even though source is `.ts` (ESM rule).
- **Backend SQL** uses parameterized queries via `PostgresService.getInstance()`.
- **Routes** live in `routes/`, controllers in `controllers/`, services in `services/`. Routes register in `server.ts` after `authenticateToken`.
- **iOS new code** uses `@Observable` where appropriate. Network calls go through `APIClient.fancyFetch`.
- **No tests exist.** Verification is "code compiles" + "manual scenario walked through". Each task ends with `npm run build` (backend) or a build expectation note (iOS). Don't invent tests.
- **Commits** are frequent and atomic — one task = one commit. Use `--no-verify` only if a hook fails for unrelated reasons; otherwise let hooks run.

---

## Task 1: Add `daily_steps` schema documentation

**Files:**
- Create: `backend/scripts/daily-steps-schema.sql`

This file is a runnable SQL script the operator can use to apply the additive DB changes (CREATE TABLE + ADD COLUMN). The DROP COLUMN happens in Task 7 after backend code stops referencing it.

- [ ] **Step 1: Create the schema file**

```sql
-- Daily Steps Tracking — additive changes (apply BEFORE backend deploy)
-- See docs/superpowers/specs/2026-04-28-daily-steps-tracking-design.md

CREATE TABLE IF NOT EXISTS daily_steps (
    user_id          TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    local_date       DATE NOT NULL,
    steps            INT  NOT NULL CHECK (steps >= 0),
    timezone_offset  INT  NOT NULL,
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, local_date)
);

CREATE INDEX IF NOT EXISTS idx_daily_steps_user_date
    ON daily_steps (user_id, local_date DESC);

ALTER TABLE notification_settings
    ADD COLUMN IF NOT EXISTS step_goal_enabled BOOLEAN NOT NULL DEFAULT TRUE;

-- AFTER backend deploy of feature/daily-steps-tracking, run separately:
-- ALTER TABLE workouts DROP COLUMN steps;
```

- [ ] **Step 2: Commit**

```bash
git add backend/scripts/daily-steps-schema.sql
git commit -m "Add daily_steps schema script"
```

---

## Task 2: Add `dailyStepsService` (backend)

**Files:**
- Create: `backend/src/services/dailyStepsService.ts`

Service exposes one function: `upsertDailySteps`. Returns the resulting `steps` (post-`GREATEST`) and the `updatedAt` timestamp. No `getDailySteps` exported here — the challenge service inlines the SELECT to keep the call boundary minimal.

- [ ] **Step 1: Create the service**

```typescript
import { PostgresService } from './DbService.js';

const db = PostgresService.getInstance();

export interface UpsertDailyStepsResult {
	steps: number;
	updatedAt: string;
}

/**
 * Insert or update a user's step total for a given local date.
 * Uses GREATEST so out-of-order or stale POSTs cannot decrease the stored value
 * — HealthKit can deliver late samples.
 */
export async function upsertDailySteps(
	userId: string,
	localDate: string,
	steps: number,
	timezoneOffset: number
): Promise<UpsertDailyStepsResult> {
	const rows = await db.query<{ steps: number; updated_at: string }>(
		`INSERT INTO daily_steps (user_id, local_date, steps, timezone_offset)
		 VALUES ($1, $2, $3, $4)
		 ON CONFLICT (user_id, local_date)
		 DO UPDATE SET
		     steps = GREATEST(daily_steps.steps, EXCLUDED.steps),
		     timezone_offset = EXCLUDED.timezone_offset,
		     updated_at = NOW()
		 RETURNING steps, updated_at::text AS updated_at`,
		[userId, localDate, steps, timezoneOffset]
	);

	const row = rows[0];
	return {
		steps: row.steps,
		updatedAt: row.updated_at,
	};
}
```

- [ ] **Step 2: Build**

```bash
cd backend && npm run build
```

Expected: clean build, no errors.

- [ ] **Step 3: Commit**

```bash
git add backend/src/services/dailyStepsService.ts
git commit -m "Add dailyStepsService with GREATEST upsert"
```

---

## Task 3: Add `dailyStepsController` and route (backend)

**Files:**
- Create: `backend/src/controllers/dailyStepsController.ts`
- Create: `backend/src/routes/dailyStepsRoutes.ts`

- [ ] **Step 1: Write the controller**

```typescript
// backend/src/controllers/dailyStepsController.ts
import { Response } from 'express';
import { AuthenticatedRequest } from '../middleware/auth.js';
import { upsertDailySteps } from '../services/dailyStepsService.js';

const LOCAL_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

export async function putDailySteps(req: AuthenticatedRequest, res: Response) {
	try {
		const userId = req.params.userId;
		const { localDate, steps, timezoneOffset } = req.body ?? {};

		if (typeof localDate !== 'string' || !LOCAL_DATE_RE.test(localDate)) {
			return res.status(400).json({ error: 'localDate must be YYYY-MM-DD' });
		}
		if (typeof steps !== 'number' || !Number.isFinite(steps) || steps < 0) {
			return res.status(400).json({ error: 'steps must be a non-negative number' });
		}
		if (typeof timezoneOffset !== 'number' || !Number.isInteger(timezoneOffset)) {
			return res.status(400).json({ error: 'timezoneOffset must be an integer' });
		}

		const result = await upsertDailySteps(userId, localDate, Math.floor(steps), timezoneOffset);
		return res.status(200).json(result);
	} catch (err: any) {
		console.error('Error upserting daily steps:', err.message);
		return res.status(500).json({ error: 'Error upserting daily steps: ' + err.message });
	}
}
```

- [ ] **Step 2: Write the route**

```typescript
// backend/src/routes/dailyStepsRoutes.ts
import { Router } from 'express';
import { putDailySteps } from '../controllers/dailyStepsController.js';
import { requireSelfAccess } from '../middleware/auth.js';

const router = Router();

router.put('/:userId/daily-steps', requireSelfAccess('userId'), putDailySteps);

export default router;
```

- [ ] **Step 3: Build**

```bash
cd backend && npm run build
```

Expected: clean build.

- [ ] **Step 4: Commit**

```bash
git add backend/src/controllers/dailyStepsController.ts backend/src/routes/dailyStepsRoutes.ts
git commit -m "Add daily-steps endpoint (PUT /users/:userId/daily-steps)"
```

---

## Task 4: Mount route in `server.ts`

**Files:**
- Modify: `backend/src/server.ts`

- [ ] **Step 1: Import and mount**

In `server.ts`, alongside the other route imports near the top, add:

```typescript
import dailyStepsRoutes from './routes/dailyStepsRoutes.js';
```

In the section after `app.use(authenticateToken);` where other `/users` routes are mounted (near `app.use('/users', dailyChallengesRoutes);`), add:

```typescript
app.use('/users', dailyStepsRoutes);
```

Place it directly after the `dailyChallengesRoutes` line for grouping clarity.

- [ ] **Step 2: Build**

```bash
cd backend && npm run build
```

Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add backend/src/server.ts
git commit -m "Mount daily-steps routes after auth"
```

---

## Task 5: Switch `ten_k_steps` challenge to read from `daily_steps`

**Files:**
- Modify: `backend/src/services/dailyChallengeService.ts`

Both the progress evaluator and the predicate evaluator need to switch from `SUM(workouts.steps)` to a single-row lookup in `daily_steps`. Missing row = 0 steps.

- [ ] **Step 1: Replace the progress query**

Find the `case 'ten_k_steps':` block inside `evaluateProgress` (around lines 170-177 in the current code). Replace its body with:

```typescript
case 'ten_k_steps': {
	const rows = await db.query<{ steps: number | null }>(
		`SELECT steps FROM daily_steps WHERE user_id = $1 AND local_date = $2`,
		[userId, localDate]
	);
	const steps = rows[0]?.steps ?? 0;
	return Math.min(steps / 10000.0, 1.0);
}
```

- [ ] **Step 2: Replace the predicate query**

Find the `case 'ten_k_steps':` block inside `evaluatePredicate` (around lines 266-274). Replace its body with:

```typescript
case 'ten_k_steps': {
	const rows = await db.query<{ steps: number | null }>(
		`SELECT steps FROM daily_steps WHERE user_id = $1 AND local_date = $2`,
		[userId, localDate]
	);
	return (rows[0]?.steps ?? 0) >= 10000;
}
```

- [ ] **Step 3: Build**

```bash
cd backend && npm run build
```

Expected: clean build.

- [ ] **Step 4: Commit**

```bash
git add backend/src/services/dailyChallengeService.ts
git commit -m "Read ten_k_steps challenge from daily_steps table"
```

---

## Task 6: Add `step_goal_enabled` to `NotificationPreferences` (backend)

**Files:**
- Modify: `backend/src/services/notificationSettingsService.ts`

- [ ] **Step 1: Update interface, defaults, getter, setter**

In `notificationSettingsService.ts`:

Add to the `NotificationPreferences` interface (alongside the other `_enabled` fields, after `competition_milestones_enabled`):

```typescript
	step_goal_enabled: boolean;
```

Add to `DEFAULT_PREFERENCES` (same spot):

```typescript
	step_goal_enabled: true,
```

Add to the object returned by `getNotificationPreferences` (in the spread):

```typescript
		step_goal_enabled: row.step_goal_enabled ?? true,
```

Add to the `fields` array inside `updateNotificationPreferences`:

```typescript
		{ key: 'step_goal_enabled', value: prefs.step_goal_enabled },
```

- [ ] **Step 2: Build**

```bash
cd backend && npm run build
```

Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add backend/src/services/notificationSettingsService.ts
git commit -m "Add step_goal_enabled to notification preferences"
```

---

## Task 7: Remove `steps` from workout sync (backend)

**Files:**
- Modify: `backend/src/services/workoutService.ts`
- Modify: `backend/src/types/workouts.ts`

- [ ] **Step 1: Update `Workout` type**

In `backend/src/types/workouts.ts`, remove the `steps` field from the `Workout` interface. Search for `steps` in the file — there should be exactly one declaration to remove (likely `steps?: number;` or similar).

- [ ] **Step 2: Update workoutService UPSERT**

In `backend/src/services/workoutService.ts`, the `workoutQuery` template string (starting around line 7) currently includes `steps` in the column list, the `$12` placeholder, and the UPDATE clause. The params array (around line 56-69) passes `workout.steps ?? null`.

Replace the entire `workoutQuery` constant with:

```typescript
	const workoutQuery = `
      INSERT INTO workouts (
        user_id,
        workout_id,
        distance,
        local_date,
        date,
        timezone_offset,
        workout_type,
        device_end_date,
        calories,
        total_duration,
        source
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
      ON CONFLICT (workout_id)
      DO UPDATE SET
        distance = EXCLUDED.distance,
        local_date = EXCLUDED.local_date,
        date = EXCLUDED.date,
        timezone_offset = EXCLUDED.timezone_offset,
        workout_type = EXCLUDED.workout_type,
        device_end_date = EXCLUDED.device_end_date,
        calories = EXCLUDED.calories,
        total_duration = EXCLUDED.total_duration,
        source = CASE
          WHEN workouts.source IN ('manual', 'edited') THEN workouts.source
          ELSE EXCLUDED.source
        END
      RETURNING workout_id, (xmax = 0) AS inserted
    `;
```

Remove the `workout.steps ?? null` entry from the params array. The params should now end with `workout.source || 'healthkit'` and have 11 entries instead of 12.

- [ ] **Step 3: Build**

```bash
cd backend && npm run build
```

Expected: clean build. If type errors fire, the `Workout` interface change in Step 1 missed something — re-check.

- [ ] **Step 4: Commit**

```bash
git add backend/src/services/workoutService.ts backend/src/types/workouts.ts
git commit -m "Remove steps field from workout sync (moved to daily_steps)"
```

---

## Task 8: Document the post-deploy DROP COLUMN step

**Files:**
- Modify: `backend/scripts/daily-steps-schema.sql`

The DROP COLUMN can only run safely after the backend deploy of Task 7. Promote the comment in the schema script to a clear, runnable second SQL block.

- [ ] **Step 1: Update the schema script**

Replace the trailing comment block in `backend/scripts/daily-steps-schema.sql` with a clearly labeled second section:

```sql
-- ─────────────────────────────────────────────────────────────────
-- POST-DEPLOY (run AFTER the backend with workoutService.ts cleanup
-- has been deployed):
-- ─────────────────────────────────────────────────────────────────
--
-- ALTER TABLE workouts DROP COLUMN steps;
```

(Leave it commented so an operator runs it explicitly. The CREATE TABLE / ADD COLUMN block above stays uncommented for the pre-deploy step.)

- [ ] **Step 2: Commit**

```bash
git add backend/scripts/daily-steps-schema.sql
git commit -m "Document post-deploy DROP COLUMN workouts.steps"
```

---

## Task 9: Add `stepGoalEnabled` to iOS `NotificationPreferences`

**Files:**
- Modify: `app/Mile A Day/Models/NotificationPreferences.swift`

- [ ] **Step 1: Add the field**

After the `hypeEnabled` line (around line 26), add:

```swift
    // Step goal achieved (local notification when daily 10k is hit)
    var stepGoalEnabled: Bool = true
```

- [ ] **Step 2: Commit**

```bash
git add "app/Mile A Day/Models/NotificationPreferences.swift"
git commit -m "Add stepGoalEnabled to iOS NotificationPreferences"
```

---

## Task 10: Add Step Goal toggle to `NotificationSettingsView`

**Files:**
- Modify: `app/Mile A Day/Views/NotificationSettingsView.swift`

The toggle goes in the existing "ACTIVITY" or "GENERAL" section if one exists; otherwise add it next to the daily reminder. Search the file for `mileCompletedEnabled` — that's the closest neighbor (your-own-mile-completion notification).

- [ ] **Step 1: Add the toggle to the view**

Find the existing `settingsToggle("Mile completed", isOn: $prefs.mileCompletedEnabled, ...)` row (or wherever the user's own-progress notifications live). Immediately after it (and a `settingsDivider`), insert:

```swift
                        settingsDivider
                        settingsToggle("Step goal", isOn: $prefs.stepGoalEnabled,
                            description: "When you reach 10,000 steps in a day")
```

(If the section style uses a wrapping `settingsSection`, place this inside the same one. Match the surrounding indentation.)

- [ ] **Step 2: Sync the toggle to the backend**

In `saveAndApply()` (around line 314), the `backendSettings: [String: Any]` dictionary currently maps iOS prefs to the backend column names. Add this entry alongside `"hypes_enabled"`:

```swift
                    "step_goal_enabled": prefs.stepGoalEnabled,
```

- [ ] **Step 3: Build**

Open Xcode and build the "Mile A Day" target. Expected: clean build, no warnings introduced.

- [ ] **Step 4: Commit**

```bash
git add "app/Mile A Day/Views/NotificationSettingsView.swift"
git commit -m "Add Step goal toggle to NotificationSettingsView"
```

---

## Task 11: Create `DailyStepsSyncService` (iOS)

**Files:**
- Create: `app/Mile A Day/Services/DailyStepsSyncService.swift`

This is the main piece of new iOS work. The service:

- Owns an `HKObserverQuery` on `.stepCount` with background delivery.
- On observer fire / `syncNow(force:)` calls, queries today's HealthKit total, applies the throttle, POSTs.
- Detects 10k crossing → POSTs immediately and fires a local UNNotification.
- Reads `NotificationPreferences.stepGoalEnabled` from UserDefaults to gate the notification.

- [ ] **Step 1: Create the service file**

```swift
import Foundation
import HealthKit
import UserNotifications

/// Syncs today's HealthKit step count to the backend `daily_steps` table on a
/// throttled cadence, and fires a local notification when the user crosses 10k.
///
/// Triggers (see plan + spec for full reasoning):
///   - HKObserverQuery wake-ups (background delivery)
///   - Foreground app activation (always posts today)
///   - First foreground after a day rollover (also posts yesterday once)
///   - Post-workout-sync hook (called by WorkoutSyncService)
///
/// Throttle (background only): post if Δsteps ≥ 500, OR ≥ 15 min since last post,
/// OR threshold crossed, OR new local date.
final class DailyStepsSyncService {

    static let shared = DailyStepsSyncService()

    private let healthStore = HKHealthStore()
    private let stepGoal = 10_000

    // Persisted state
    private let lastPostedStepsKey = "dailySteps.lastPostedSteps"
    private let lastPostTimestampKey = "dailySteps.lastPostTimestamp"
    private let lastPostedDateKey = "dailySteps.lastPostedDate"
    private let goalNotifiedDateKey = "dailySteps.goalNotifiedDate"

    private var observerQuery: HKObserverQuery?

    // MARK: - Lifecycle

    /// Call once at app launch (after HealthKit authorization is requested).
    func start() {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }

        let query = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, completionHandler, error in
            if let error = error {
                print("[DailyStepsSyncService] Observer error: \(error.localizedDescription)")
                completionHandler()
                return
            }
            Task { [weak self] in
                await self?.syncNow(force: false)
                completionHandler()
            }
        }
        healthStore.execute(query)
        observerQuery = query

        healthStore.enableBackgroundDelivery(for: stepType, frequency: .immediate) { success, error in
            if let error = error {
                print("[DailyStepsSyncService] enableBackgroundDelivery failed: \(error.localizedDescription)")
            } else if !success {
                print("[DailyStepsSyncService] enableBackgroundDelivery returned false")
            }
        }
    }

    /// Call from `scenePhase == .active` and from `WorkoutSyncService` post-success.
    /// `force = true` skips the throttle (always posts).
    func syncNow(force: Bool) async {
        guard AppStateManager.shared.isAuthenticated,
              let userId = UserManager.shared.currentUser.backendUserId else { return }

        let now = Date()
        let todayLocalDate = Self.localDateString(for: now)
        let todaySteps = await fetchSteps(for: now)

        // Day-rollover catch-up: post yesterday's final count once on the first sync of a new day.
        if let lastDate = UserDefaults.standard.string(forKey: lastPostedDateKey),
           lastDate != todayLocalDate {
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
            let yesterdayLocalDate = Self.localDateString(for: yesterday)
            if yesterdayLocalDate == lastDate {
                let yesterdaySteps = await fetchSteps(for: yesterday)
                if yesterdaySteps > 0 {
                    _ = await post(userId: userId,
                                   localDate: yesterdayLocalDate,
                                   steps: yesterdaySteps)
                }
            }
        }

        // Goal crossing: highest priority — always post + maybe notify.
        let lastPosted = UserDefaults.standard.integer(forKey: lastPostedStepsKey)
        let lastPostedDate = UserDefaults.standard.string(forKey: lastPostedDateKey)
        let crossed = todaySteps >= stepGoal &&
                      (lastPostedDate != todayLocalDate || lastPosted < stepGoal)

        if crossed {
            await postAndCommit(userId: userId,
                                localDate: todayLocalDate,
                                steps: todaySteps,
                                now: now)
            maybeFireGoalNotification(localDate: todayLocalDate)
            return
        }

        if force || shouldPost(currentSteps: todaySteps,
                               todayLocalDate: todayLocalDate,
                               now: now) {
            await postAndCommit(userId: userId,
                                localDate: todayLocalDate,
                                steps: todaySteps,
                                now: now)
        }
    }

    // MARK: - Throttle

    private func shouldPost(currentSteps: Int, todayLocalDate: String, now: Date) -> Bool {
        let lastPosted = UserDefaults.standard.integer(forKey: lastPostedStepsKey)
        let lastTimestamp = UserDefaults.standard.object(forKey: lastPostTimestampKey) as? Date
        let lastDate = UserDefaults.standard.string(forKey: lastPostedDateKey)

        if lastDate != todayLocalDate { return true }
        if currentSteps - lastPosted >= 500 { return true }
        if let ts = lastTimestamp,
           now.timeIntervalSince(ts) >= 15 * 60,
           currentSteps != lastPosted { return true }
        return false
    }

    // MARK: - Network

    private struct UpsertResponse: Decodable {
        let steps: Int
        let updatedAt: String
    }

    private struct UpsertBody: Encodable {
        let localDate: String
        let steps: Int
        let timezoneOffset: Int
    }

    private func post(userId: String, localDate: String, steps: Int) async -> Bool {
        let timezoneOffset = TimeZone.current.secondsFromGMT() / 60
        let body = UpsertBody(localDate: localDate, steps: steps, timezoneOffset: timezoneOffset)
        do {
            let bodyData = try JSONEncoder().encode(body)
            let _: UpsertResponse = try await APIClient.fancyFetch(
                endpoint: "/users/\(userId)/daily-steps",
                method: .PUT,
                body: bodyData,
                responseType: UpsertResponse.self
            )
            return true
        } catch {
            print("[DailyStepsSyncService] POST failed for \(localDate): \(error)")
            return false
        }
    }

    private func postAndCommit(userId: String, localDate: String, steps: Int, now: Date) async {
        let ok = await post(userId: userId, localDate: localDate, steps: steps)
        guard ok else { return }
        UserDefaults.standard.set(steps, forKey: lastPostedStepsKey)
        UserDefaults.standard.set(now, forKey: lastPostTimestampKey)
        UserDefaults.standard.set(localDate, forKey: lastPostedDateKey)
    }

    // MARK: - HealthKit query

    private func fetchSteps(for date: Date) async -> Int {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return 0 }
        let upperBound = min(endOfDay, Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: upperBound, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, _ in
                if let sum = result?.sumQuantity() {
                    continuation.resume(returning: Int(sum.doubleValue(for: HKUnit.count())))
                } else {
                    continuation.resume(returning: 0)
                }
            }
            self.healthStore.execute(query)
        }
    }

    // MARK: - Goal notification

    private func maybeFireGoalNotification(localDate: String) {
        let alreadyNotified = UserDefaults.standard.string(forKey: goalNotifiedDateKey)
        guard alreadyNotified != localDate else { return }

        let prefs = NotificationPreferences.load()
        guard prefs.stepGoalEnabled else {
            UserDefaults.standard.set(localDate, forKey: goalNotifiedDateKey)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "🎉 You hit 10,000 steps!"
        content.body = "Daily step goal complete — keep moving!"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "step-goal-\(localDate)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[DailyStepsSyncService] Notification add failed: \(error.localizedDescription)")
            }
        }
        UserDefaults.standard.set(localDate, forKey: goalNotifiedDateKey)
    }

    // MARK: - Helpers

    private static func localDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
}
```

Confirmed APIs used:
- `APIClient.fancyFetch(endpoint: String, method: HTTPMethod = .GET, body: Data? = nil, responseType: T.Type)` — defined in `app/Mile A Day/Services/APIClient.swift:22`. `HTTPMethod.PUT` is in `app/Mile A Day/Utils/Extensions.swift:9`.
- `UserManager.shared.currentUser.backendUserId: String?` — used identically in `WorkoutSyncService` and `DailyChallengesView`.
- `AppStateManager.shared.isAuthenticated: Bool` — used in `Mile_A_DayApp.swift:34`.
- `NotificationPreferences.load()` — defined in `app/Mile A Day/Models/NotificationPreferences.swift:43`.

- [ ] **Step 2: Build**

Build "Mile A Day" target in Xcode. Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add "app/Mile A Day/Services/DailyStepsSyncService.swift"
git commit -m "Add DailyStepsSyncService (HealthKit observer + throttled backend sync + goal notification)"
```

---

## Task 12: Wire `DailyStepsSyncService` into app lifecycle

**Files:**
- Modify: `app/Mile A Day/Mile_A_DayApp.swift`

- [ ] **Step 1: Start the service at launch + on foreground**

In the `init()` of `Mile_A_DayApp`, after `MADBackgroundService.shared.registerBackgroundTasks()`, add:

```swift
        DailyStepsSyncService.shared.start()
```

In the `WindowGroup { RootView() ... }` chain, after the existing `.onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification))` closure (or alongside the existing `Task { ... }` inside it), schedule a step sync:

```swift
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    MADBackgroundService.shared.appWillEnterForeground()
                    if AppStateManager.shared.isAuthenticated {
                        Task {
                            await MADNotificationService.shared.requestAuthorization()
                            MADNotificationService.shared.registerForRemoteNotifications()
                            await DailyStepsSyncService.shared.syncNow(force: true)
                        }
                    }
                }
```

(Merge the new `await DailyStepsSyncService.shared.syncNow(force: true)` line into the existing closure body — don't duplicate the closure.)

- [ ] **Step 2: Build**

Build "Mile A Day" in Xcode. Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add "app/Mile A Day/Mile_A_DayApp.swift"
git commit -m "Start DailyStepsSyncService at launch + sync on foreground"
```

---

## Task 13: Remove `fetchDailySteps` from `WorkoutSyncService` + hook post-sync

**Files:**
- Modify: `app/Mile A Day/Services/WorkoutSyncService.swift`

This removes the source of the bug (per-workout `steps` attachment) and adds a post-sync trigger so newly logged workouts force a fresh step push.

- [ ] **Step 1: Delete the `fetchDailySteps(on:)` method**

Locate the `private func fetchDailySteps(on date: Date) async -> Int?` method (currently around lines 592-615). Delete the entire method including its doc comment (`/// Fetch the total step count for the local day...` ... through the closing brace).

- [ ] **Step 2: Stop attaching steps to the workout dict**

Find the `let steps = await fetchDailySteps(on: workout.startDate)` line (around line 514). Delete that line.

Find the block:
```swift
            if let steps {
                workoutDict["steps"] = steps
            }
```
(around lines 529-531). Delete the entire `if let steps { ... }` block.

- [ ] **Step 3: Hook post-sync step refresh**

Locate the point in `WorkoutSyncService` where a successful upload concludes — search for the `markWorkoutsAsSynced(...)` call. Immediately after that call (after the workouts are committed as synced), add:

```swift
        Task {
            await DailyStepsSyncService.shared.syncNow(force: true)
        }
```

Match the surrounding indentation. This guarantees a fresh step total goes up to the backend right after a workout, so the daily challenge reflects reality immediately.

- [ ] **Step 4: Build**

Build "Mile A Day" in Xcode. Expected: clean build. If a struct (`Workout` model on iOS) had a `steps` field that's now unused, leave it alone — only the workout-sync wire payload is being changed; the iOS type may still be used elsewhere. (Check via Xcode "Find in Workspace" for `\.steps` or `.steps` usage on workout models if errors fire.)

- [ ] **Step 5: Commit**

```bash
git add "app/Mile A Day/Services/WorkoutSyncService.swift"
git commit -m "Stop sending per-workout steps; trigger daily steps sync after workout upload"
```

---

## Task 14: Final verification

- [ ] **Step 1: Backend full build**

```bash
cd backend && npm run build
```

Expected: clean build, no errors.

- [ ] **Step 2: iOS full build**

Open Xcode, select the "Mile A Day" scheme, Product → Build. Expected: clean build with no new warnings.

- [ ] **Step 3: Manual scenario walkthrough (recorded as a checklist; do not execute, just confirm the code paths exist)**

Walk through each scenario by reading the code paths and confirming they wire up correctly. Mark each as ✓ in the commit message:

- [ ] HealthKit observer wake-up → `syncNow(force: false)` → throttle decision
- [ ] Foreground enter → `syncNow(force: true)` → unconditional POST + yesterday catch-up
- [ ] Goal crossing locally → POST + local notification (gated by `stepGoalEnabled`)
- [ ] `step_goal_enabled` POST in `saveAndApply` → backend `notification_settings` row updated
- [ ] `GET /users/:id/challenges/today` for `ten_k_steps` → reads from `daily_steps`
- [ ] `WorkoutSyncService` payload no longer contains `steps`
- [ ] Backend `workoutService.uploadWorkouts` no longer references `workouts.steps`

- [ ] **Step 4: Confirm no lingering references**

```bash
cd backend && grep -rn "workouts\.steps\|workout\.steps\b" src/ --include="*.ts"
```

Expected: zero matches in `src/services` and `src/controllers`. (May still appear in comments or in `dailyChallengeService.ts` if Task 5 was skipped.)

```bash
cd "/Users/david/dev/Mile-A-Day/.worktrees/daily-steps-tracking/app/Mile A Day" && grep -rn "fetchDailySteps\|workoutDict\[\"steps\"\]" Services/
```

Expected: zero matches.

- [ ] **Step 5: Commit verification artifacts (optional)**

If any issues found in Steps 1-4, fix them and commit. Otherwise, no commit needed.

---

## Rollout (operator runs after merge)

Execute in this order — pre-deploy DB changes first, then backend, then DROP COLUMN, then iOS app store submission. See spec § Rollout for the safety reasoning.

1. **Apply additive DB changes** (`backend/scripts/daily-steps-schema.sql` lines 4-22):
   ```bash
   psql "$DATABASE_URL" -f backend/scripts/daily-steps-schema.sql
   ```
2. **Deploy backend** (this branch merged to main, deployed however the team currently deploys).
3. **Apply DROP COLUMN** manually (paste the post-deploy SQL block from the schema file):
   ```sql
   ALTER TABLE workouts DROP COLUMN steps;
   ```
4. **Submit iOS update** via Xcode → App Store Connect.

---

## File touch summary

| File | New / Modified | Task |
| --- | --- | --- |
| `backend/scripts/daily-steps-schema.sql` | New | 1, 8 |
| `backend/src/services/dailyStepsService.ts` | New | 2 |
| `backend/src/controllers/dailyStepsController.ts` | New | 3 |
| `backend/src/routes/dailyStepsRoutes.ts` | New | 3 |
| `backend/src/server.ts` | Modified | 4 |
| `backend/src/services/dailyChallengeService.ts` | Modified | 5 |
| `backend/src/services/notificationSettingsService.ts` | Modified | 6 |
| `backend/src/services/workoutService.ts` | Modified | 7 |
| `backend/src/types/workouts.ts` | Modified | 7 |
| `app/Mile A Day/Models/NotificationPreferences.swift` | Modified | 9 |
| `app/Mile A Day/Views/NotificationSettingsView.swift` | Modified | 10 |
| `app/Mile A Day/Services/DailyStepsSyncService.swift` | New | 11 |
| `app/Mile A Day/Mile_A_DayApp.swift` | Modified | 12 |
| `app/Mile A Day/Services/WorkoutSyncService.swift` | Modified | 13 |
