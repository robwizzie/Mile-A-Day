# Direct Workout Upload from Apple Watch — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a workout finishes on the Apple Watch, upload it (with per-mile splits) straight to the backend from the Watch, instead of waiting for the iPhone's HealthKit-based sync.

**Architecture:** The iPhone pushes its backend access token + user id to the Watch over the existing `MADWatchBridge` WCSession channel. A new watchOS-only `WatchWorkoutUploader` reads those, computes splits with the shared `SplitCalculator`, and `POST`s directly to `/workouts/{userId}/upload`. The upload is best-effort and detached from the UI; the iPhone's existing sync remains as an idempotent backstop.

**Tech Stack:** Swift / SwiftUI, watchOS, HealthKit, WatchConnectivity (`WCSession`), `URLSession`.

---

## Testing Note

This project has **no automated test runner** for the iOS/watchOS targets, and the
Xcode project cannot be built from the CLI (`CLAUDE.md`: "Build via Xcode only").
So tasks here are **code change + commit**; compile/run verification is a single
**manual** task at the end (Task 5), performed in Xcode against the
`Mile A Day Watch Watch App` scheme. Each code task is still small and
independently committable.

Spec: `docs/superpowers/specs/2026-05-16-watch-direct-upload-design.md`.

---

## Task 1: Carry auth token + user id over the Watch bridge

`MADWatchBridge` already pushes a one-way iPhone→Watch snapshot. Add the backend
access token and user id to that payload, and store them on the Watch side.

**Files:**
- Modify: `app/Mile A Day/Models/HealthKitManager.swift` (the `MADWatchBridge` class — `pushSnapshotIfReady()` is around line 1390, `apply(context:)` around line 1423)

- [ ] **Step 1: Add token + id to the iOS push payload**

In `MADWatchBridge.pushSnapshotIfReady()` (inside the `#if os(iOS)` block),
replace the existing `let payload` / `stableHash` section with:

```swift
        var payload: [String: Any] = [
            "streak": hk.retroactiveStreak,
            "todayMiles": hk.todaysDistance,
            "goalMiles": user.goalMiles > 0 ? user.goalMiles : 1.0,
            "firstName": user.firstName ?? "",
            "name": user.name,
            "ts": Date().timeIntervalSince1970
        ]

        // Carry the backend auth token + user id so the watch can upload
        // workouts directly. The watch never refreshes tokens — it relies on
        // these pushes, which is safe because access tokens last 30 days.
        let authToken = UserDefaults.standard.string(forKey: "authToken")
        let backendUserId = UserDefaults.standard.string(forKey: "backendUserId")
        if let authToken { payload["authToken"] = authToken }
        if let backendUserId { payload["backendUserId"] = backendUserId }

        // Hash on the value-bearing fields only (not the timestamp) so we don't
        // re-send identical state. Token + id are included so a token change
        // forces a re-push.
        let stableHash = "\(payload["streak"] ?? 0)|\(payload["todayMiles"] ?? 0)|\(payload["goalMiles"] ?? 0)|\(payload["firstName"] ?? "")|\(payload["name"] ?? "")|\(authToken ?? "")|\(backendUserId ?? "")".hashValue
        if stableHash == lastPushedHash { return }
        lastPushedHash = stableHash
```

(The `payload` declaration changes from `let` to `var`. The `do { try WCSession.default.updateApplicationContext(payload) } ...` block below it is unchanged.)

- [ ] **Step 2: Store token + id on the Watch side**

In `MADWatchBridge.apply(context:)` (inside the `#if os(watchOS)` block), add the
following just before the closing `userManager.saveUserData()` line:

```swift
            if let token = context["authToken"] as? String, !token.isEmpty {
                UserDefaults.standard.set(token, forKey: "authToken")
            }
            if let backendUserId = context["backendUserId"] as? String, !backendUserId.isEmpty {
                UserDefaults.standard.set(backendUserId, forKey: "backendUserId")
            }
```

(Absent keys are intentionally left untouched, so a partial push never wipes a
valid token already on the Watch.)

- [ ] **Step 3: Commit**

```bash
git add "app/Mile A Day/Models/HealthKitManager.swift"
git commit -m "Push backend auth token to the watch over WCSession"
```

---

## Task 2: Push a freshly rotated token to the Watch

