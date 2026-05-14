# Background Workout Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make completed workouts upload to the backend and notifications fire reliably whether the iOS app is foregrounded, backgrounded, or fully terminated, by unblocking the existing HealthKit observer path and adding a scheduled silent-push fallback.

**Architecture:** Three independent wake-up layers, each routing through a single `performBackgroundSync` entry point on `MADBackgroundService`:

1. **HealthKit observer** — `HKObserverQuery` + `enableBackgroundDelivery(.immediate)` (already wired; unblocked by adding `UIBackgroundModes` in Xcode).
2. **Silent push** — new backend cron sends APNs `content-available` pushes 4×/day in ET; iOS `AppDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` triggers a sync.
3. **`BGAppRefreshTask`** — already wired; same path, no code change.

**Tech Stack:** iOS (Swift/SwiftUI, HealthKit, BackgroundTasks, UNUserNotificationCenter), Backend (Node.js, Express, `node-cron`, raw http2 APNs client in `pushNotificationService.ts`).

**Spec:** `docs/superpowers/specs/2026-05-14-background-workout-sync-design.md`

**Notes on testing:** Neither iOS nor the backend has a test runner configured (per project CLAUDE.md). TDD-style "write failing test first" is replaced with explicit verification steps: log inspection, manual triggers via dev endpoints, and Xcode Debug menu actions. Every change still has a verifiable check before commit.

**Notes on the Xcode project file:** `project.pbxproj` is excluded by `.claudeignore` and must not be modified by the AI. Capability changes that normally live in build settings (`UIBackgroundModes`, `BGTaskSchedulerPermittedIdentifiers`) are documented as manual steps the user performs in Xcode — Task 1.

---

## Task 1: Add iOS background capabilities in Xcode (manual user step)

**Files:**
- Modify: `app/Mile A Day.xcodeproj/project.pbxproj` (via Xcode UI only — do not edit by hand)

**Why this is first:** Every iOS code path that follows is dependent on these capability declarations. Without them, iOS will neither relaunch the app for HealthKit deliveries nor deliver background-priority silent pushes.

- [ ] **Step 1: Open the project in Xcode**

Open `app/Mile A Day.xcodeproj`. Select the **Mile A Day** target (not the Watch app or Widget Extension).

- [ ] **Step 2: Add Background Modes capability**

Go to **Signing & Capabilities**. If "Background Modes" is not already present, click **+ Capability** and add it.

- [ ] **Step 3: Enable the three modes**

Under Background Modes, check:
- **Background fetch**
- **Background processing**
- **Remote notifications**

(`UIBackgroundModes` array in the generated Info.plist will become `["fetch", "processing", "remote-notification"]`.)

- [ ] **Step 4: Register the BGTask identifier**

Under Background Modes, scroll down to **Permitted background task scheduler identifiers** (this maps to the `BGTaskSchedulerPermittedIdentifiers` plist key). Add a single entry:

```
com.mileaday.background-refresh
```

(This matches `MADBackgroundService.backgroundTaskIdentifier` at `app/Mile A Day/Core/Services/MADBackgroundService.swift:20`.)

- [ ] **Step 5: Verify the build**

Build the app (⌘B) to confirm no signing or capability errors.

- [ ] **Step 6: Commit**

```bash
cd "/Users/david/dev/Mile-A-Day/.claude/worktrees/background-workout-sync"
git add "app/Mile A Day.xcodeproj/project.pbxproj"
git commit -m "Enable UIBackgroundModes and BGTask scheduler identifier for the main app target"
```

---

## Task 2: Expose a non-UI background sync entry point on `MADBackgroundService`

**Files:**
- Modify: `app/Mile A Day/Core/Services/MADBackgroundService.swift`

**Why:** Today, `performBackgroundWork()` is `private` and `syncWorkoutsInBackground()` is also `private`. The new silent-push handler in `AppDelegate` and the existing BGTask handler all need a single, common entry point. Right now BGTask reaches it via `handleBackgroundRefresh` and the HK observer reaches it via `handleNewWorkoutData`. We introduce one public entry point all three layers can call.

- [ ] **Step 1: Add a public `performBackgroundSync` method**

Add this method to `MADBackgroundService` (just below `performBackgroundWork` at line 144). It is the single entry point background wake-ups call.

