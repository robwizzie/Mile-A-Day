# Background Workout Sync — Design

**Date:** 2026-05-14
**Status:** Approved, ready for implementation plan

## Problem

When a user finishes a mile, we want the workout to upload to the backend and any relevant notifications to fire **immediately**, regardless of whether the app is foregrounded, backgrounded, or fully terminated.

Today the foundation is partially built but is effectively a no-op because:

- `MADBackgroundService` registers an `HKObserverQuery` with `enableBackgroundDelivery(frequency: .immediate)` and a `BGAppRefreshTask`, but `Info.plist` declares no `UIBackgroundModes`. Without those declarations iOS will not grant the app meaningful background time.
- No `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` implementation exists, so silent pushes cannot wake the app.
- The background-launch path (app launched by iOS into the background due to HealthKit delivery) is not explicitly handled — the existing sync triggers are wired to UI lifecycle notifications.

## Goals

1. As soon as a user completes a mile, the workout uploads to the backend automatically — even when the app is fully closed.
2. Notifications fire on the user's device promptly (local "mile completed" notification + the existing backend-driven friend pushes).
3. Behavior degrades gracefully: if one wake-up mechanism fails or is throttled by iOS, another will catch up within hours.

## Non-Goals

- New notification types (streak milestones, PR alerts, etc.) — out of scope.
- Production APNs entitlement / TestFlight wiring — deployment concern, addressed separately.
- WatchOS-side sync — the Watch app writes to HealthKit, the phone picks it up. Unchanged.
- Local persistent queue of pending workouts — HealthKit is already the source of truth.

## Approach: Layered Wake-Up

Three independent layers. Each is a complete path on its own; the others exist to cover throttling or failure of any single layer.

### Layer 1 — HealthKit observer (primary)

This is the "fully closed" path. iOS can relaunch a terminated app when a new `HKWorkout` lands in HealthKit, but only if the background-delivery infrastructure is correctly declared.

**Changes:**

- `app/Mile A Day/Info.plist` — add `UIBackgroundModes` containing:
  - `fetch` (for `BGAppRefreshTask`)
  - `processing` (in case we later need `BGProcessingTask`)
  - `remote-notification` (for silent push, Layer 2)
- Verify `MileADay.entitlements` has `com.apple.developer.healthkit` (already present).
- `MADBackgroundService.setupWorkoutObserver()` — verify the `HKObserverQuery` completion handler is called after sync. If iOS is not seeing the completion call, it will eventually stop delivering. (Read the file during implementation; fix only if missing.)
- `AppDelegate.application(_:didFinishLaunchingWithOptions:)` — when the app is launched into the background (no UI), still initialize the services that observe HealthKit and trigger an immediate sync. Today the sync paths key off UI lifecycle notifications, which do not fire on background launch.
- Expose a non-UI entry point on `MADBackgroundService` — e.g. `performBackgroundSync(reason:completion:)` — that can be called from `AppDelegate`, the BGTask handler, and the silent-push handler.

### Layer 2 — Backend silent push (fallback, every 4h during waking hours)

If iOS throttles HealthKit background delivery (which it will under heavy battery pressure or after periods of dormancy), a periodic silent push wakes the app to re-check HealthKit for unsynced workouts.

**Cadence:** 4 fires per active user per day, at roughly 08:00 / 12:00 / 16:00 / 20:00 in the user's local timezone.

**Backend changes:**

- New `backend/src/cron/silentSyncPushCron.ts`. Runs hourly. For each user with a registered device token and a known timezone, checks whether the current time in their tz falls within ±30 min of one of the four target hours. If so, send the silent push.
- The existing device-token storage and APNs sender are reused. A `sendSilentPush(deviceToken, payload)` helper is added (or extracted) if one is not already available. The payload sets `aps.content-available = 1`, omits `alert` / `sound` / `badge`, and includes a `type: "background_sync"` field for the iOS handler to dispatch on.
- Cron is registered in the existing cron entrypoint alongside the other jobs. No new endpoint, no DB schema change.

**iOS changes:**

- `AppDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` — when `aps.content-available == 1` and `type == "background_sync"`, call `MADBackgroundService.performBackgroundSync(reason: .silentPush, completion:)` and invoke the OS-provided `fetchCompletionHandler` with `.newData` or `.noData` based on the result.
- Register for remote notifications at the existing point (`MADNotificationService` already does this). No new entitlement work.

### Layer 3 — `BGAppRefreshTask` (existing, leave alone)

`MADBackgroundService` already registers `mileaday.refresh` and reschedules it on app background. With `fetch` declared in `UIBackgroundModes`, iOS will start honoring this. No code changes other than making sure the task handler routes through the same `performBackgroundSync` entry point as the other layers.

## Notification behavior

Unchanged. The existing flows continue to work, now reliably triggered:

- `MADNotificationService.sendMileCompletedNotification()` already fires a local notification after the upload completes, with same-day dedup. No changes.
- `updateDailyReminder()` continues to schedule the daily reminder on foreground. No changes.
- Friend mile pushes, badge / challenge / race rewards — all flow through the existing backend push paths in `workoutController.uploadWorkouts`. No changes.

## Error handling

- **Upload failure during background sync.** The `HKObserverQuery` completion handler is still called (so iOS keeps delivering); the workout stays in HealthKit and is picked up on the next wake-up. No local queue.
- **Silent push delivery failure / APNs throttling.** Logged on the backend; the next cron tick or the HK observer covers it. Accepted as routine.
- **Push received while app is foregrounded.** The silent-push handler still runs `performBackgroundSync`; the existing foreground sync paths debounce themselves, so duplicate work is cheap.
- **BGTask expiration.** Existing handler already calls `task.setTaskCompleted(success:)`. Unchanged.

## Testing

Manual, since neither the iOS app nor the backend has a test runner configured.

**iOS (per platform conventions):**

- Build to a device, complete a workout while the app is closed, observe Console logs in Xcode for the sync + notification path.
- Trigger HealthKit observer with "Simulate Background Fetch" in Xcode's Debug menu.
- Send a manual silent push via a `curl` script (or a `/dev/*` test endpoint on the backend) and verify the app wakes and syncs.

**Backend:**

- Add a one-shot trigger under the existing `/dev/*` route prefix (e.g. `POST /dev/silent-sync-push/:userId`) that runs the cron logic for a single user. Used for local verification and removable after launch.
- Verify timezone math for users in non-UTC zones (use the existing user timezone field).

## Implementation Slices

The plan will likely split into roughly:

1. **iOS capability + entry point.** Info.plist `UIBackgroundModes`, `AppDelegate.didFinishLaunchingWithOptions` background-launch handling, `MADBackgroundService.performBackgroundSync` extraction. No backend dependency.
2. **iOS silent-push handler.** `AppDelegate.didReceiveRemoteNotification` wired to `performBackgroundSync`.
3. **Backend silent-push helper + cron.** `sendSilentPush` helper, `silentSyncPushCron.ts`, cron registration, dev-only one-shot trigger.
4. **End-to-end verification.** Manual test plan walkthrough on a physical device.

## Open Questions

None at design time — all decisions resolved during brainstorming.
