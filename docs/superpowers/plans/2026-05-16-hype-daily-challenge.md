# Hype-able Daily Challenge Completions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `friend_challenge_completed` notifications hype-able by adding a new `challenge` hype context type.

**Architecture:** Mirror the existing `mile` hype-context pattern. The backend gains a `challenge` context type with per-completion dedup (`context_id = "<friendId>:<localDate>"`) and validation against the `user_challenge_completions` table; the iOS inbox derives a hype affordance for `friend_challenge_completed` rows. No DB migration — `hype_log.context_type` is free-text.

**Tech Stack:** TypeScript / Express 5 / PostgreSQL (`backend/`), Swift / SwiftUI (`app/`).

**Working directory:** All code paths are relative to the worktree root `/Users/david/dev/Mile-A-Day/.claude/worktrees/hype-daily-goal/`.

**Note on testing:** The backend has no test runner (see `CLAUDE.md`). Backend verification is `cd backend && npm run build` (TypeScript compile = typecheck). iOS verification is a build in Xcode, done by the user — the agent must not run `xcodebuild`.

---

### Task 1: Export a challenge-completion lookup helper

Adds an exported helper so the hype controller can verify a friend completed a challenge on a given date.

**Files:**
- Modify: `backend/src/services/dailyChallengeService.ts`

- [ ] **Step 1: Add the `hasChallengeCompletion` export**

Insert this function in `backend/src/services/dailyChallengeService.ts` in the `// ─── Helpers ───` section, immediately after the existing private `getCompletionRow` function (ends near line 560):

```typescript
/**
 * True if the user has a recorded daily-challenge completion for the given
 * local date. Used to validate `challenge`-context hypes.
 */
export async function hasChallengeCompletion(userId: string, localDate: string): Promise<boolean> {
  const rows = await db.query<{ exists: boolean }>(
    `SELECT EXISTS (
      SELECT 1 FROM user_challenge_completions WHERE user_id = $1 AND local_date = $2
    ) AS exists`,
    [userId, localDate],
  );
  return rows[0]?.exists === true;
}
```

- [ ] **Step 2: Verify the backend compiles**

Run: `cd backend && npm run build`
Expected: exits 0, no TypeScript errors.

- [ ] **Step 3: Commit**

```bash
git add backend/src/services/dailyChallengeService.ts
git commit -m "feat: add hasChallengeCompletion lookup helper"
```

---

### Task 2: Add the `challenge` context type to the hype service and controller

Widens the `HypeContext` type, whitelists the new context, adds the hype-back message, and validates challenge completion.

**Files:**
- Modify: `backend/src/services/hypeService.ts:33-37`
- Modify: `backend/src/controllers/hypeController.ts`

- [ ] **Step 1: Widen the `HypeContext.contextType` union**

In `backend/src/services/hypeService.ts`, change the `HypeContext` interface (currently lines 33-37):

```typescript
export interface HypeContext {
	contextType: 'mile' | 'badge' | 'pr' | 'challenge';
	contextId: string;
	contextLabel: string;
}
```

- [ ] **Step 2: Import the completion helper in the controller**