When `APIClient` refreshes the access token, forward it to the Watch immediately
so the Watch is not stuck with a stale token until the next snapshot change.

**Files:**
- Modify: `app/Mile A Day/Services/APIClient.swift` (`updateTokens`, around line 177)

- [ ] **Step 1: Call the bridge after updating tokens**

Replace the `updateTokens` function body:

```swift
    private static func updateTokens(accessToken: String, refreshToken: String) {
        UserManager.shared.setTokens(accessToken: accessToken, refreshToken: refreshToken)
        print("[APIClient] ✅ Tokens updated in storage")
        // Forward the freshly rotated token to the watch so it can keep
        // uploading workouts directly.
        MADWatchBridge.shared.pushSnapshotIfReady()
    }
```

(`APIClient` compiles into the iOS target only, and `pushSnapshotIfReady()` is
defined in the `#if os(iOS)` block of `MADWatchBridge`, so this resolves.)

- [ ] **Step 2: Commit**

```bash
git add "app/Mile A Day/Services/APIClient.swift"
git commit -m "Forward refreshed token to the watch"
```

---

## Task 3: Create the watchOS direct uploader

A new watchOS-only file. Placed inside the `Mile A Day Watch Watch App/` folder so
Xcode's synchronized-folder model auto-includes it in the Watch target — no
`project.pbxproj` change.

**Files:**
- Create: `app/Mile A Day Watch Watch App/Services/WatchWorkoutUploader.swift`

- [ ] **Step 1: Create the `Services/` folder and write the file**

Create `app/Mile A Day Watch Watch App/Services/WatchWorkoutUploader.swift` with
exactly this content:

```swift
import Foundation
import HealthKit

/// watchOS-only. Uploads a finished workout straight to the backend so it lands
/// on the server immediately, instead of waiting for the iPhone's HealthKit
/// sync. Best-effort: any failure is logged and dropped — the iPhone's sync is
/// the backstop, and the upload endpoint is idempotent on workout id.
enum WatchWorkoutUploader {

    private static let baseURL = "https://mad.mindgoblin.tech"

    static func upload(_ workout: HKWorkout) async {
        guard let token = UserDefaults.standard.string(forKey: "authToken"), !token.isEmpty,
              let userId = UserDefaults.standard.string(forKey: "backendUserId"), !userId.isEmpty
        else {
            print("[WatchWorkoutUploader] No auth token / user id on watch — skipping direct upload")
            return
        }

        let splits = await SplitCalculator.calculateSplits(for: workout)
        let calories = await activeEnergyKilocalories(for: workout)

        let splitsData: [[String: Any]] = splits.map { split in
            [
                "splitNumber": split.splitNumber,
                "distance": split.distance,
                "duration": split.duration,
                "pace": split.pace
            ]
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        let localDate = dateFormatter.string(from: workout.startDate)

        let isoFormatter = ISO8601DateFormatter()
        let deviceEndDate = isoFormatter.string(from: workout.endDate)

        let distance = workout.totalDistance?.doubleValue(for: .mile()) ?? 0
        let timezoneOffset = TimeZone.current.secondsFromGMT() / 60

        let workoutDict: [String: Any] = [
            "workoutId": workout.uuid.uuidString,
            "distance": distance,
            "localDate": localDate,
            "date": localDate,
            "timezoneOffset": timezoneOffset,
            "workoutType": workoutType(from: workout.workoutActivityType),
            "deviceEndDate": deviceEndDate,
            "calories": calories,
            "totalDuration": workout.duration,
            "splits": splitsData,
            "source": "healthkit"
        ]

        guard let url = URL(string: "\(baseURL)/workouts/\(userId)/upload"),
              let body = try? JSONSerialization.data(withJSONObject: [workoutDict])
        else {
            print("[WatchWorkoutUploader] Failed to build upload request")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                print("[WatchWorkoutUploader] No HTTP response")
                return
            }
            if (200...299).contains(http.statusCode) {
                print("[WatchWorkoutUploader] ✅ Uploaded workout \(workout.uuid.uuidString)")
            } else {
                print("[WatchWorkoutUploader] ⚠️ Upload failed (status \(http.statusCode)) — iPhone sync will retry")
            }
        } catch {
            print("[WatchWorkoutUploader] ⚠️ Upload failed: \(error.localizedDescription) — iPhone sync will retry")
        }
    }

    private static func workoutType(from activityType: HKWorkoutActivityType) -> String {
        switch activityType {
        case .running: return "running"
        case .walking: return "walking"
        case .cycling: return "cycling"
        case .hiking: return "hiking"
        default: return "other"
        }
    }

    private static func activeEnergyKilocalories(for workout: HKWorkout) async -> Double {
        guard HKHealthStore.isHealthDataAvailable(),
              let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
        else {
            return 0
        }
        let healthStore = HKHealthStore()
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForObjects(from: workout)
            let query = HKStatisticsQuery(
                quantityType: energyType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let value = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }
}
```

