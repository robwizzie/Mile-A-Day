# Direct Workout Upload from Apple Watch — Design

**Date:** 2026-05-16
**Status:** Approved

## Problem

When a user finishes a workout on the Apple Watch, it is **not** uploaded to the
backend promptly. The Watch app only saves the workout to HealthKit
(`WatchWorkoutManager.endWorkout()` calls `builder.finishWorkout` and discards the
result). Upload to the backend depends entirely on the **iPhone**: the workout
must first sync Watch → iPhone HealthKit, then the iPhone must run its sync
(foreground, `BGAppRefreshTask`, HealthKit observer, or silent push). For a runner
using a cellular Watch without their phone, the workout does not reach the server
until the phone is reachable again.

## Goal

When a workout finishes on the Watch, upload it to the backend **directly from the
Watch**, including per-mile splits, as a best-effort fast path. The existing
iPhone-based sync remains as a backstop so nothing is ever lost.

## Non-Goals

- Replacing or modifying the existing iPhone HealthKit-based sync.
- Token refresh on the Watch.
- Cleaning up the legacy `Mile A Day Watch App` folder (separate task).
- Uploading workout data not already in the backend schema (e.g. heart rate —
  the `workouts` table has no column for it).

## Context / Constraints

- **Live Watch target:** `Mile A Day Watch Watch App` (confirmed). The older
  `Mile A Day Watch App` folder is legacy and untouched by this work.
- **Auth tokens** (`authToken`, `refreshToken`) live in the **iOS app's**
  `UserDefaults`. The Watch has no access to them and cannot log in itself.
- **Access tokens last 30 days** (`ACCESS_TOKEN_EXPIRY = '30d'` in
  `backend/src/services/tokenService.ts`). Refresh tokens **rotate** on use
  (old token revoked) — so the Watch must never refresh independently, or it
  would invalidate the iPhone's session.
- **Backend upload is idempotent:** `POST /workouts/:userId/upload` does
  `INSERT INTO workouts ... ON CONFLICT (workout_id) DO UPDATE` and the same for
  `workout_splits` on `(workout_id, split_number)`. A Watch upload followed by an
  iPhone backstop upload of the same workout simply upserts — no double-count.
- **Xcode 16 synchronized folders** (`objectVersion = 77`). `SplitCalculator.swift`
  and `WorkoutSplit.swift` are already members of the Watch target (listed in the
  "Mile A Day" folder exception set for the Watch target, which — for a non-default
  group — is an *inclusion* list). A new file placed physically inside
  `Mile A Day Watch Watch App/` is auto-included in the Watch target.
  **No `project.pbxproj` edits are required.**
