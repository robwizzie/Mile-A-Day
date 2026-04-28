# Hype Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "hype" reaction that lets a user celebrate a friend or competition co-participant who completed today's mile, delivered as a one-tap rich-notification action button on the existing `friend_activity` push.

**Architecture:** Mirrors the existing `flex` / `friendNudge` shape — service helper for rate limiting, controller, route, augmented APNs payload — plus an iOS `UNNotificationCategory` with a `HYPE_ACTION` button whose handler hits `POST /hype`. No persistent recipient artifact in v1; the push *is* the UX.

**Tech Stack:** TypeScript / Express 5.1 / PostgreSQL on the backend; Swift / SwiftUI / `UserNotifications` framework on iOS. ESM imports require `.js` extensions per `.claude/rules/backend.md`.

**Note on testing:** This repo has no test runner. Verification is via `npm run build` (TypeScript typecheck), `/api-test` curl flows, and physical-device iOS testing. Each task ends with a build + commit. The TDD pattern from `superpowers:writing-plans` does not apply here; we follow the existing flex/nudge convention.

**Spec:** `docs/superpowers/specs/2026-04-27-hype-feature-design.md`

---

## Phase 1 — Backend

### Task 1: Create `hype_log` table

**Files:**
- Create (manual SQL): apply to PostgreSQL via `psql` or `/db-query`

- [ ] **Step 1: Apply schema**

Run against the database (use `$DATABASE_URL` or `/db-query`):

```sql
CREATE TABLE hype_log (
  id          BIGSERIAL PRIMARY KEY,
  sender_id   UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  target_id   UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX hype_log_sender_created_idx ON hype_log (sender_id, created_at DESC);
```

- [ ] **Step 2: Verify table exists**

Run via `/db-query`:

```sql
SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'hype_log' ORDER BY ordinal_position;
```

Expected output: 4 rows — `id bigint`, `sender_id uuid`, `target_id uuid`, `created_at timestamp with time zone`.

- [ ] **Step 3: No commit yet** — DB schema is applied manually, not tracked in git (per `backend.md`: "No migrations system"). Move on.

---

### Task 2: Add `hypes_enabled` column + extend `notificationSettingsService`

**Files:**
- DB: add column to `notification_settings`
- Modify: `backend/src/services/notificationSettingsService.ts`

- [ ] **Step 1: Apply DB column**

```sql
ALTER TABLE notification_settings ADD COLUMN IF NOT EXISTS hypes_enabled BOOLEAN NOT NULL DEFAULT TRUE;
```

- [ ] **Step 2: Update `NotificationPreferences` interface**

In `backend/src/services/notificationSettingsService.ts`, modify the interface (around line 7-16):

```typescript
export interface NotificationPreferences {
	nudges_enabled: boolean;
	flexes_enabled: boolean;
	hypes_enabled: boolean;
	friend_activity_enabled: boolean;
	competition_invites_enabled: boolean;
	competition_updates_enabled: boolean;
	competition_milestones_enabled: boolean;
	quiet_hours_start: number | null;
	quiet_hours_end: number | null;
}
```

- [ ] **Step 3: Update `DEFAULT_PREFERENCES`**

Around line 18-27:

```typescript
const DEFAULT_PREFERENCES: NotificationPreferences = {
	nudges_enabled: true,
	flexes_enabled: true,
	hypes_enabled: true,
	friend_activity_enabled: true,
	competition_invites_enabled: true,
	competition_updates_enabled: true,
	competition_milestones_enabled: true,
	quiet_hours_start: null,
	quiet_hours_end: null,
};
```

- [ ] **Step 4: Update `getNotificationPreferences` mapping**

Around line 38-47, add the line:

```typescript
hypes_enabled: row.hypes_enabled ?? true,
```

…immediately after `flexes_enabled`.

- [ ] **Step 5: Update `updateNotificationPreferences` field list**

Around line 60-69, add `{ key: 'hypes_enabled', value: prefs.hypes_enabled }` immediately after `flexes_enabled`.

- [ ] **Step 6: Extend `shouldSendNotification` type and switch**

Around line 184-211, change the union type to include `'hype'` and add a switch case:

```typescript
export async function shouldSendNotification(
	targetUserId: string,
	senderId: string | null,
	notificationType: 'nudge' | 'flex' | 'hype' | 'friend_activity' | 'competition_invite' | 'competition_update' | 'competition_milestone'
): Promise<boolean> {
	const prefs = await getNotificationPreferences(targetUserId);

	switch (notificationType) {
		case 'nudge':
			if (!prefs.nudges_enabled) return false;
			break;
		case 'flex':
			if (!prefs.flexes_enabled) return false;
			break;
		case 'hype':
			if (!prefs.hypes_enabled) return false;
			break;
		case 'friend_activity':
			if (!prefs.friend_activity_enabled) return false;
			break;
		case 'competition_invite':
			if (!prefs.competition_invites_enabled) return false;
			break;
		case 'competition_update':
			if (!prefs.competition_updates_enabled) return false;
			break;
		case 'competition_milestone':
			if (!prefs.competition_milestones_enabled) return false;
			break;
	}
	// ...rest of function unchanged
```

(Leave the friend-specific muting block below untouched.)

- [ ] **Step 7: Build**

```bash
cd backend && npm run build
```

Expected: clean compile, exit 0.

- [ ] **Step 8: Commit**

```bash
git add backend/src/services/notificationSettingsService.ts
git commit -m "Add hypes_enabled to notification preferences"
```

---

### Task 3: Create `hypeService.ts` (rate-limit helpers + log)

**Files:**
- Create: `backend/src/services/hypeService.ts`

- [ ] **Step 1: Create the service file**

```typescript
import { PostgresService } from './DbService.js';

const db = PostgresService.getInstance();

export const HYPE_DAILY_LIMIT = 3;

/**
 * Count of hypes the sender has sent in the last 24 hours (rolling window).
 */
export async function getDailyHypeCount(senderId: string): Promise<number> {
	const rows = await db.query<{ count: string }>(
		`SELECT COUNT(*)::text AS count FROM hype_log
		WHERE sender_id = $1
			AND created_at > NOW() - INTERVAL '24 hours'`,
		[senderId]
	);
	return parseInt(rows[0]?.count ?? '0', 10);
}

/**
 * Returns true if the sender has fewer than HYPE_DAILY_LIMIT hypes in the last 24h.
 */
export async function canHype(senderId: string): Promise<boolean> {
	const count = await getDailyHypeCount(senderId);
	return count < HYPE_DAILY_LIMIT;
}

/**
 * Insert a hype_log row. Returns the new row's id and created_at so callers
 * can roll back if a post-insert recount finds the sender over the limit
 * (race-condition mitigation).
 */
export async function logHype(senderId: string, targetId: string): Promise<{ id: string; created_at: string }> {
	const rows = await db.query<{ id: string; created_at: string }>(
		`INSERT INTO hype_log (sender_id, target_id) VALUES ($1, $2)
		RETURNING id, created_at`,
		[senderId, targetId]
	);
	return rows[0];
}

/**
 * Delete a previously-inserted hype_log row by id. Used to roll back a
 * race-induced over-limit insert.
 */
export async function deleteHype(id: string): Promise<void> {
	await db.query(`DELETE FROM hype_log WHERE id = $1`, [id]);
}

/**
 * Returns ISO timestamp when the sender's oldest in-window hype rolls off,
 * unlocking their next slot. Returns null if they have spare capacity.
 */
export async function getHypeResetsAt(senderId: string): Promise<string | null> {
	const count = await getDailyHypeCount(senderId);
	if (count < HYPE_DAILY_LIMIT) return null;

	const rows = await db.query<{ rolls_off: string }>(
		`SELECT (created_at + INTERVAL '24 hours')::text AS rolls_off
		FROM hype_log
		WHERE sender_id = $1
			AND created_at > NOW() - INTERVAL '24 hours'
		ORDER BY created_at ASC
		LIMIT 1`,
		[senderId]
	);
	return rows[0]?.rolls_off ?? null;
}
```

- [ ] **Step 2: Build**

```bash
cd backend && npm run build
```

Expected: clean compile.

- [ ] **Step 3: Commit**

```bash
git add backend/src/services/hypeService.ts
git commit -m "Add hypeService with rate-limit helpers"
```

---

### Task 4: Create `hypeController.ts`

**Files:**
- Create: `backend/src/controllers/hypeController.ts`

- [ ] **Step 1: Inspect existing helpers we'll call**

Skim these so the controller calls them correctly:

- `getFriendship(senderId, targetId)` from `services/friendshipService.ts` — returns friendship row, or `{ error }`, or undefined; success means `status === 'accepted'`.
- `getTodayMiles(userId)` from `services/workoutService.ts` — returns number of miles completed today.
- `getUser({ userId })` from `services/userService.ts` — returns user row with `username`.
- `sendPush(userId, payload)` from `services/pushNotificationService.ts`.
- `shouldSendNotification(targetId, senderId, type)` from `services/notificationSettingsService.ts`.

We also need a helper to detect "shared active competition" — write it inline as a private query, since no existing helper does exactly this.

- [ ] **Step 2: Create the controller file**

```typescript
import { Response } from 'express';
import { AuthenticatedRequest } from '../middleware/auth.js';
import { PostgresService } from '../services/DbService.js';
import { getFriendship } from '../services/friendshipService.js';
import { getTodayMiles } from '../services/workoutService.js';
import { getUser } from '../services/userService.js';
import { sendPush } from '../services/pushNotificationService.js';
import { shouldSendNotification } from '../services/notificationSettingsService.js';
import {
	canHype,
	logHype,
	deleteHype,
	getDailyHypeCount,
	getHypeResetsAt,
	HYPE_DAILY_LIMIT,
} from '../services/hypeService.js';

const db = PostgresService.getInstance();

/**
 * Returns true if sender and target are accepted participants in at least
 * one currently-active competition.
 */
async function shareActiveCompetition(senderId: string, targetId: string): Promise<boolean> {
	const rows = await db.query<{ exists: boolean }>(
		`SELECT EXISTS (
			SELECT 1
			FROM competition_users cu_sender
			JOIN competition_users cu_target ON cu_target.competition_id = cu_sender.competition_id
			JOIN competitions c ON c.id = cu_sender.competition_id
			WHERE cu_sender.user_id = $1
				AND cu_target.user_id = $2
				AND cu_sender.invite_status = 'accepted'
				AND cu_target.invite_status = 'accepted'
				AND c.start_date IS NOT NULL
				AND c.start_date <= NOW()
				AND c.winner IS NULL
				AND (c.end_date IS NULL OR c.end_date > NOW())
		) AS exists`,
		[senderId, targetId]
	);
	return rows[0]?.exists === true;
}

async function isFriendOrCoParticipant(senderId: string, targetId: string): Promise<boolean> {
	const friendship = await getFriendship(senderId, targetId);
	const friendsAccepted = friendship && !('error' in friendship) && friendship.status === 'accepted';
	if (friendsAccepted) return true;
	return shareActiveCompetition(senderId, targetId);
}

export async function sendHype(req: AuthenticatedRequest, res: Response) {
	const senderId = req.userId!;
	const targetUserId = req.body?.target_user_id;

	try {
		// 1. Basic validation
		if (!targetUserId || typeof targetUserId !== 'string') {
			return res.status(400).json({ error: 'target_user_id is required' });
		}
		if (senderId === targetUserId) {
			return res.status(400).json({ error: "You can't hype yourself" });
		}

		// 2. Relationship check
		const allowed = await isFriendOrCoParticipant(senderId, targetUserId);
		if (!allowed) {
			return res.status(403).json({
				error: 'You can only hype friends or people in your active competitions',
			});
		}

		// 3. Target must have completed their mile today
		const todayMiles = await getTodayMiles(targetUserId);
		if (todayMiles < 1.0) {
			return res.status(400).json({ error: "This user hasn't completed their mile today" });
		}

		// 4. Rate limit pre-check
		if (!(await canHype(senderId))) {
			return res.status(429).json({
				error: `You've used all ${HYPE_DAILY_LIMIT} hypes for the day`,
				hypes_remaining: 0,
				resets_at: await getHypeResetsAt(senderId),
			});
		}

		// 5. Insert, then post-insert recount to mitigate race
		const inserted = await logHype(senderId, targetUserId);
		const countAfter = await getDailyHypeCount(senderId);
		if (countAfter > HYPE_DAILY_LIMIT) {
			await deleteHype(inserted.id);
			return res.status(429).json({
				error: `You've used all ${HYPE_DAILY_LIMIT} hypes for the day`,
				hypes_remaining: 0,
				resets_at: await getHypeResetsAt(senderId),
			});
		}

		// 6. Push (best-effort; failure does not roll back the log)
		const shouldSend = await shouldSendNotification(targetUserId, senderId, 'hype');
		if (shouldSend) {
			const sender = await getUser({ userId: senderId });
			const senderName = sender?.username ?? 'Someone';
			await sendPush(targetUserId, {
				title: '🔥 You got hyped!',
				body: `@${senderName} just hyped up your recent workout!`,
				type: 'hype_received',
				data: { user_id: senderId },
			});
		}

		res.status(200).json({
			message: 'Hype sent',
			hypes_remaining: Math.max(0, HYPE_DAILY_LIMIT - countAfter),
		});
	} catch (error: any) {
		console.error('Error sending hype:', error.message);
		res.status(500).json({ error: 'Error sending hype' });
	}
}