```swift
/// Unified entry point for background sync triggered by HealthKit, BGTask, silent push, or background launch.
/// Caller is responsible for any iOS completion handler (BGTask, fetchCompletionHandler, etc.).
@MainActor
func performBackgroundSync(reason: BackgroundSyncReason) async {
    print("[MADBackgroundService] performBackgroundSync(reason: \(reason))")

    // Only run if user has authenticated.
    guard UserDefaults.standard.bool(forKey: "MAD_IsAuthenticated") else {
        print("[MADBackgroundService] Skipping sync — user not authenticated")
        return
    }

    await performBackgroundWork()
}

enum BackgroundSyncReason: String {
    case healthKitObserver
    case bgAppRefreshTask
    case silentPush
    case backgroundLaunch
}
```

- [ ] **Step 2: Update `handleBackgroundRefresh` to call the new entry point**

Replace the `Task { [weak self] in ... }` block in `handleBackgroundRefresh` (lines 127-130) with:

```swift
Task { [weak self] in
    await self?.performBackgroundSync(reason: .bgAppRefreshTask)
    task.setTaskCompleted(success: true)
}
```

- [ ] **Step 3: Update `handleNewWorkoutData` to call the new entry point**

Replace the body of `handleNewWorkoutData()` (lines 134-141) with:

```swift
@MainActor
private func handleNewWorkoutData() async {
    guard await requestHealthKitAuthorizationIfNeeded() else { return }
    await performBackgroundSync(reason: .healthKitObserver)
}
```

- [ ] **Step 4: Verify build**

In Xcode, build the app (⌘B). Expected: clean build.

- [ ] **Step 5: Commit**

```bash
git add "app/Mile A Day/Core/Services/MADBackgroundService.swift"
git commit -m "Add unified performBackgroundSync entry point for background wake-ups"
```

---

## Task 3: Handle background launch from HealthKit delivery in `AppDelegate`

**Files:**
- Modify: `app/Mile A Day/AppDelegate.swift`

**Why:** When iOS relaunches the app into the background because a new workout landed in HealthKit, the scene does not come up, so the `UIApplication.didEnterBackgroundNotification` / `UIApplication.willEnterForegroundNotification` publishers wired in `Mile_A_DayApp` never fire. The lifecycle hook that *does* fire is `application(_:didFinishLaunchingWithOptions:)`. We need to detect that the app launched into the background state and trigger a sync.

- [ ] **Step 1: Add a background-launch trigger in `didFinishLaunchingWithOptions`**

Replace the body of the existing `application(_:didFinishLaunchingWithOptions:)` (lines 12-18) with:

```swift
func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    // Ensure the notification delegate is set before the system delivers
    // a pending notification response on cold launch.
    _ = MADNotificationService.shared

    // If iOS launched us in the background (no UI scene), kick off a sync immediately.
    // For UI launches, the scene lifecycle in Mile_A_DayApp handles the sync.
    if application.applicationState == .background {
        print("[AppDelegate] Launched in background — triggering performBackgroundSync")
        Task {
            await MADBackgroundService.shared.performBackgroundSync(reason: .backgroundLaunch)
        }
    }

    return true
}
```

- [ ] **Step 2: Verify build**

Build the app (⌘B). Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add "app/Mile A Day/AppDelegate.swift"
git commit -m "Trigger background sync when app is launched into background state"
```

---

## Task 4: Handle silent (`content-available`) push in `AppDelegate`

**Files:**
- Modify: `app/Mile A Day/AppDelegate.swift`

**Why:** The scheduled silent push fires `aps.content-available = 1` with `type: "background_sync"`. To wake the app and grant background execution time, we must implement `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` and call the OS-provided completion handler within ~30 seconds.

- [ ] **Step 1: Add the remote notification handler**

Append this method to `AppDelegate` (after `didFailToRegisterForRemoteNotificationsWithError` at line 38):

```swift
func application(_ application: UIApplication,
                 didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                 fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    // Only handle our background_sync silent pushes here. Other push types
    // are visible alerts and are handled by UNUserNotificationCenterDelegate.
    let aps = userInfo["aps"] as? [String: Any]
    let contentAvailable = (aps?["content-available"] as? Int) ?? 0
    let type = userInfo["type"] as? String

    guard contentAvailable == 1, type == "background_sync" else {
        completionHandler(.noData)
        return
    }

    print("[AppDelegate] Received background_sync silent push")
    Task {
        await MADBackgroundService.shared.performBackgroundSync(reason: .silentPush)
        completionHandler(.newData)
    }
}
```

- [ ] **Step 2: Verify build**

Build (⌘B). Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add "app/Mile A Day/AppDelegate.swift"
git commit -m "Handle background_sync silent push to trigger workout sync"
```

---