- The Watch ⇄ iPhone link is `MADWatchBridge` (a `WCSession` owner in
  `HealthKitManager.swift`, compiled into both targets). It currently pushes a
  one-way iPhone → Watch snapshot (streak, today's miles, goal, name) via
  `updateApplicationContext`.

## Approach

Chosen auth strategy: **the iPhone pushes the access token to the Watch.** The
Watch uses it to POST directly; it never refreshes. With 30-day tokens the Watch
effectively always holds a valid token, and there is no refresh-token rotation
race. Rejected alternatives: a full `APIClient`/`TokenRefreshService` port to
watchOS (refresh-token rotation race, more code); handing the workout to the
iPhone over `WCSession` (not a direct upload — fails the cellular-Watch-without-
phone case).

## Components

### 1. Token delivery — extend `MADWatchBridge`

`HealthKitManager.swift`, `MADWatchBridge`:

- **iOS side (`pushSnapshotIfReady`)** — add `authToken` and `backendUserId` to the
  `applicationContext` payload dictionary. Add both values to the `stableHash`
  string so a token change forces a re-push (the timestamp is still excluded).
  - `authToken` source: `UserDefaults.standard.string(forKey: "authToken")`.
  - `backendUserId` source: `UserDefaults.standard.string(forKey: "backendUserId")`.
  - If either is missing, push the snapshot without those keys (Watch keeps its
    last-known values).
- **Watch side (`apply(context:)`)** — when `authToken` / `backendUserId` are
  present in the received context, write them to the Watch's
  `UserDefaults.standard` under the same keys. Do not clear them if absent from a
  given context (avoids wiping a good token on a partial push).
- The iPhone already calls `pushSnapshotIfReady()` from assorted update sites and
  on `WCSession` activation. No new trigger is strictly required — the token rides
  along with the next snapshot push. (Optional, low-cost improvement: also call
  `pushSnapshotIfReady()` right after a successful token refresh in
  `APIClient.updateTokens`, so a freshly rotated token reaches the Watch sooner.
  Include this.)

### 2. `WatchWorkoutUploader.swift` (new file)

Location: `app/Mile A Day Watch Watch App/Services/WatchWorkoutUploader.swift`
(create the `Services/` subfolder). watchOS-only.

A minimal POST-only uploader — **not** a port of `APIClient`. Public surface:

```swift
enum WatchWorkoutUploader {
    static func upload(_ workout: HKWorkout) async
}
```

Behavior:

1. Read `authToken` and `backendUserId` from Watch `UserDefaults`. If either is
   missing → log and return (the iPhone backstop will handle the workout).
2. Compute splits: `await SplitCalculator.calculateSplits(for: workout)`.
3. Build one workout dictionary matching the backend payload (same shape as
   `WorkoutSyncService.transformWorkoutsForBackend`):
   - `workoutId` = `workout.uuid.uuidString`
   - `distance` = `workout.totalDistance?.doubleValue(for: .mile()) ?? 0`
   - `localDate` / `date` = `yyyy-MM-dd` of `workout.startDate` in the current
     time zone
   - `timezoneOffset` = `TimeZone.current.secondsFromGMT() / 60`
   - `workoutType` = mapped from `workout.workoutActivityType` (local `switch`:
     running/walking/cycling/hiking/other)
   - `deviceEndDate` = ISO-8601 string of `workout.endDate`
   - `calories` = active energy in kilocalories (HKStatisticsQuery for
     `.activeEnergyBurned` with `HKQuery.predicateForObjects(from: workout)`;
     `0` on failure)
   - `totalDuration` = `workout.duration`
   - `splits` = array of `{ splitNumber, distance, duration, pace }`
   - `source` = `"healthkit"`
4. `POST` to `https://mad.mindgoblin.tech/workouts/{backendUserId}/upload` with
   headers `Content-Type: application/json` and
   `Authorization: Bearer {authToken}`, body = `JSONSerialization` of
   `[workoutDict]` (the endpoint expects an array).
5. On HTTP 2xx → log success. On any other status or thrown error → log and
   return. No retry, no token refresh, no user-facing error.

The base URL is hardcoded, consistent with `APIClient.baseURL`.

### 3. Trigger — `WatchWorkoutManager.endWorkout()`

`app/Mile A Day Watch Watch App/Views/WatchWorkoutManager.swift`, line ~144:

- Change `builder.finishWorkout { _, error in` to capture the workout:
  `builder.finishWorkout { workout, error in`.
- In the success branch, **after** `completion(true)`, if `workout` is non-nil,
  fire `Task { await WatchWorkoutUploader.upload(workout) }`.
- The upload is fully detached from the UI completion handler — `endWorkout`'s
  `completion(_:)` is never delayed by, or made to depend on, the upload.

### 4. Backstop — unchanged

The iPhone HealthKit-based sync (`MADBackgroundService`, `WorkoutSyncService`,
`AppLaunchSyncHandler`) is not modified. Because the endpoint is idempotent, a
later iPhone upload of the same workout upserts the row and splits. If the Watch
upload fails for any reason, the workout still reaches the backend via the phone.

## Data Flow

```
Workout ends on Watch
  -> HKLiveWorkoutBuilder.finishWorkout  (saved to HealthKit)
  -> completion(true)  (UI updates immediately)
  -> Task: WatchWorkoutUploader.upload(workout)
       -> read token + userId from Watch UserDefaults
       -> SplitCalculator.calculateSplits(for: workout)
       -> POST /workouts/{userId}/upload   (best-effort, direct)
  -> (independently) Watch -> iPhone HealthKit sync
  -> (later) iPhone backstop sync upserts the same workout   (idempotent)
```

## Error Handling

| Condition | Behavior |
|---|---|
| No `authToken` / `backendUserId` on Watch | Log, skip. iPhone backstop covers it. |
| No network on Watch | `URLSession` throws → log, skip. Backstop covers it. |
| HTTP 401 (token somehow invalid) | Log, skip. No refresh attempt. |
| HTTP 5xx / other non-2xx | Log, skip. No retry. |
| `finishWorkout` returns nil workout | No upload attempted. |

No path blocks the UI or surfaces an error to the user. Every failure mode
degrades to "the iPhone uploads it later."

## Testing

No automated test runner exists for the iOS/watchOS targets. Manual verification:

1. **Phone nearby:** finish a Watch workout; confirm a `workouts` row (with
   `workout_splits`) appears on the backend within seconds.
2. **Cellular Watch, phone in airplane mode / left behind:** finish a workout;
   confirm it uploads directly from the Watch.
3. **Watch fully offline:** finish a workout; confirm the Watch upload fails
   silently and the workout still appears later once the phone syncs.
4. **No double-count:** after a Watch upload, let the iPhone sync run; confirm
   the workout, distance, streak, and splits are not duplicated or doubled.
5. Confirm `endWorkout`'s UI completion is not delayed by the upload (the
   workout-summary screen appears immediately regardless of network).

## Files Touched

- `app/Mile A Day/Models/HealthKitManager.swift` — extend `MADWatchBridge`
  (`pushSnapshotIfReady`, `apply(context:)`).
- `app/Mile A Day/Services/APIClient.swift` — one-line call to
  `MADWatchBridge.shared.pushSnapshotIfReady()` after `updateTokens`, so a freshly
  rotated token reaches the Watch promptly.
- `app/Mile A Day Watch Watch App/Services/WatchWorkoutUploader.swift` — new.
- `app/Mile A Day Watch Watch App/Views/WatchWorkoutManager.swift` — capture the
  workout and trigger the upload.

No `project.pbxproj` changes. No backend changes.