export async function getHypeStatus(req: AuthenticatedRequest, res: Response) {
	const senderId = req.userId!;
	try {
		const [count, resetsAt] = await Promise.all([
			getDailyHypeCount(senderId),
			getHypeResetsAt(senderId),
		]);
		res.status(200).json({
			hypes_remaining: Math.max(0, HYPE_DAILY_LIMIT - count),
			resets_at: resetsAt,
		});
	} catch (error: any) {
		console.error('Error getting hype status:', error.message);
		res.status(500).json({ error: 'Error getting hype status' });
	}
}
```

- [ ] **Step 3: Build**

```bash
cd backend && npm run build
```

Expected: clean compile.

- [ ] **Step 4: Commit**

```bash
git add backend/src/controllers/hypeController.ts
git commit -m "Add hypeController with sendHype and getHypeStatus"
```

---

### Task 5: Create `hypeRoutes.ts` and register in `server.ts`

**Files:**
- Create: `backend/src/routes/hypeRoutes.ts`
- Modify: `backend/src/server.ts`

- [ ] **Step 1: Create the route file**

```typescript
import { Router } from 'express';
import { sendHype, getHypeStatus } from '../controllers/hypeController.js';

const router = Router();

router.post('/', sendHype);
router.get('/status', getHypeStatus);