## Task 5: Add a `sendSilentPushToUser` helper in the backend push service

**Files:**
- Modify: `backend/src/services/pushNotificationService.ts`

**Why:** Existing `sendToDevice` always sets `apns-push-type: alert`, `apns-priority: 10`, and an `aps.alert` payload — this is wrong for silent pushes. Silent (background) pushes need `apns-push-type: background`, `apns-priority: 5`, and an `aps.content-available: 1` payload with no `alert`/`sound`/`badge`. We add a parallel function rather than overloading `sendToDevice` to keep the call sites readable and avoid accidentally turning visible pushes into silent ones.

- [ ] **Step 1: Add a `sendSilentPush` internal helper and `sendSilentPushToUser` exported function**

Append the following to `backend/src/services/pushNotificationService.ts` (after `unregisterDeviceToken` at line 308, before the `// ─── Quiet Hours & Batching ───` section heading):

```typescript
// ─── Silent (background) pushes ─────────────────────────────────────

/**
 * APNs silent push. Wakes the app to do background work; renders nothing.
 * Do not call directly — use sendSilentPushToUser.
 */
function sendSilentPushToDevice(deviceToken: string, type: string, data: Record<string, string> = {}): Promise<boolean> {
	return new Promise(resolve => {
		const token = getApnsToken();
		if (!token || !APNS_BUNDLE_ID) {
			console.warn('[Push] APNs not configured, skipping silent push');
			resolve(false);
			return;
		}

		const apnsPayload = JSON.stringify({
			aps: { 'content-available': 1 },
			type,
			data
		});

		const client = http2.connect(APNS_HOST);

		client.on('error', err => {
			console.error('[Push] Silent HTTP/2 connection error:', err.message);
			client.close();
			resolve(false);
		});

		const req = client.request({
			':method': 'POST',
			':path': `/3/device/${deviceToken}`,
			'authorization': `bearer ${token}`,
			'apns-topic': APNS_BUNDLE_ID,
			'apns-push-type': 'background',
			'apns-priority': '5',
			'content-type': 'application/json'
		});

		let responseData = '';
		let statusCode = 0;

		req.on('response', headers => {
			statusCode = headers[':status'] as number;
		});

		req.on('data', chunk => {
			responseData += chunk;
		});

		req.on('end', () => {
			client.close();
			if (statusCode === 200) {
				resolve(true);
			} else {
				console.error(`[Push] Silent APNs error ${statusCode}: ${responseData}`);
				if (statusCode === 410 || (statusCode === 400 && responseData.includes('BadDeviceToken'))) {
					removeInvalidToken(deviceToken).catch(() => {});
				}
				resolve(false);
			}
		});

		req.on('error', err => {
			console.error('[Push] Silent request error:', err.message);
			client.close();
			resolve(false);
		});

		req.write(apnsPayload);
		req.end();
	});
}

/**
 * Send a silent (content-available) push to every registered device of a user.
 * Skips throttling, quiet hours, in-app inbox storage, and notification_log writes.
 * These pushes are invisible to the user and have no per-day cap concern.
 */
export async function sendSilentPushToUser(userId: string, type: string, data: Record<string, string> = {}): Promise<number> {
	const tokens = await db.query<{ device_token: string }>(
		'SELECT device_token FROM device_tokens WHERE user_id = $1',
		[userId]
	);
	if (tokens.length === 0) return 0;

	const results = await Promise.all(tokens.map(({ device_token }) => sendSilentPushToDevice(device_token, type, data)));
	return results.filter(Boolean).length;
}
```

- [ ] **Step 2: Verify build**

```bash
cd backend && npm run build
```

Expected: `tsc` produces no errors.

- [ ] **Step 3: Commit**

```bash
git add backend/src/services/pushNotificationService.ts
git commit -m "Add silent (background) push helper to push notification service"
```

---

## Task 6: Add the silent-sync cron job and register it

**Files:**
- Create: `backend/src/cron/silentSyncCron.ts`
- Modify: `backend/src/server.ts`

**Why:** Schedules a `background_sync` silent push to every user with a device token at 8am / 12pm / 4pm / 8pm ET. Matches the existing `notificationCron` ET-based pattern (the project has no per-user timezone column).

- [ ] **Step 1: Create the cron file**

Create `backend/src/cron/silentSyncCron.ts` with the following content:

```typescript
import cron from 'node-cron';
import { PostgresService } from '../services/DbService.js';
import { sendSilentPushToUser } from '../services/pushNotificationService.js';

const db = PostgresService.getInstance();

/**
 * Trigger the background-sync silent push for every user with a registered device token.
 * Exported so dev routes can invoke it on-demand.
 */
export async function runSilentSyncPushFanout(): Promise<{ users: number; pushes: number }> {
	const rows = await db.query<{ user_id: string }>(
		`SELECT DISTINCT user_id FROM device_tokens`
	);

	let pushes = 0;
	for (const { user_id } of rows) {
		try {
			pushes += await sendSilentPushToUser(user_id, 'background_sync');
		} catch (err: any) {
			console.error(`[SilentSyncCron] Error pushing user ${user_id}:`, err.message);
		}
	}

	return { users: rows.length, pushes };
}

export function startSilentSyncCron(): void {
	// 4x daily at 8am, 12pm, 4pm, 8pm ET.
	cron.schedule(
		'0 8,12,16,20 * * *',
		async () => {
			console.log('[CRON] Silent sync push fanout starting...');
			try {
				const { users, pushes } = await runSilentSyncPushFanout();
				console.log(`[CRON] Silent sync push fanout complete: ${users} users, ${pushes} pushes`);
			} catch (err: any) {
				console.error('[CRON] Silent sync push fanout failed:', err.message);
			}
		},
		{ timezone: 'America/New_York' }
	);

	console.log('Silent sync push cron scheduled (8am, 12pm, 4pm, 8pm ET).');
}
```

- [ ] **Step 2: Register the cron in `server.ts`**

In `backend/src/server.ts`, add this import alongside the other cron imports (near line 19, after `startNotificationCron`):

```typescript
import { startSilentSyncCron } from './cron/silentSyncCron.js';
```

Then find the existing cron startup block (search for `startNotificationCron()`) and add a call right after:

```typescript
startSilentSyncCron();
```

- [ ] **Step 3: Build to verify everything compiles**

```bash
cd backend && npm run build
```

Expected: `tsc` produces no errors.

- [ ] **Step 4: Smoke-run the dev server**

```bash
cd backend && npm run dev
```

Expected log lines on startup include:

```
Silent sync push cron scheduled (8am, 12pm, 4pm, 8pm ET).
```

Stop with Ctrl-C.

- [ ] **Step 5: Commit**

```bash
git add backend/src/cron/silentSyncCron.ts backend/src/server.ts
git commit -m "Schedule background_sync silent push 4x daily ET to wake iOS clients"
```

---

## Task 7: Add a dev-only endpoint to trigger the silent-sync cron on demand

**Files:**
- Modify: `backend/src/controllers/devController.ts`
- Modify: `backend/src/routes/devRoutes.ts`

**Why:** Verifying the silent push flow on a physical device requires being able to fire the push immediately, not waiting for 8am ET. This endpoint sits under the existing `/dev/*` mount (public, behind the convention that dev routes are not exposed in production builds).

- [ ] **Step 1: Add a controller**

Open `backend/src/controllers/devController.ts` and append:

```typescript
import { runSilentSyncPushFanout } from '../cron/silentSyncCron.js';
import { sendSilentPushToUser } from '../services/pushNotificationService.js';
import type { Request, Response } from 'express';

export async function triggerSilentSyncFanout(req: Request, res: Response): Promise<void> {
	try {
		const result = await runSilentSyncPushFanout();
		res.json({ success: true, ...result });
	} catch (err: any) {
		res.status(500).json({ success: false, error: err.message });
	}
}

export async function triggerSilentSyncForUser(req: Request, res: Response): Promise<void> {
	const userId = req.params.userId;
	if (!userId) {
		res.status(400).json({ success: false, error: 'userId required' });
		return;
	}
	try {
		const pushes = await sendSilentPushToUser(userId, 'background_sync');
		res.json({ success: true, userId, pushes });
	} catch (err: any) {
		res.status(500).json({ success: false, error: err.message });
	}
}
```

(If existing controllers in this file already import `Request`/`Response` from `express`, deduplicate the imports — keep the existing ones and drop the new `import type` line.)

- [ ] **Step 2: Wire the routes**

Open `backend/src/routes/devRoutes.ts`. Replace its contents with:

```typescript
import { Router } from 'express';
import {
	generateTestToken,
	triggerCompetitionCron,
	sendTestNotification,
	triggerSilentSyncFanout,
	triggerSilentSyncForUser
} from '../controllers/devController.js';

const router = Router();

router.post('/test-token', generateTestToken);
router.post('/run-competition-cron', triggerCompetitionCron);
router.post('/test-notification', sendTestNotification);
router.post('/silent-sync-fanout', triggerSilentSyncFanout);
router.post('/silent-sync/:userId', triggerSilentSyncForUser);

export default router;
```