The payload shape mirrors `WorkoutSyncService.transformWorkoutsForBackend` exactly,
so the backend treats Watch and iPhone uploads identically. `SplitCalculator` and
`WorkoutSplit` are already members of the Watch target.

- [ ] **Step 2: Commit**

```bash
git add "app/Mile A Day Watch Watch App/Services/WatchWorkoutUploader.swift"
git commit -m "Add watchOS direct workout uploader"
```

---

## Task 4: Trigger the upload when a workout finishes

`WatchWorkoutManager.endWorkout()` currently discards the finished `HKWorkout`.
Capture it and fire the upload after the UI completion handler.

**Files:**
- Modify: `app/Mile A Day Watch Watch App/Views/WatchWorkoutManager.swift` (the `builder.finishWorkout` closure, around line 144)

- [ ] **Step 1: Capture the workout and fire the upload**

Replace the `builder.finishWorkout { _, error in ... }` block (currently lines
~144–157) with:

```swift
            builder.finishWorkout { workout, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("finishWorkout failed: \(error.localizedDescription)")
                        completion(false)
                    } else {
                        // Refresh average HR one more time in case samples arrived late.
                        if let samples = self?.heartRateSamples, !samples.isEmpty {
                            self?.averageHeartRate = samples.reduce(0, +) / Double(samples.count)
                        }
                        completion(true)
                        // Best-effort direct upload from the watch. Detached from
                        // the UI completion above so the summary screen never
                        // waits on the network. The iPhone sync is the backstop.
                        if let workout {
                            Task { await WatchWorkoutUploader.upload(workout) }
                        }
                    }
                }
            }
```

The only changes vs. the current code: `_` becomes `workout`, and the
`if let workout { Task { ... } }` block is added after `completion(true)`.

- [ ] **Step 2: Commit**

```bash
git add "app/Mile A Day Watch Watch App/Views/WatchWorkoutManager.swift"
git commit -m "Upload workout directly from the watch on finish"
```

---

## Task 5: Manual verification in Xcode

No automated tests exist; this task is performed by hand.

- [ ] **Step 1: Build the Watch target**

Open `app/Mile A Day.xcodeproj` in Xcode, select the `Mile A Day Watch Watch App`
scheme, and build (Cmd-B). Expected: builds with no errors. (`WatchWorkoutUploader`
should auto-appear in the Watch target because it lives inside the
`Mile A Day Watch Watch App/` folder.)

- [ ] **Step 2: Build the iOS target**

Select the `Mile A Day` scheme and build. Expected: builds with no errors (the
`MADWatchBridge` and `APIClient` changes compile).

- [ ] **Step 3: Happy path — phone nearby**

Run the app on a paired iPhone + Watch (signed in). On the Watch, start and finish
a short workout. Within a few seconds, confirm a new row exists in the backend
`workouts` table for that workout id, with matching `workout_splits` rows. Check
the Watch console for `[WatchWorkoutUploader] ✅ Uploaded workout ...`.

- [ ] **Step 4: Cellular Watch without the phone**

Put the iPhone in airplane mode (or leave it out of range). On a cellular Watch,
finish a workout. Confirm it still reaches the backend (the Watch uploaded it
directly).

- [ ] **Step 5: Offline Watch — graceful failure + backstop**

Put the Watch in airplane mode. Finish a workout. Confirm: the workout-summary
screen appears immediately (UI not blocked), the console logs an upload failure,
and — after restoring connectivity and letting the iPhone sync run — the workout
still appears on the backend exactly once.

- [ ] **Step 6: No double-count**

After a successful Watch upload, foreground the iPhone app so its sync runs.
Confirm the workout, its distance, the streak, and the splits are **not**
duplicated or doubled on the backend (the `ON CONFLICT DO UPDATE` upsert holds).