export default router;
```

- [ ] **Step 2: Register in `server.ts`**

In `backend/src/server.ts`, add the import alongside other route imports near the top:

```typescript
import hypeRoutes from './routes/hypeRoutes.js';
```

And add the mount line *after* `authenticateToken`, after the existing `app.use('/notifications', notificationRoutes);` line (around line 71):

```typescript
app.use('/hype', hypeRoutes);
```

- [ ] **Step 3: Build**

```bash
cd backend && npm run build
```

Expected: clean compile.

- [ ] **Step 4: Commit**

```bash
git add backend/src/routes/hypeRoutes.ts backend/src/server.ts
git commit -m "Register POST /hype and GET /hype/status routes"
```

---

### Task 6: Augment `friend_activity` push with `category` and competition co-participant fanout

**Files:**
- Modify: `backend/src/services/notificationService.ts` (the `friend_activity` fanout function near the top of the file)

- [ ] **Step 1: Read the current `friend_activity` fanout function**

In `backend/src/services/notificationService.ts`, locate the function that fans out the friend_activity push (it queries `friendships`, sends to up to 5 friends with `type: 'friend_activity'`). Currently lines ~30-67.

- [ ] **Step 2: Replace the fanout body to add `category`, dedup, and co-participant extension**

Replace the body of that function (keep the function name and signature). The new body:

```typescript
try {
	const [user] = await db.query('SELECT username FROM users WHERE user_id = $1', [userId]);
	if (!user) return;

	// Friends (bidirectional accepted)
	const friendRows = await db.query<{ friend_id: string }>(
		`SELECT friend_id FROM friendships WHERE user_id = $1 AND status = 'accepted'`,
		[userId]
	);

	// Active-competition co-participants (other accepted users in the runner's active comps)
	const compRows = await db.query<{ user_id: string }>(
		`SELECT DISTINCT cu_other.user_id
		FROM competition_users cu_self
		JOIN competition_users cu_other ON cu_other.competition_id = cu_self.competition_id
		JOIN competitions c ON c.id = cu_self.competition_id
		WHERE cu_self.user_id = $1
			AND cu_other.user_id <> $1
			AND cu_self.invite_status = 'accepted'
			AND cu_other.invite_status = 'accepted'
			AND c.start_date IS NOT NULL
			AND c.start_date <= NOW()
			AND c.winner IS NULL
			AND (c.end_date IS NULL OR c.end_date > NOW())`,
		[userId]
	);

	const friendIds = friendRows.map(r => r.friend_id);
	const friendSet = new Set(friendIds);
	const coParticipantIds = compRows
		.map(r => r.user_id)
		.filter(id => !friendSet.has(id));

	// Cap: up to 5 friends + up to 5 unique co-participants = max 10 recipients
	const friendsToNotify = friendIds.slice(0, 5);
	const coParticipantsToNotify = coParticipantIds.slice(0, 5);
	const recipients = [...friendsToNotify, ...coParticipantsToNotify];

	if (recipients.length === 0) return;

	const title = `${user.username} got their mile in!`;
	const body = 'Your friend just completed their daily mile. Time to lace up!';

	let sentCount = 0;
	for (const recipientId of recipients) {
		const ok = await shouldSendNotification(recipientId, userId, 'friend_activity');
		if (!ok) continue;

		sendPush(recipientId, {
			title,
			body,
			type: 'friend_activity',
			category: 'FRIEND_ACTIVITY',
			data: { user_id: userId },
		}).catch(err => console.error('[Push] Error sending friend activity:', err.message));
		sentCount++;
	}

	if (sentCount > 0) {
		console.log(`[Notifications] Sent mile completion to ${sentCount} recipients of ${user.username}`);
	}
} catch (err: any) {
	console.error('[Notifications] Error notifying friends of mile completion:', err.message);
}
```

- [ ] **Step 3: Verify `sendPush` payload type accepts `category`**

Open `backend/src/services/pushNotificationService.ts` and locate the type definition for the `payload` argument of `sendPush` (search for `interface PushPayload` or similar). If `category?: string` is not already present, add it.

```typescript
// In the PushPayload (or equivalent) type:
category?: string;
```

Then in the body that constructs the APNs request from the payload, forward `category` into the APNs `aps` dictionary:

```typescript
// Wherever the aps dict is built:
const aps: Record<string, any> = {
	alert: { title: payload.title, body: payload.body },
	sound: 'default',
};
if (payload.category) aps.category = payload.category;
// ... existing code that adds aps.thread_id etc.
```

(If the existing code already conditionally adds `aps.category`, leave it alone.)

- [ ] **Step 4: Build**

```bash
cd backend && npm run build
```

Expected: clean compile. If the `PushPayload` type lives in a different file, fix the import there too until build passes.

- [ ] **Step 5: Commit**

```bash
git add backend/src/services/notificationService.ts backend/src/services/pushNotificationService.ts
git commit -m "Extend friend_activity fanout to competition co-participants and add APNs category"
```

---

### Task 7: Backend manual verification

**Files:** none (verification only)

- [ ] **Step 1: Start dev server**

```bash
cd backend && npm run dev
```

Watch logs for `Server running on port…` and no import errors.

- [ ] **Step 2: Get a JWT for two test users**

Use existing dev login flows or `/auth` endpoints to obtain `$ALICE_TOKEN` and `$BOB_TOKEN`. Note their `user_id`s as `$ALICE_ID` and `$BOB_ID`.

Pre-condition: Bob has run ≥ 1 mile today, Alice and Bob are friends or share an active competition.

- [ ] **Step 3: Happy path — Alice hypes Bob**

```bash
curl -i -X POST http://localhost:3000/hype \
  -H "Authorization: Bearer $ALICE_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"target_user_id\":\"$BOB_ID\"}"
```

Expected: `200 OK`, body `{ "message": "Hype sent", "hypes_remaining": 2 }`. Bob's device receives a push titled `🔥 You got hyped!`.

- [ ] **Step 4: Self-hype rejection**

```bash
curl -i -X POST http://localhost:3000/hype \
  -H "Authorization: Bearer $ALICE_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"target_user_id\":\"$ALICE_ID\"}"
```

Expected: `400`, body contains `"You can't hype yourself"`.

- [ ] **Step 5: Target hasn't run today**

Use a target user `$CHARLIE_ID` who has 0 miles today and is a friend.

```bash
curl -i -X POST http://localhost:3000/hype \
  -H "Authorization: Bearer $ALICE_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"target_user_id\":\"$CHARLIE_ID\"}"
```

Expected: `400`, body contains `"hasn't completed their mile today"`.

- [ ] **Step 6: Not friends and no shared competition**

Use `$STRANGER_ID` — no friendship, no shared active competition, completed mile today.

```bash
curl -i -X POST http://localhost:3000/hype \
  -H "Authorization: Bearer $ALICE_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"target_user_id\":\"$STRANGER_ID\"}"