In `backend/src/controllers/hypeController.ts`, change the workoutService import line (currently line 5) so the file also imports the new helper. Add this import after it (after line 8's `shouldSendNotification` import is fine too — place it with the other service imports):

```typescript
import { hasChallengeCompletion } from '../services/dailyChallengeService.js';
```

- [ ] **Step 3: Whitelist the `challenge` context type**

In `backend/src/controllers/hypeController.ts`, find the validation block (currently line 109):

```typescript
			if (!['mile', 'badge', 'pr'].includes(rawContextType)) {
					return res.status(400).json({
						error: "context_type must be one of 'mile' | 'badge' | 'pr'"
					});
				}
```

Replace it with:

```typescript
			if (!['mile', 'badge', 'pr', 'challenge'].includes(rawContextType)) {
					return res.status(400).json({
						error: "context_type must be one of 'mile' | 'badge' | 'pr' | 'challenge'"
					});
				}
```

- [ ] **Step 4: Add the `challenge` hype-back message**

In `backend/src/controllers/hypeController.ts`, find the `buildHypeBackBody` switch (currently lines 74-81). Add a `case 'challenge'` after the `pr` case:

```typescript
	switch (context.contextType) {
		case 'mile':
			return `${senderName} hyped your daily mile 🔥`;
		case 'badge':
			return `${senderName} hyped you earning '${context.contextLabel}' 🔥`;
		case 'pr':
			return `${senderName} hyped your new ${context.contextLabel} 🔥`;
		case 'challenge':
			return `${senderName} hyped your '${context.contextLabel}' challenge 🔥`;
	}
```

- [ ] **Step 5: Add challenge-completion validation**

In `backend/src/controllers/hypeController.ts`, find the validation chain that ends the `mile` branch (currently lines 138-147):

```typescript
		} else if (context.contextType === 'mile') {
				const dateMatch = context.contextId.match(/:(\d{4}-\d{2}-\d{2})$/);
				if (!dateMatch) {
					return res.status(400).json({ error: 'Invalid mile context_id; expected "<userId>:YYYY-MM-DD"' });
				}
				const milesOnDate = await getMilesOnLocalDate(targetUserId, dateMatch[1]);
				if (milesOnDate < 1.0) {
					return res.status(400).json({ error: "This user didn't complete a mile that day" });
				}
			}
```

Add a `challenge` branch immediately after that closing `}` (before the dedupe pre-check comment):

```typescript
		} else if (context.contextType === 'challenge') {
				const dateMatch = context.contextId.match(/:(\d{4}-\d{2}-\d{2})$/);
				if (!dateMatch) {
					return res.status(400).json({ error: 'Invalid challenge context_id; expected "<userId>:YYYY-MM-DD"' });
				}
				const completed = await hasChallengeCompletion(targetUserId, dateMatch[1]);
				if (!completed) {
					return res.status(400).json({ error: "This user didn't complete a challenge that day" });
				}
			}
```

- [ ] **Step 6: Verify the backend compiles**

Run: `cd backend && npm run build`
Expected: exits 0, no TypeScript errors. (If the `buildHypeBackBody` switch errors as non-exhaustive, the `case 'challenge'` from Step 4 is missing — add it.)

- [ ] **Step 7: Commit**

```bash
git add backend/src/services/hypeService.ts backend/src/controllers/hypeController.ts
git commit -m "feat: accept and validate the challenge hype context type"
```

---

### Task 3: Derive a hype context for `friend_challenge_completed` notifications

Makes `GET /in-app-notifications` return hype affordance fields for challenge-completion rows.

**Files:**
- Modify: `backend/src/controllers/inAppNotificationController.ts:6-11` and `:64-78`

- [ ] **Step 1: Widen the `HypeDerivation` interface**

In `backend/src/controllers/inAppNotificationController.ts`, change the `HypeDerivation` interface (currently lines 6-11):

```typescript
interface HypeDerivation {
	hype_target_user_id: string | null;
	hype_context_type: 'mile' | 'badge' | 'pr' | 'challenge' | null;
	hype_context_id: string | null;
	hype_context_label: string | null;
}
```

- [ ] **Step 2: Add the `friend_challenge_completed` derivation branch**

In `backend/src/controllers/inAppNotificationController.ts`, find the `friend_personal_best` branch inside `deriveHypeContext` (currently lines 64-76, ending with `}`). Add this branch immediately after it, before the final `return empty;`:

```typescript
	if (row.type === 'friend_challenge_completed') {
		const targetId = data.sender_id;
		const localDate = data.local_date;
		if (!targetId || !localDate) return empty;
		// challenge_title was added to the push payload; older rows fall back to
		// the notification body, which is the challenge title verbatim.
		const label = data.challenge_title || row.body || "today's challenge";
		return {
			hype_target_user_id: String(targetId),
			hype_context_type: 'challenge',
			hype_context_id: `${targetId}:${localDate}`,
			hype_context_label: String(label)
		};
	}
```

- [ ] **Step 3: Verify the backend compiles**

Run: `cd backend && npm run build`
Expected: exits 0, no TypeScript errors.

- [ ] **Step 4: Commit**

```bash
git add backend/src/controllers/inAppNotificationController.ts
git commit -m "feat: derive challenge hype context for in-app notifications"
```

---

### Task 4: Include the challenge title in the push payload

Adds `challenge_title` to the `friend_challenge_completed` push `data` so the hype label is reliable for new notifications.

**Files:**
- Modify: `backend/src/services/pushNotificationService.ts:713-724`

- [ ] **Step 1: Add `challenge_title` to the push data**

In `backend/src/services/pushNotificationService.ts`, find the `sendPush` call inside `fanOutFriendChallengePush` (currently lines 714-723). Update its `data` object:

```typescript
		sendPush(friendId, {
				title: `${sender} finished today's challenge`,
				body: completion.challengeTitle,
				type: 'friend_challenge_completed',
				data: {
					sender_id: senderId,
					challenge_key: completion.challengeKey,
					challenge_title: completion.challengeTitle,
					local_date: completion.localDate
				}
			}).catch(err => console.error('[Push] friend_challenge_completed send failed:', err.message));