- [ ] **Step 3: Build**

```bash
cd backend && npm run build
```

Expected: clean build.

- [ ] **Step 4: Smoke test the endpoint**

Start the dev server:

```bash
cd backend && npm run dev
```

In another terminal, hit the per-user endpoint with your real backend user id:

```bash
curl -sX POST http://localhost:3000/dev/silent-sync/<YOUR_USER_ID> | jq
```

Expected JSON:

```json
{ "success": true, "userId": "<YOUR_USER_ID>", "pushes": 1 }
```

Backend log should include a `[Push] Silent APNs ...` line on failure, or be silent on success.

Stop the dev server with Ctrl-C.

- [ ] **Step 5: Commit**

```bash
git add backend/src/controllers/devController.ts backend/src/routes/devRoutes.ts
git commit -m "Add /dev/silent-sync endpoints to trigger fanout on demand"
```

---

## Task 8: End-to-end verification on a physical device

**Files:** none.

**Why:** No automated tests cover this flow end-to-end (no XCUITest harness, no backend integration suite). This task is the gate before merge.

- [ ] **Step 1: Install build on a physical iPhone**

Connect your iPhone, select it as the run destination in Xcode, build & run. (Simulators do not deliver real APNs nor wake the app from HealthKit background delivery — physical hardware is required.)

- [ ] **Step 2: Confirm device token registration**

In Xcode Console, filter for `[AppDelegate] APNs device token:` — it should print the truncated token. The backend log should show a successful `POST /devices` (or whatever the existing registration endpoint is) and the row should be visible in `device_tokens` for your `user_id`.

- [ ] **Step 3: Verify the silent push path**

With the app force-quit (swipe up from the app switcher), POST to the dev endpoint:

```bash
curl -sX POST https://mad.mindgoblin.tech/dev/silent-sync/<YOUR_USER_ID>
```

Within a few seconds:
- Xcode Console (still attached even after force quit on a debug build) should print:

```
[AppDelegate] Received background_sync silent push
[MADBackgroundService] performBackgroundSync(reason: silentPush)
[Background] Updating user with HealthKit data ...
```

- If you have an unsynced workout in HealthKit, the upload should hit the backend within ~30s.

- [ ] **Step 4: Verify the HealthKit observer path**

With the app force-quit, complete a short workout via Apple Health (record an "Other" workout manually, or finish a run on the Watch). Watch Xcode Console for:

```
[MADBackgroundService] performBackgroundSync(reason: healthKitObserver)
[Background] Updating user ...
```

If you also hit the daily mile goal in that workout, a local "mile completed" notification should appear on the lock screen.

- [ ] **Step 5: Verify the BGAppRefreshTask path**

In Xcode, while the app is paused (suspended state, app icon visible but app inactive), use **Debug → Simulate Background App Refresh**. Console should print:

```
[MADBackgroundService] performBackgroundSync(reason: bgAppRefreshTask)
```

- [ ] **Step 6: Sanity-check the cron registration**

Tail the production backend log around the next scheduled hour (8/12/16/20 ET). Expected:

```
[CRON] Silent sync push fanout starting...
[CRON] Silent sync push fanout complete: N users, M pushes
```

- [ ] **Step 7: Open a PR**

Spec satisfied; ready for merge.

---

## Self-Review Notes

Spec coverage (each requirement → task that implements it):

- iOS UIBackgroundModes + BGTask identifier declared → Task 1
- `HKObserverQuery` background delivery (already exists, completion handler call already in place at `MADBackgroundService.swift:87`) → no code change; unblocked by Task 1
- Unified `performBackgroundSync` entry point → Task 2
- Background launch (no UI) triggers a sync → Task 3
- Silent push handler in `AppDelegate` → Task 4
- Backend `sendSilentPushToUser` helper → Task 5
- 4×/day scheduled silent push fanout cron → Task 6
- Dev-only on-demand trigger for verification → Task 7
- Manual end-to-end verification → Task 8

Cross-task type consistency: `performBackgroundSync(reason:)` and `BackgroundSyncReason` defined in Task 2 are used unchanged in Tasks 3 and 4. The push `type` string `"background_sync"` is used identically in Tasks 4 (iOS handler check), 6 (cron call), and 7 (per-user trigger). The cron function name `runSilentSyncPushFanout` is defined in Task 6 and re-imported in Task 7.

No placeholders; every code step shows complete code.