```

Expected: `403`.

- [ ] **Step 7: Daily limit**

Hype 3 valid targets in succession from Alice's account. The 4th request:

```bash
curl -i -X POST http://localhost:3000/hype \
  -H "Authorization: Bearer $ALICE_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"target_user_id\":\"$BOB_ID\"}"
```

Expected: `429`, body `{ "error": "You've used all 3 hypes for the day", "hypes_remaining": 0, "resets_at": "<ISO>" }`.

- [ ] **Step 8: Status endpoint**

```bash
curl -i http://localhost:3000/hype/status -H "Authorization: Bearer $ALICE_TOKEN"
```

Expected: `200`, body `{ "hypes_remaining": 0, "resets_at": "<ISO>" }`.

- [ ] **Step 9: Recipient with `'hype'` notifications disabled**

In another shell, mark Bob's `hypes_enabled = false`:

```sql
UPDATE notification_settings SET hypes_enabled = false WHERE user_id = '<BOB_ID>';
```

(You may need to first `INSERT` a row if Bob has none.)

Hype Bob from another sender. Expected: endpoint returns `200`, but Bob receives no push. `hype_log` row still inserted.

Re-enable:

```sql
UPDATE notification_settings SET hypes_enabled = true WHERE user_id = '<BOB_ID>';
```

- [ ] **Step 10: DB inspection**

```sql
SELECT sender_id, target_id, created_at FROM hype_log ORDER BY created_at DESC LIMIT 10;
```

Expected: rows match the calls just made.

- [ ] **Step 11: No commit** — verification step. If any check fails, return to the relevant earlier task and fix.

---

## Phase 2 — iOS

### Task 8: Create `HypeService.swift`

**Files:**
- Create: `app/Mile A Day/Services/HypeService.swift`

- [ ] **Step 1: Create the service file**

```swift
import Foundation

/// Response shape from POST /hype.
struct HypeResponse: Decodable {
    let message: String
    let hypes_remaining: Int
}

/// Response shape from GET /hype/status.
struct HypeStatusResponse: Decodable {
    let hypes_remaining: Int
    let resets_at: String?
}

/// Sends and queries hype state. Stateless; safe to call from anywhere
/// including the notification action handler.
enum HypeService {
    /// Sends a hype to the target user.
    /// - Returns: response with the sender's remaining daily quota.
    /// - Throws: `APIError` on transport or auth failure. Callers should
    ///   surface 429 distinctly via the `APIError.httpStatus(429)` case.
    static func sendHype(targetUserId: String) async throws -> HypeResponse {
        struct Body: Encodable { let target_user_id: String }
        let bodyData = try JSONEncoder().encode(Body(target_user_id: targetUserId))

        return try await APIClient.fancyFetch(
            endpoint: "/hype",
            method: .POST,
            body: bodyData,
            responseType: HypeResponse.self
        )
    }