```

- [ ] **Step 2: Verify the backend compiles**

Run: `cd backend && npm run build`
Expected: exits 0, no TypeScript errors.

- [ ] **Step 3: Commit**

```bash
git add backend/src/services/pushNotificationService.ts
git commit -m "feat: include challenge_title in friend_challenge_completed push"
```

---

### Task 5: Show the hype button on challenge notifications in the iOS inbox

Adds the `friend_challenge_completed` case to the inbox's hype-affordance derivation.

**Files:**
- Modify: `app/Mile A Day/Views/NotificationInboxView.swift` — `hypeAffordance(for:)` (~line 123) and `hypeTargetUserId(for:)` (~line 167)
- Modify: `app/Mile A Day/Services/HypeService.swift:17-20`

- [ ] **Step 1: Add the `friend_challenge_completed` case to `hypeAffordance`**

In `app/Mile A Day/Views/NotificationInboxView.swift`, in `hypeAffordance(for:)`, add this case immediately after the `friend_personal_best` case and before `default:`:

```swift
        case "friend_challenge_completed":
            guard let targetId = data["sender_id"] else { return nil }
            // local_date is in the payload; fall back to the row's creation date.
            let localDate = data["local_date"] ?? String(notification.created_at.prefix(10))
            return HypeContext(
                contextType: "challenge",
                contextId: "\(targetId):\(localDate)",
                contextLabel: data["challenge_title"] ?? notification.body
            )
```

- [ ] **Step 2: Add the `friend_challenge_completed` case to `hypeTargetUserId`**

In the same file, in `hypeTargetUserId(for:)`, change the badge/pr case line (currently `case "friend_badge_earned", "friend_personal_best":`) to include the new type:

```swift
        case "friend_badge_earned", "friend_personal_best", "friend_challenge_completed":
            return data["sender_id"]
```

- [ ] **Step 3: Update the `HypeContext` doc comment**

In `app/Mile A Day/Services/HypeService.swift`, change the `contextType` comment (currently line 17):

```swift
    let contextType: String   // "mile" | "badge" | "pr" | "challenge"
```

- [ ] **Step 4: iOS build verification (user)**

Ask the user to build the "Mile A Day" target in Xcode and confirm it compiles. The agent must not run `xcodebuild`.

- [ ] **Step 5: Commit**

```bash
git add "app/Mile A Day/Views/NotificationInboxView.swift" "app/Mile A Day/Services/HypeService.swift"
git commit -m "feat: hype button on daily challenge completion notifications"
```

---

### Task 6: End-to-end verification

Confirms the full flow works against a running backend.

**Files:** none (verification only).

- [ ] **Step 1: Start the backend**

Run: `cd backend && npm run dev`
Expected: server starts with no errors.

- [ ] **Step 2: Verify the in-app notifications endpoint returns challenge hype fields**

With a test account that has received a `friend_challenge_completed` notification, call `GET /in-app-notifications` (authenticated). Confirm the challenge row has `hype_context_type: "challenge"`, a `hype_context_id` of the form `"<id>:<date>"`, a non-empty `hype_context_label`, and `is_hyped: false`.

If no such notification exists, trigger one: have a friended test user complete that day's daily challenge (upload a qualifying workout), which fans out a `friend_challenge_completed` push.

- [ ] **Step 3: Verify a challenge hype succeeds**

`POST /hype` (authenticated) with body:

```json
{
  "target_user_id": "<friendId>",
  "context_type": "challenge",
  "context_id": "<friendId>:<localDate>",
  "context_label": "Double Down"
}
```

Expected: `200` with `{ "message": "Hype sent", "hypes_remaining": <n> }`.

- [ ] **Step 4: Verify dedup**

Repeat the exact `POST /hype` from Step 3.
Expected: `409` with `{ "error": "already_hyped" }`.

- [ ] **Step 5: Verify validation rejects an uncompleted challenge**

`POST /hype` with a `context_id` whose date the target did not complete a challenge on (e.g. a far-past date).
Expected: `400` with `{ "error": "This user didn't complete a challenge that day" }`.

- [ ] **Step 6: No commit** — verification only.

---

## Self-Review

**Spec coverage:**
- New `challenge` context type → Task 2 Step 1 (type), Task 2 Step 3 (whitelist).
- context_id `"<friendId>:<localDate>"` → Task 2 Step 5, Task 3 Step 2, Task 5 Step 1.
- No DB migration → confirmed; no task touches schema.
- `buildHypeBackBody` case → Task 2 Step 4.
- Challenge-completion validation + `hasChallengeCompletion` helper → Task 1, Task 2 Steps 2 & 5.
- `deriveHypeContext` branch + `HypeDerivation` widening → Task 3.
- `challenge_title` in push payload → Task 4.
- iOS `hypeAffordance` / `hypeTargetUserId` → Task 5 Steps 1-2.
- iOS `HypeService` comment → Task 5 Step 3.
- Edge cases (older rows, dedup, validation failure) → Task 6 Steps 4-5; older-row label fallback in Task 3 Step 2 and Task 5 Step 1.

**Placeholder scan:** none found — every step has concrete code or commands.

**Type consistency:** `hasChallengeCompletion(userId, localDate)` defined in Task 1, imported and called in Task 2. `HypeContext.contextType` union widened in Task 2 Step 1; `HypeDerivation.hype_context_type` widened in Task 3 Step 1. `challenge_title` written in Task 4, read in Task 3 Step 2 and Task 5 Step 1. Consistent throughout.