    /// Fetches the sender's current daily hype quota.
    static func status() async throws -> HypeStatusResponse {
        return try await APIClient.fancyFetch(
            endpoint: "/hype/status",
            responseType: HypeStatusResponse.self
        )
    }
}
```

- [ ] **Step 2: Add file to Xcode target**

Open the project in Xcode, right-click the `Services` group, "Add Files to Mile A Day…", select `HypeService.swift`, and ensure the **Mile A Day** target is checked. (Per `CLAUDE.md`, do NOT modify `project.pbxproj` directly.)

- [ ] **Step 3: Build**

In Xcode, ⌘B. Expected: clean build.

- [ ] **Step 4: Commit**

```bash
git add "app/Mile A Day/Services/HypeService.swift"
# project.pbxproj will be touched by Xcode adding the file - acceptable per existing patterns
git add app/Mile\ A\ Day.xcodeproj/project.pbxproj
git commit -m "Add HypeService for backend hype API"
```

---

### Task 9: Register `FRIEND_ACTIVITY` notification category

**Files:**
- Modify: `app/Mile A Day/Core/Services/MADNotificationService.swift`

- [ ] **Step 1: Add a category-registration helper**

In `MADNotificationService.swift`, add a new private method below `requestAuthorization()` (around line 63):

```swift
/// Registers all UNNotificationCategories the app handles.
/// Currently: FRIEND_ACTIVITY → 🔥 Hype action.
private func registerCategories() {
    let hypeAction = UNNotificationAction(
        identifier: "HYPE_ACTION",
        title: "🔥 Hype",
        options: []
    )
    let friendActivity = UNNotificationCategory(
        identifier: "FRIEND_ACTIVITY",
        actions: [hypeAction],
        intentIdentifiers: [],
        options: []
    )
    center.setNotificationCategories([friendActivity])
}
```

- [ ] **Step 2: Call it from `init`**

In the `private override init()` block (around line 36-48), add a call to `registerCategories()` after `center.delegate = self`:

```swift
private override init() {
    super.init()
    center.delegate = self
    registerCategories()

    if let lastDate = userDefaults.object(forKey: lastNotificationKey) as? Date {
        lastCompletionNotificationDate = lastDate
    }

    Task {
        await refreshAuthorizationStatus()
    }
}
```

- [ ] **Step 3: Build in Xcode**

⌘B. Expected: clean build.

- [ ] **Step 4: Commit**

```bash
git add "app/Mile A Day/Core/Services/MADNotificationService.swift"
git commit -m "Register FRIEND_ACTIVITY notification category with Hype action"
```

---

### Task 10: Handle `HYPE_ACTION` in the notification delegate

**Files:**
- Modify: `app/Mile A Day/Core/Services/MADNotificationService.swift` (the `didReceive response` method around line 395)

- [ ] **Step 1: Replace `didReceive response` body**

Replace the existing implementation:

```swift
func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
    let userInfo = response.notification.request.content.userInfo

    // Handle action-button taps before generic tap routing.
    if response.actionIdentifier == "HYPE_ACTION" {
        await handleHypeAction(userInfo: userInfo)
        return
    }

    guard let type = userInfo["type"] as? String else { return }
    let data = userInfo["data"] as? [String: String] ?? [:]

    pendingNotificationType = type

    NotificationCenter.default.post(
        name: .didTapPushNotification,
        object: nil,
        userInfo: ["type": type, "data": data]
    )
}

/// Handles the 🔥 Hype action button on a friend_activity push.
/// Runs in the background (app may be suspended); calls /hype and
/// shows a brief local notification with the result.
private func handleHypeAction(userInfo: [AnyHashable: Any]) async {
    // Pull target user_id from the data payload.
    let data = userInfo["data"] as? [String: String]
    guard let targetUserId = data?["user_id"], !targetUserId.isEmpty else {
        await postLocalToast(title: "Couldn't send hype", body: "Try opening the app.")
        return
    }

    do {
        let response = try await HypeService.sendHype(targetUserId: targetUserId)
        let remaining = response.hypes_remaining
        let body = remaining == 1
            ? "Hype sent! 1 left today."
            : "Hype sent! \(remaining) left today."
        await postLocalToast(title: "🔥 Hype sent", body: body)
    } catch let error as APIError where error.isRateLimited {
        await postLocalToast(title: "Out of hypes", body: "You're out of hypes for today.")
    } catch {
        await postLocalToast(title: "Couldn't send hype", body: "Try opening the app.")
    }
}

/// Schedules an immediate local notification used as a lightweight toast
/// from the action handler (when the app may be suspended).
private func postLocalToast(title: String, body: String) async {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = nil
    let request = UNNotificationRequest(
        identifier: "hype-toast-\(UUID().uuidString)",
        content: content,
        trigger: nil
    )
    do {
        try await center.add(request)
    } catch {
        print("[Hype] Failed to post toast: \(error.localizedDescription)")
    }
}
```

- [ ] **Step 2: Add a `rateLimited` case to `APIError` and route 429 to it**

Open `app/Mile A Day/Services/APIClient.swift`. The current `APIError` enum (around line 176) has cases `invalidURL, invalidResponse, notAuthenticated, unauthorized, badRequest(String), notFound, serverError(Int), tokenRefreshFailed`. There is no rate-limit case — currently a 429 falls through to `serverError(429)` via the `default` switch arm.

Add a `rateLimited(String)` case to the enum:

```swift
enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case notAuthenticated
    case unauthorized
    case badRequest(String)
    case rateLimited(String)
    case notFound
    case serverError(Int)
    case tokenRefreshFailed
    // ...keep any existing cases below this
```

Find the existing `errorDescription` switch in the enum and add a matching arm:

```swift
case .rateLimited(let message):
    return message
```

In `makeRequest` (around line 108-124), insert a `case 429` arm before the `default` arm:

```swift
case 429:
    if let errorData = try? JSONDecoder().decode([String: String].self, from: data),
       let errorMessage = errorData["error"] {
        throw APIError.rateLimited(errorMessage)
    }
    throw APIError.rateLimited("Rate limited")
```

Then add a helper at the bottom of the file (outside the class):

```swift
extension APIError {
    /// True for HTTP 429 responses.
    var isRateLimited: Bool {
        if case .rateLimited = self { return true }
        return false
    }
}
```

- [ ] **Step 3: Build in Xcode**

⌘B. Expected: clean build. Fix any naming mismatches between `APIError`'s actual cases and the helper.

- [ ] **Step 4: Commit**

```bash
git add "app/Mile A Day/Core/Services/MADNotificationService.swift" "app/Mile A Day/Services/APIClient.swift"
git commit -m "Handle HYPE_ACTION by calling /hype and showing local toast"
```

---

### Task 11: iOS manual verification on physical device

**Files:** none (verification only)

- [ ] **Step 1: Build & install on a physical device**

Notification action buttons require a real device. Connect an iPhone, select it as the run destination, ⌘R from Xcode.

- [ ] **Step 2: Sign in as Alice**

Use a test account that has at least one friend (Bob) who has completed a mile today (or trigger a test workout sync from another device).

- [ ] **Step 3: Trigger a `friend_activity` push**

From the backend dev environment (or staging), have Bob's account upload a workout that crosses the 1-mile threshold. The runner's device receives the existing self-completion push; Alice's device should receive a `friend_activity` push titled `Bob got their mile in!`.

- [ ] **Step 4: Verify the action button is present**

On the lock screen, long-press (or pull down) the notification. Expected: the `🔥 Hype` action appears at the bottom.

- [ ] **Step 5: Tap `🔥 Hype` without opening the app**

Expected behavior:
- Backend `/hype` endpoint receives the call (verify in server logs).
- Bob's device receives a `🔥 You got hyped!` push within ~1-2 seconds.
- Alice's device shows a local toast: `Hype sent! 2 left today.` (silent, banner-style).

- [ ] **Step 6: Drain Alice's daily limit**

Trigger 3 more friend_activity pushes from valid hype targets (or directly POST to `/hype` 3× from another tool while Alice is logged in). Then trigger a 5th hype attempt via the action button.

Expected: Alice's local toast shows `Out of hypes — You're out of hypes for today.`

- [ ] **Step 7: Verify cold-launch path**

Force-quit the app. Trigger another friend_activity push. Tap `🔥 Hype` action. Expected: app remains backgrounded; backend still receives the request; toast appears.

- [ ] **Step 8: No commit** — verification only. Failures route back to relevant earlier tasks.

---

## Phase 3 — Cross-cutting cleanup

### Task 12: Update notification settings UI (if user-facing toggle exists)

**Files:**
- Possibly: `app/Mile A Day/Views/NotificationSettingsView.swift`

- [ ] **Step 1: Inspect the settings view**

Open `app/Mile A Day/Views/NotificationSettingsView.swift`. If there are Toggle rows for `flexes_enabled`, `nudges_enabled`, etc., add a parallel row for `hypes_enabled`.

- [ ] **Step 2: Add the row (if applicable)**

Match the existing pattern. Example:

```swift
Toggle("Hype reactions", isOn: $viewModel.hypesEnabled)
    .onChange(of: viewModel.hypesEnabled) { _, newValue in
        Task { await viewModel.savePreferences() }
    }
```

Update the corresponding view model and the encode/decode for the `/notifications/preferences` endpoint to include `hypes_enabled`.

- [ ] **Step 3: If no user-facing settings UI for these toggles exists**

Skip this task. The default `true` and the API surface from Task 2 are sufficient for v1.

- [ ] **Step 4: Build + commit (if changes were made)**

```bash
git add "app/Mile A Day/Views/NotificationSettingsView.swift" /* + view model file */
git commit -m "Add Hype reactions toggle to notification settings"
```

---

## Done

After all tasks complete:

- [ ] Run `cd backend && npm run build` once more — clean.
- [ ] Run a final iOS build on device — clean.
- [ ] Hand off to `superpowers:finishing-a-development-branch` for merge/PR decision.

The branch will be ready to merge to `main`.
