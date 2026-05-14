# Hype From the Notification Inbox — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users hype friends from the in-app notification inbox (not just the push banner), make the hype-back notification contextual, and build out friend personal-best notifications so PRs are also hype-able.

**Architecture:** Extend the existing `hype_log` table with optional context columns. Add a new `friend_personal_best` notification type powered by pre-vs-post-workout aggregate comparison inside the workout upload flow (no new tables). Server enriches each inbox row with the data the iOS client needs to decide whether to render a hype button, who to hype, and whether the row is already hyped. iOS adds a button, a context-aware `HypeService` overload, and a settings toggle.

**Tech Stack:** TypeScript / Express 5.1 / PostgreSQL (raw SQL, no ORM) on the backend. Swift / SwiftUI / Observation on iOS. No automated test runner — verification via `npm run build`, manual curl, and physical-device testing.

**Spec:** `docs/superpowers/specs/2026-05-14-hype-from-inbox-design.md`

---

## File map

**Backend — modify:**
- `backend/src/db/notification_tables.sql` — append two `ALTER TABLE` blocks (additive; safe to re-run)
- `backend/src/services/hypeService.ts` — extend `logHypeIfUnderLimit`, add `findExistingHype`
- `backend/src/services/pushNotificationService.ts` — add `'friend_personal_best'` to type union, add `fanOutFriendPersonalBestPush`, add `badge_name` to badge fan-out, type union for new types
- `backend/src/services/notificationSettingsService.ts` — add `friend_personal_best_enabled` setting key
- `backend/src/services/notificationService.ts` — add `kind` discriminator to `friend_activity` data payloads
- `backend/src/services/workoutService.ts` — add `computePersonalRecords(userId, excludeWorkoutIds?)` helper
- `backend/src/controllers/workoutController.ts` — call PR detection after upload commit, fire fan-out
- `backend/src/controllers/hypeController.ts` — accept context fields, 409 dedupe, contextual hype-back wording
- `backend/src/controllers/inAppNotificationController.ts` — enrich inbox rows with hype fields

**iOS — modify:**
- `app/Mile A Day/Models/Competition.swift` — add hype fields to `InAppNotification`
- `app/Mile A Day/Services/HypeService.swift` — add context overload, surface 409
- `app/Mile A Day/Views/NotificationInboxView.swift` — render hype button + tap handler
- `app/Mile A Day/Views/Settings/...` — find existing friend-activity toggle row, add a sibling for friend-PR

**Spec doc:** already at `docs/superpowers/specs/2026-05-14-hype-from-inbox-design.md`.

---

## Verification notes

Backend has no test runner. After every backend task: `cd backend && npm run build` to type-check. Manual API tests use `curl` against `npm run dev` on localhost:8080. iOS verification is done by building in Xcode and walking through the manual test scenarios in Task 22.

CLAUDE.md rule: confirm with user before applying DB migrations. Task 3 is a checkpoint.

---

## Task 1: SQL — extend `hype_log` with context columns

**Files:**
- Modify: `backend/src/db/notification_tables.sql` (append new block at end of file)

- [ ] **Step 1: Add the migration block**

Append to `backend/src/db/notification_tables.sql`:

```sql
-- ─── Hype context (2026-05-14) ───────────────────────────────────────
-- Optional context describing what was hyped (mile / badge / pr).
-- Legacy push-action hypes keep these columns NULL and skip dedupe.
ALTER TABLE hype_log ADD COLUMN IF NOT EXISTS context_type TEXT;
ALTER TABLE hype_log ADD COLUMN IF NOT EXISTS context_id TEXT;
ALTER TABLE hype_log ADD COLUMN IF NOT EXISTS context_label TEXT;

-- Partial unique index: one hype per (sender, target, context_type, context_id)
-- when context is present. Legacy NULL-context hypes can repeat (matches today).
CREATE UNIQUE INDEX IF NOT EXISTS hype_log_context_dedupe_idx
    ON hype_log (sender_id, target_id, context_type, context_id)
    WHERE context_id IS NOT NULL;
```

- [ ] **Step 2: Type-check still compiles**

```bash
cd backend && npm run build
```

Expected: no errors (this file isn't imported by TS so it's a sanity check that nothing else broke).

- [ ] **Step 3: Commit**

```bash
git add backend/src/db/notification_tables.sql
git commit -m "Add hype_log context columns + dedupe index"
```

---

## Task 2: SQL — extend `notification_settings` with friend PR toggle

**Files:**
- Modify: `backend/src/db/notification_tables.sql` (append after Task 1 block)

- [ ] **Step 1: Append the migration**

Append to `backend/src/db/notification_tables.sql`:

```sql
-- ─── Friend personal-best notifications (2026-05-14) ─────────────────
ALTER TABLE notification_settings
    ADD COLUMN IF NOT EXISTS friend_personal_best_enabled BOOLEAN DEFAULT TRUE;

UPDATE notification_settings
    SET friend_personal_best_enabled = COALESCE(friend_personal_best_enabled, TRUE);
```

- [ ] **Step 2: Type-check**

```bash
cd backend && npm run build
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add backend/src/db/notification_tables.sql
git commit -m "Add friend_personal_best_enabled to notification_settings"
```

---

## Task 3: CHECKPOINT — apply migrations against the database

**No file changes — pure operations checkpoint.**

- [ ] **Step 1: Ask the user before applying**

Print the two `ALTER TABLE` / `CREATE INDEX` statements from Tasks 1 and 2. Ask: "Ready to apply these migrations against the database? (CLAUDE.md says I should confirm before DDL.)"

- [ ] **Step 2: After approval, apply via the `db-query` skill or `psql`**

Run each statement in sequence against `$DATABASE_URL`. The `IF NOT EXISTS` guards make them safe to re-run.

- [ ] **Step 3: Verify columns landed**

```bash
psql "$DATABASE_URL" -c "\d hype_log"
psql "$DATABASE_URL" -c "\d notification_settings"
```

Expected: `context_type`, `context_id`, `context_label` on `hype_log`; `friend_personal_best_enabled` on `notification_settings`.

- [ ] **Step 4: No commit needed (no file changes).**

---

## Task 4: Add `'friend_personal_best'` to the notification type union

**Files:**
- Modify: `backend/src/services/pushNotificationService.ts` around line 82 (`NotificationType` union)

- [ ] **Step 1: Add the new type to the union**

Find the existing `NotificationType` union (currently includes `'personal_best'`, `'friend_activity'`, `'friend_badge_earned'`, etc.). Add `'friend_personal_best'` to the list:

```typescript
type NotificationType =
    | 'mile_completed'
    | 'streak_milestone'
    | 'nudge_received'
    | 'flex_received'
    | 'hype_received'
    | 'friend_activity'
    | 'streak_broken'
    | 'competition_invite'
    | 'competition_accepted'
    | 'competition_started'
    | 'competition_finished'
    | 'competition_updates'
    | 'competition_milestone'
    | 'personal_best'
    | 'friend_personal_best'   // NEW
    | 'badge_earned'
    | 'friend_badge_earned'
    | 'challenge_completed'
    | 'friend_challenge_completed';
```

(Use the exact existing list — only add the one line. If the list differs from the above, just add the new entry alongside the others.)

- [ ] **Step 2: Type-check**

```bash
cd backend && npm run build
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add backend/src/services/pushNotificationService.ts
git commit -m "Add friend_personal_best to NotificationType union"
```

---

## Task 5: Add `friend_personal_best` plumbing to notification settings service

**Files:**
- Modify: `backend/src/services/notificationSettingsService.ts`

- [ ] **Step 1: Update the settings shape and defaults**

Locate the `NotificationSettings` interface and the default object (around lines 11–25 with `friend_activity_enabled: boolean` etc.). Add `friend_personal_best_enabled` everywhere `friend_activity_enabled` appears:

```typescript
export interface NotificationSettings {
    // ...existing fields...
    friend_activity_enabled: boolean;
    friend_personal_best_enabled: boolean;   // NEW
    // ...
}

const DEFAULTS: NotificationSettings = {
    // ...existing...
    friend_activity_enabled: true,
    friend_personal_best_enabled: true,      // NEW
    // ...
};
```

In the row-mapping function (around line 46), add:
```typescript
friend_personal_best_enabled: row.friend_personal_best_enabled ?? true,
```

In the upsert key-value array (around line 70):
```typescript
{ key: 'friend_personal_best_enabled', value: prefs.friend_personal_best_enabled },
```

- [ ] **Step 2: Extend the notification-type-to-settings-key mapping**

Find the mapping object (around line 205 — `friend_activity: 'friend_activity_enabled'`). Add:
```typescript
friend_personal_best: 'friend_personal_best_enabled',
```

- [ ] **Step 3: Extend the union of notification types accepted by `shouldSendNotification`**

Around line 267 (`notificationType: 'nudge' | 'flex' | 'hype' | 'friend_activity' | ...`). Add `'friend_personal_best'` to that union.

- [ ] **Step 4: Add the case in the `switch` that checks per-type prefs**

Around line 282 (`case 'friend_activity':`). Add a parallel case:
```typescript
case 'friend_personal_best':
    if (!prefs.friend_personal_best_enabled) return false;
    break;
```

And in the friend-specific muting block (around line 307 — `if (notificationType === 'friend_activity' && fs.activity_muted)`), extend the condition so friend PRs respect the same per-friend activity mute:
```typescript
if ((notificationType === 'friend_activity' || notificationType === 'friend_personal_best') && fs.activity_muted) return false;
```

- [ ] **Step 5: Type-check**

```bash
cd backend && npm run build
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add backend/src/services/notificationSettingsService.ts
git commit -m "Plumb friend_personal_best through notification settings"
```

---

## Task 6: Add `computePersonalRecords` helper to workoutService

**Files:**
- Modify: `backend/src/services/workoutService.ts` (append at end of file)

- [ ] **Step 1: Append the helper**

Add to the end of `backend/src/services/workoutService.ts`:

```typescript
/**
 * Returns the user's two tracked personal records computed from workouts,
 * optionally excluding a set of workout IDs (used to compute the "pre-upload"
 * baseline so the caller can detect a PR set by this upload).
 *
 * - fastestSplitPaceSecMi: MIN(split_pace) across qualifying splits (>=0.95mi, >0 pace).
 *   0 if the user has no qualifying splits.
 * - mostMilesInOneDay: MAX(SUM(distance) GROUP BY local_date). 0 if no workouts.
 */
export async function computePersonalRecords(
    userId: string,
    excludeWorkoutIds: string[] = []
): Promise<{ fastestSplitPaceSecMi: number; mostMilesInOneDay: number }> {
    const db = PostgresService.getInstance();
    const exclude = excludeWorkoutIds.length > 0;

    const paceQuery = exclude
        ? `SELECT MIN(s.split_pace)::text AS min_pace
           FROM workout_splits s
           JOIN workouts w ON w.workout_id = s.workout_id
           WHERE w.user_id = $1
               AND s.split_pace > 0
               AND s.split_distance >= 0.95
               AND NOT (w.workout_id = ANY($2::text[]))`
        : `SELECT MIN(s.split_pace)::text AS min_pace
           FROM workout_splits s
           JOIN workouts w ON w.workout_id = s.workout_id
           WHERE w.user_id = $1 AND s.split_pace > 0 AND s.split_distance >= 0.95`;

    const dayQuery = exclude
        ? `SELECT COALESCE(MAX(day_total), 0)::text AS best_day FROM (
                SELECT SUM(distance) AS day_total FROM workouts
                WHERE user_id = $1 AND NOT (workout_id = ANY($2::text[]))
                GROUP BY local_date
            ) t`
        : `SELECT COALESCE(MAX(day_total), 0)::text AS best_day FROM (
                SELECT SUM(distance) AS day_total FROM workouts
                WHERE user_id = $1 GROUP BY local_date
            ) t`;

    const params: any[] = exclude ? [userId, excludeWorkoutIds] : [userId];

    const [paceRow, bestDayRow] = await Promise.all([
        db.query<{ min_pace: string | null }>(paceQuery, params),
        db.query<{ best_day: string | null }>(dayQuery, params)
    ]);

    const fastestSplitPaceSecMi = paceRow[0]?.min_pace ? parseFloat(paceRow[0].min_pace) : 0;
    const mostMilesInOneDay = parseFloat(bestDayRow[0]?.best_day ?? '0') || 0;
    return { fastestSplitPaceSecMi, mostMilesInOneDay };
}
```

- [ ] **Step 2: Type-check**

```bash
cd backend && npm run build
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add backend/src/services/workoutService.ts
git commit -m "Add computePersonalRecords helper"
```

---

## Task 7: Implement `fanOutFriendPersonalBestPush`

**Files:**
- Modify: `backend/src/services/pushNotificationService.ts` (add new exported function near `fanOutFriendBadgePush`, around line 526)

- [ ] **Step 1: Add the formatter helper**

Above the new function, add a private helper to format the body text:

```typescript
function formatPersonalBestBody(prType: 'fastest_mile' | 'most_miles_day', newValue: number): string {
    if (prType === 'fastest_mile') {
        // newValue is seconds per mile
        const totalSeconds = Math.round(newValue);
        const minutes = Math.floor(totalSeconds / 60);
        const seconds = totalSeconds % 60;
        const paceStr = `${minutes}:${seconds.toString().padStart(2, '0')}`;
        return `Fastest mile — ${paceStr} pace`;
    }
    // most_miles_day — newValue is miles
    const milesStr = newValue >= 10 ? newValue.toFixed(1) : newValue.toFixed(2);
    return `Most miles in a day — ${milesStr} mi`;
}

function personalBestLabel(prType: 'fastest_mile' | 'most_miles_day', newValue: number): string {
    if (prType === 'fastest_mile') {
        const totalSeconds = Math.round(newValue);
        const minutes = Math.floor(totalSeconds / 60);
        const seconds = totalSeconds % 60;
        return `fastest mile (${minutes}:${seconds.toString().padStart(2, '0')})`;
    }
    const milesStr = newValue >= 10 ? newValue.toFixed(1) : newValue.toFixed(2);
    return `most miles in a day (${milesStr} mi)`;
}
```

- [ ] **Step 2: Add the fan-out function**

Below `fanOutFriendBadgePush` (around line 547), add:

```typescript
/**
 * Fan out a personal-best to every accepted friend. No throttle — each PR
 * dimension is its own event, and a single workout breaking both PRs should
 * produce two distinct inbox rows so the viewer can hype each independently.
 */
export async function fanOutFriendPersonalBestPush(
    senderId: string,
    prType: 'fastest_mile' | 'most_miles_day',
    newValue: number,
    workoutId: string
): Promise<void> {
    const friendIds = await getAcceptedFriendIds(senderId);
    if (friendIds.length === 0) return;
    const sender = await getSenderDisplayName(senderId);

    const title = `${sender} set a new personal best`;
    const body = formatPersonalBestBody(prType, newValue);
    const label = personalBestLabel(prType, newValue);

    for (const friendId of friendIds) {
        const shouldSend = await shouldSendNotification(friendId, senderId, 'friend_personal_best');
        if (!shouldSend) continue;

        sendPush(friendId, {
            title,
            body,
            type: 'friend_personal_best',
            data: {
                sender_id: senderId,
                pr_type: prType,
                pr_label: label,
                new_value: newValue,
                workout_id: workoutId
            }
        }).catch(err => console.error('[Push] friend_personal_best send failed:', err.message));
    }
}
```

- [ ] **Step 3: Add the `shouldSendNotification` import if missing**

Check the top of the file — if `shouldSendNotification` is not already imported from `./notificationSettingsService.js`, add the import.

- [ ] **Step 4: Type-check**

```bash
cd backend && npm run build
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add backend/src/services/pushNotificationService.ts
git commit -m "Add fanOutFriendPersonalBestPush"
```

---

## Task 8: Wire PR detection into the workout upload flow

**Files:**
- Modify: `backend/src/controllers/workoutController.ts` (around line 75, in the post-commit reward section)

- [ ] **Step 1: Read the existing post-commit block**

Open `backend/src/controllers/workoutController.ts`. Around line 46 is the start of the "evaluate badges + daily challenges AFTER the upload transaction committed" block, and line 75 has the `for (const badge of rewards.newlyEarnedBadges)` loop with `fireBadgeEarnedPush` and `fanOutFriendBadgePush`.

- [ ] **Step 2: Add imports**

At the top of the file, add (if not already present):

```typescript
import { computePersonalRecords } from '../services/workoutService.js';
import { fanOutFriendPersonalBestPush } from '../services/pushNotificationService.js';
```

(The existing `fireBadgeEarnedPush, fanOutFriendBadgePush, fanOutFriendChallengePush` import line is already there — just extend it.)

- [ ] **Step 3: Detect and fan out PRs**

Find the variable holding the just-uploaded workout IDs (the call to `uploadWorkouts(userId, workouts)` returns them — likely `insertedWorkoutIds` or similar). Locate the line that fires `evaluateWorkoutRewards`. Add a PR-detection block alongside it (after the transaction commits, fire-and-forget like the badge pushes):

```typescript
// PR detection: compare pre-upload PRs (excluding this batch) to post-upload PRs.
// Fire one fan-out per dimension that improved. Don't block the response.
(async () => {
    try {
        const [pre, post] = await Promise.all([
            computePersonalRecords(userId, insertedWorkoutIds),
            computePersonalRecords(userId)
        ]);
        const lastWorkoutId = insertedWorkoutIds[insertedWorkoutIds.length - 1] ?? '';

        // Fastest mile: SMALLER pace is better. Pre-value of 0 means "no prior record".
        if (post.fastestSplitPaceSecMi > 0 && (pre.fastestSplitPaceSecMi === 0 || post.fastestSplitPaceSecMi < pre.fastestSplitPaceSecMi)) {
            fanOutFriendPersonalBestPush(userId, 'fastest_mile', post.fastestSplitPaceSecMi, lastWorkoutId)
                .catch(err => console.error('Error fanning out friend_personal_best (fastest_mile):', err.message));
        }
        // Most miles in a day: BIGGER is better.
        if (post.mostMilesInOneDay > pre.mostMilesInOneDay) {
            fanOutFriendPersonalBestPush(userId, 'most_miles_day', post.mostMilesInOneDay, lastWorkoutId)
                .catch(err => console.error('Error fanning out friend_personal_best (most_miles_day):', err.message));
        }
    } catch (err: any) {
        console.error('Error detecting personal bests:', err.message);
    }
})();
```

Place this block right after the badge/challenge fire-and-forget block.

⚠️ Confirm the actual variable name for the inserted workout IDs by reading the surrounding code — it might be `insertedWorkoutIds`, `newWorkoutIds`, `workoutIds`, or destructured from a return value. Use the existing name. If badges use `rewards.newlyEarnedBadges` and a `triggeringWorkoutId` is somewhere upstream, that path likely has the IDs already.

- [ ] **Step 4: Type-check**

```bash
cd backend && npm run build
```

Expected: no errors. If the variable name is wrong, the TS error will name it.

- [ ] **Step 5: Commit**

```bash
git add backend/src/controllers/workoutController.ts
git commit -m "Fire friend_personal_best fan-out on PR improvement"
```

---

## Task 9: Add `kind` discriminator to `friend_activity` push data

**Why:** `friend_activity` is used for both mile-completion (celebratory, hype-able) and streak-broken (sympathetic, NOT hype-able). The iOS inbox enricher needs to tell them apart.

**Files:**
- Modify: `backend/src/services/notificationService.ts` (two `friend_activity` sends around lines 82 and 375)

- [ ] **Step 1: Find and update the mile-completion fan-out**

Around line 82 of `notificationService.ts`:

```typescript
sendPush(recipientId, {
    title,
    body,
    type: 'friend_activity',
    category: 'FRIEND_ACTIVITY',
    data: { user_id: userId, kind: 'mile_completed' }   // add kind
}).catch(err => console.error('[Push] Error sending friend activity:', err.message));
```

- [ ] **Step 2: Find and update the streak-broken fan-out**

Around line 375:

```typescript
sendPush(friend_id, {
    title: 'Streak broken!',
    body: `${username}'s ${streakLength}-day streak just ended. Send them some encouragement!`,
    type: 'friend_activity',
    data: { user_id, kind: 'streak_broken' }   // add kind
}).catch(err => console.error('[Push] streak broken error:', err.message));
```

- [ ] **Step 3: Type-check**

```bash
cd backend && npm run build
```

- [ ] **Step 4: Commit**

```bash
git add backend/src/services/notificationService.ts
git commit -m "Tag friend_activity pushes with kind discriminator"
```

---

## Task 10: Add `badge_name` to `fanOutFriendBadgePush` data payload

**Files:**
- Modify: `backend/src/services/pushNotificationService.ts` (the `data` block of `fanOutFriendBadgePush`, around lines 538–544)

- [ ] **Step 1: Add `badge_name` to the data object**

Find `fanOutFriendBadgePush`. Update the `sendPush(...)` call's `data` block:

```typescript
data: {
    sender_id: senderId,
    badge_id: badge.badgeId,
    badge_name: badge.name,        // NEW — used by inbox hype context label
    rarity: badge.rarity
}
```

- [ ] **Step 2: Type-check**

```bash
cd backend && npm run build
```

- [ ] **Step 3: Commit**

```bash
git add backend/src/services/pushNotificationService.ts
git commit -m "Include badge_name in friend_badge_earned data"
```

---

## Task 11: Extend `hypeService.logHypeIfUnderLimit` to accept context columns

**Files:**
- Modify: `backend/src/services/hypeService.ts`

- [ ] **Step 1: Update the function signature and INSERT statement**

Replace the existing `logHypeIfUnderLimit` (lines 34–46) with:

```typescript
export interface HypeContext {
    contextType: 'mile' | 'badge' | 'pr';
    contextId: string;
    contextLabel: string;
}

/**
 * Atomically insert a hype_log row only if the sender is still under the
 * daily limit. Optional context describes what was hyped (mile/badge/pr) and
 * enables dedupe via the partial unique index on (sender, target, ctx_type, ctx_id).
 * Returns the new row's id, or null if the limit was reached.
 *
 * Caller is responsible for the dedupe pre-check (this function will throw if the
 * partial unique index rejects the insert; check via `findExistingHype` first).
 */
export async function logHypeIfUnderLimit(
    senderId: string,
    targetId: string,
    context?: HypeContext
): Promise<{ id: string } | null> {
    if (context) {
        const rows = await db.query<{ id: string }>(
            `INSERT INTO hype_log (sender_id, target_id, context_type, context_id, context_label)
            SELECT $1, $2, $3, $4, $5
            WHERE (
                SELECT COUNT(*) FROM hype_log
                WHERE sender_id = $1 AND created_at > NOW() - INTERVAL '24 hours'
            ) < ${HYPE_DAILY_LIMIT}
            RETURNING id`,
            [senderId, targetId, context.contextType, context.contextId, context.contextLabel]
        );
        return rows[0] ?? null;
    }
    const rows = await db.query<{ id: string }>(
        `INSERT INTO hype_log (sender_id, target_id)
        SELECT $1, $2
        WHERE (
            SELECT COUNT(*) FROM hype_log
            WHERE sender_id = $1 AND created_at > NOW() - INTERVAL '24 hours'
        ) < ${HYPE_DAILY_LIMIT}
        RETURNING id`,
        [senderId, targetId]
    );
    return rows[0] ?? null;
}
```

- [ ] **Step 2: Add a `findExistingHype` helper at the end of the file**

```typescript
/**
 * Returns true if the sender has already hyped this exact context.
 * Only meaningful when context is provided; legacy NULL-context hypes are not deduped.
 */
export async function hasHypedContext(
    senderId: string,
    targetId: string,
    contextType: string,
    contextId: string
): Promise<boolean> {
    const rows = await db.query<{ exists: boolean }>(
        `SELECT EXISTS (
            SELECT 1 FROM hype_log
            WHERE sender_id = $1 AND target_id = $2
                AND context_type = $3 AND context_id = $4
        ) AS exists`,
        [senderId, targetId, contextType, contextId]
    );
    return rows[0]?.exists === true;
}
```

- [ ] **Step 3: Type-check**

```bash
cd backend && npm run build
```

- [ ] **Step 4: Commit**

```bash
git add backend/src/services/hypeService.ts
git commit -m "Extend hype log with optional context columns"
```

---

## Task 12: Extend `hypeController.sendHype` to accept context + return 409 dup

**Files:**
- Modify: `backend/src/controllers/hypeController.ts`

- [ ] **Step 1: Update imports**

Replace the existing hype service import (lines 9–14) with:

```typescript
import {
    logHypeIfUnderLimit,
    getDailyHypeCount,
    getHypeResetsAt,
    hasHypedContext,
    HYPE_DAILY_LIMIT,
    HypeContext,
} from '../services/hypeService.js';
```

- [ ] **Step 2: Rewrite the `sendHype` controller**

Replace the existing `sendHype` (lines 50–106) with:

```typescript
export async function sendHype(req: AuthenticatedRequest, res: Response) {
    const senderId = req.userId!;
    const targetUserId = req.body?.target_user_id;
    const rawContextType = req.body?.context_type;
    const rawContextId = req.body?.context_id;
    const rawContextLabel = req.body?.context_label;

    try {
        if (!targetUserId || typeof targetUserId !== 'string') {
            return res.status(400).json({ error: 'target_user_id is required' });
        }
        if (senderId === targetUserId) {
            return res.status(400).json({ error: "You can't hype yourself" });
        }

        // Parse optional context. All three must be present together, or all absent.
        let context: HypeContext | undefined;
        const anyCtx = rawContextType || rawContextId || rawContextLabel;
        const allCtx = rawContextType && rawContextId && rawContextLabel;
        if (anyCtx && !allCtx) {
            return res.status(400).json({ error: 'context_type, context_id, and context_label must be provided together' });
        }
        if (allCtx) {
            if (!['mile', 'badge', 'pr'].includes(rawContextType)) {
                return res.status(400).json({ error: "context_type must be one of 'mile' | 'badge' | 'pr'" });
            }
            context = {
                contextType: rawContextType,
                contextId: String(rawContextId),
                contextLabel: String(rawContextLabel),
            };
        }

        const allowed = await isFriendOrCoParticipant(senderId, targetUserId);
        if (!allowed) {
            return res.status(403).json({
                error: 'You can only hype friends or people in your active competitions',
            });
        }

        const todayMiles = await getTodayMiles(targetUserId);
        if (todayMiles < 1.0) {
            return res.status(400).json({ error: "This user hasn't completed their mile today" });
        }

        // Context-aware dedupe pre-check (legacy no-context hypes skip this).
        if (context) {
            const alreadyHyped = await hasHypedContext(senderId, targetUserId, context.contextType, context.contextId);
            if (alreadyHyped) {
                return res.status(409).json({ error: 'already_hyped' });
            }
        }

        const inserted = await logHypeIfUnderLimit(senderId, targetUserId, context);
        if (!inserted) {
            return res.status(429).json({
                error: `You've used all ${HYPE_DAILY_LIMIT} hypes for the day`,
                hypes_remaining: 0,
                resets_at: await getHypeResetsAt(senderId),
            });
        }

        const countAfter = await getDailyHypeCount(senderId);

        const shouldSend = await shouldSendNotification(targetUserId, senderId, 'hype');
        if (shouldSend) {
            const sender = await getUser({ userId: senderId });
            const senderName = sender?.username ?? 'Someone';
            const body = buildHypeBackBody(senderName, context);
            await sendPush(targetUserId, {
                title: '🔥 You got hyped!',
                body,
                type: 'hype_received',
                data: {
                    user_id: senderId,
                    context_type: context?.contextType ?? null,
                    context_label: context?.contextLabel ?? null,
                },
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

function buildHypeBackBody(senderName: string, context: HypeContext | undefined): string {
    if (!context) {
        return `@${senderName} just hyped up your recent workout!`;
    }
    switch (context.contextType) {
        case 'mile':
            return `${senderName} hyped your daily mile 🔥`;
        case 'badge':
            return `${senderName} hyped you earning '${context.contextLabel}' 🔥`;
        case 'pr':
            return `${senderName} hyped your new ${context.contextLabel} 🔥`;
    }
}
```

- [ ] **Step 3: Type-check**

```bash
cd backend && npm run build
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add backend/src/controllers/hypeController.ts
git commit -m "Hype API: accept context, dedupe 409, contextual hype-back"
```

---

## Task 13: Enrich inbox rows with hype context fields

**Files:**
- Modify: `backend/src/controllers/inAppNotificationController.ts` (getInbox function around line 6)

- [ ] **Step 1: Read the existing `getInbox` to identify the row type**

Open the file. Around line 14 there's a SELECT FROM `in_app_notifications`. Note the destructured row shape so the enrichment matches.

- [ ] **Step 2: Add the enrichment helper at the bottom of the file**

```typescript
interface HypeFields {
    hype_target_user_id: string | null;
    hype_context_type: 'mile' | 'badge' | 'pr' | null;
    hype_context_id: string | null;
    hype_context_label: string | null;
    is_hyped: boolean;
}

/**
 * Derive hype context from a notification row's type + data. Returns null fields
 * for notification types that aren't hype-able.
 */
function deriveHypeContext(row: { type: string; data: Record<string, any> | null; created_at: Date | string }):
    Omit<HypeFields, 'is_hyped'> & { hype_target_user_id: string | null } {
    const data = row.data ?? {};
    const empty = {
        hype_target_user_id: null,
        hype_context_type: null,
        hype_context_id: null,
        hype_context_label: null,
    };

    if (row.type === 'friend_activity') {
        // Only celebrate the mile-completion variant. Streak-broken is sympathetic.
        if (data.kind !== 'mile_completed') return empty;
        const targetId = data.user_id;
        if (!targetId) return empty;
        // Use user_id:YYYY-MM-DD as the context id since the push payload doesn't
        // carry a workout_id and the user only finishes one mile per day from a hype POV.
        const localDate = new Date(row.created_at).toISOString().slice(0, 10);
        return {
            hype_target_user_id: targetId,
            hype_context_type: 'mile',
            hype_context_id: `${targetId}:${localDate}`,
            hype_context_label: "today's mile",
        };
    }

    if (row.type === 'friend_badge_earned') {
        const targetId = data.sender_id;
        const badgeId = data.badge_id;
        const badgeName = data.badge_name;
        if (!targetId || !badgeId) return empty;
        return {
            hype_target_user_id: targetId,
            hype_context_type: 'badge',
            hype_context_id: String(badgeId),
            hype_context_label: badgeName ? String(badgeName) : 'a medal',
        };
    }

    if (row.type === 'friend_personal_best') {
        const targetId = data.sender_id;
        const prType = data.pr_type;
        const workoutId = data.workout_id;
        const label = data.pr_label;
        if (!targetId || !prType || !workoutId) return empty;
        return {
            hype_target_user_id: targetId,
            hype_context_type: 'pr',
            hype_context_id: `${prType}:${workoutId}`,
            hype_context_label: label ? String(label) : 'personal best',
        };
    }

    return empty;
}
```

- [ ] **Step 3: Modify `getInbox` to compute hype fields per row**

After the existing `SELECT ... FROM in_app_notifications WHERE user_id = $1 ORDER BY ... LIMIT ... OFFSET ...` returns its rows, transform them. Add (replacing the existing return-shape construction):

```typescript
const rows = await db.query<any>(
    // ...existing query, unchanged...
    // (keep the existing SELECT)
);

// Pass 1: derive hype context for each row.
const derived = rows.map(r => ({
    row: r,
    hype: deriveHypeContext(r),
}));

// Pass 2: batch-query is_hyped for rows that have a context.
const ctxKeys = derived
    .filter(d => d.hype.hype_target_user_id && d.hype.hype_context_type && d.hype.hype_context_id)
    .map(d => ({
        targetId: d.hype.hype_target_user_id!,
        type: d.hype.hype_context_type!,
        id: d.hype.hype_context_id!,
    }));

const hypedSet = new Set<string>();
if (ctxKeys.length > 0) {
    const targetIds = ctxKeys.map(k => k.targetId);
    const types = ctxKeys.map(k => k.type);
    const ids = ctxKeys.map(k => k.id);
    const hyped = await db.query<{ target_id: string; context_type: string; context_id: string }>(
        `SELECT target_id, context_type, context_id
        FROM hype_log
        WHERE sender_id = $1
            AND (target_id, context_type, context_id) IN (
                SELECT * FROM UNNEST($2::text[], $3::text[], $4::text[])
            )`,
        [userId, targetIds, types, ids]
    );
    for (const h of hyped) {
        hypedSet.add(`${h.target_id}|${h.context_type}|${h.context_id}`);
    }
}

const notifications = derived.map(({ row, hype }) => {
    const isHyped =
        hype.hype_target_user_id &&
        hype.hype_context_type &&
        hype.hype_context_id &&
        hypedSet.has(`${hype.hype_target_user_id}|${hype.hype_context_type}|${hype.hype_context_id}`);
    return {
        id: row.id,
        title: row.title,
        body: row.body,
        type: row.type,
        data: row.data,
        is_read: row.is_read,
        created_at: row.created_at,
        hype_target_user_id: hype.hype_target_user_id,
        hype_context_type: hype.hype_context_type,
        hype_context_id: hype.hype_context_id,
        hype_context_label: hype.hype_context_label,
        is_hyped: Boolean(isHyped),
    };
});
```

Replace the existing `res.status(200).json({ notifications, unread_count })` shape so `notifications` is `derived.map(...)` (the enriched array). Keep the `unread_count` calculation as-is.

⚠️ Read the actual code first — the existing var name for the rows array may be `notifications` rather than `rows`. Use whatever it is. The transformation logic is the only thing that matters.

- [ ] **Step 4: Type-check**

```bash
cd backend && npm run build
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add backend/src/controllers/inAppNotificationController.ts
git commit -m "Enrich inbox rows with hype context + is_hyped"
```

---

## Task 14: Manual API smoke test (backend complete checkpoint)

**No file changes.** Verifies the backend chunk is wired up before iOS work begins.

- [ ] **Step 1: Start the dev server**

```bash
cd backend && npm run dev
```

Leave it running.

- [ ] **Step 2: Hit the inbox endpoint with a real token**

(Use a known user token — the user can supply via prompt if needed.)

```bash
curl -s http://localhost:8080/notifications/inbox?limit=20 \
    -H "Authorization: Bearer $TOKEN" | jq '.notifications[] | {type, hype_target_user_id, hype_context_type, hype_context_id, hype_context_label, is_hyped}'
```

Expected: every row has the five new fields. Mile-completion `friend_activity` rows have non-null hype fields; streak-broken `friend_activity` and unrelated types have nulls.

- [ ] **Step 3: Send a context hype**

Pick a friend_activity row's hype_target_user_id, hype_context_type, hype_context_id, hype_context_label:

```bash
curl -X POST http://localhost:8080/hype \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "target_user_id": "<id-from-row>",
        "context_type": "mile",
        "context_id": "<from-row>",
        "context_label": "today'\''s mile"
    }'
```

Expected: `200 { message: "Hype sent", hypes_remaining: N }`.

- [ ] **Step 4: Repeat the same call**

Expected: `409 { error: "already_hyped" }`.

- [ ] **Step 5: Re-fetch the inbox**

Expected: that row now has `is_hyped: true`.

- [ ] **Step 6: Stop the dev server (Ctrl-C). No commit.**

---

## Task 15: iOS — extend `InAppNotification` model

**Files:**
- Modify: `app/Mile A Day/Models/Competition.swift` (the `InAppNotification` struct)

- [ ] **Step 1: Add five optional fields**

Find the `InAppNotification` struct. Add the new fields (use whatever the existing decoding style is — likely `Codable` with `CodingKeys`):

```swift
struct InAppNotification: Codable, Identifiable {
    let id: String
    let title: String
    let body: String
    let type: String
    let data: [String: String]?
    let is_read: Bool
    let created_at: String

    // NEW — server-computed hype affordance fields. Default to nil/false for old responses.
    var hype_target_user_id: String? = nil
    var hype_context_type: String? = nil
    var hype_context_id: String? = nil
    var hype_context_label: String? = nil
    var is_hyped: Bool = false
}
```

If the file already uses `CodingKeys`, extend that enum with cases for each new field mapped to the matching snake_case JSON key.

⚠️ The `data: [String: String]?` shape may need to widen if our new data payload uses nested values (e.g., `new_value: number` in `friend_personal_best`). If decoding fails at runtime for those rows, change `data` to `[String: AnyCodable]?` or to a typed payload. For now, assume the existing shape works — most existing data entries are strings — and revisit if Task 22's manual test shows decode failures on PR rows.

- [ ] **Step 2: Verify build**

Open Xcode, build the `Mile A Day` scheme. Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add "app/Mile A Day/Models/Competition.swift"
git commit -m "iOS: add hype fields to InAppNotification model"
```

---

## Task 16: iOS — extend `HypeService` with context overload

**Files:**
- Modify: `app/Mile A Day/Services/HypeService.swift`

- [ ] **Step 1: Read the existing implementation**

Open the file. The current signature is roughly `func sendHype(targetUserId: String) async throws -> HypeResponse` at line ~16.

- [ ] **Step 2: Add a `HypeContext` struct + new overload**

Append (or place next to the existing function):

```swift
struct HypeContext {
    let contextType: String   // "mile" | "badge" | "pr"
    let contextId: String
    let contextLabel: String
}

enum HypeError: Error {
    case alreadyHyped
    case outOfHypes(resetsAt: String?)
    case other(String)
}

extension HypeService {
    func sendHype(targetUserId: String, context: HypeContext) async throws -> HypeResponse {
        var body: [String: String] = [
            "target_user_id": targetUserId,
            "context_type": context.contextType,
            "context_id": context.contextId,
            "context_label": context.contextLabel,
        ]
        // Existing implementation uses APIClient.fancyFetch — mirror its call style here.
        // Map 409 → HypeError.alreadyHyped, 429 → HypeError.outOfHypes(resetsAt:), everything else → .other(msg)
        // Use the same JSON encoding + response decoding as the existing sendHype(targetUserId:) call.
        // …
        fatalError("Implement using APIClient.fancyFetch pattern — see existing sendHype(targetUserId:) above.")
    }
}
```

⚠️ Replace the `fatalError` with a real implementation mirroring the existing `sendHype(targetUserId:)`. The two methods differ only in body shape and status-code handling. Pattern:

```swift
let url = URL(string: "\(APIClient.baseURL)/hype")!
let response = try await APIClient.fancyFetch(url: url, method: "POST", body: try JSONEncoder().encode(body))
switch response.statusCode {
case 200:
    return try JSONDecoder().decode(HypeResponse.self, from: response.data)
case 409:
    throw HypeError.alreadyHyped
case 429:
    let payload = try? JSONDecoder().decode([String: AnyCodable].self, from: response.data)
    let resetsAt = payload?["resets_at"]?.value as? String
    throw HypeError.outOfHypes(resetsAt: resetsAt)
default:
    let message = String(data: response.data, encoding: .utf8) ?? "Unknown error"
    throw HypeError.other(message)
}
```

(Match the exact API surface of `APIClient.fancyFetch` — adapt as needed if the helper returns differently.)

- [ ] **Step 3: Build in Xcode**

Expected: clean build.

- [ ] **Step 4: Commit**

```bash
git add "app/Mile A Day/Services/HypeService.swift"
git commit -m "iOS: HypeService context overload + structured errors"
```

---

## Task 17: iOS — render the hype button in the inbox row

**Files:**
- Modify: `app/Mile A Day/Views/NotificationInboxView.swift`

- [ ] **Step 1: Locate the row view**

Open the file. The row rendering is around lines 133–181 (mentioned in the spec). Find the trailing area of each row's HStack.

- [ ] **Step 2: Add per-row hype state**

The view that renders rows (likely a `ForEach` or a child `View`) needs local state for the per-row optimistic-hide flag. Two options — pick what fits the existing structure:

**Option A: per-row `@State` in a dedicated subview** (preferred — avoids the parent rebuilding the full list on each tap):

```swift
private struct InboxRow: View {
    let notification: InAppNotification
    let onTap: () -> Void
    @State private var localHidden: Bool = false
    @State private var errorToast: String? = nil
    @EnvironmentObject var hypeService: HypeService  // or however it's accessed

    var body: some View {
        HStack(spacing: 12) {
            // ... existing icon + text content ...
            Spacer()
            if !notification.is_hyped && !localHidden, let targetId = notification.hype_target_user_id,
               let ctxType = notification.hype_context_type, let ctxId = notification.hype_context_id,
               let ctxLabel = notification.hype_context_label {
                Button {
                    Task { await hype(targetId: targetId, ctxType: ctxType, ctxId: ctxId, ctxLabel: ctxLabel) }
                } label: {
                    Text("🔥 Hype")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Color.orange.opacity(0.18)))
                        .foregroundColor(.orange)
                }
                .buttonStyle(.borderless)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .overlay(alignment: .top) {
            if let msg = errorToast {
                Text(msg)
                    .font(.caption).padding(8)
                    .background(Capsule().fill(Color.red.opacity(0.85)))
                    .foregroundColor(.white)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func hype(targetId: String, ctxType: String, ctxId: String, ctxLabel: String) async {
        localHidden = true   // optimistic
        do {
            _ = try await hypeService.sendHype(
                targetUserId: targetId,
                context: HypeContext(contextType: ctxType, contextId: ctxId, contextLabel: ctxLabel)
            )
            // Success: stay hidden. Optionally pulse haptic / confetti.
        } catch HypeError.alreadyHyped {
            // Already hyped server-side — keep hidden, silent.
        } catch HypeError.outOfHypes {
            localHidden = false
            await showToast("You're out of hypes today — back tomorrow")
        } catch {
            localHidden = false
            await showToast("Couldn't send hype")
        }
    }

    @MainActor
    private func showToast(_ message: String) async {
        errorToast = message
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        errorToast = nil
    }
}
```

**Option B:** if the existing row is a closure inline in a `ForEach`, factor it into `InboxRow` first, then proceed as in Option A.

Wire `InboxRow` into the existing `ForEach` in place of the inline row body, passing the existing tap handler as `onTap`.

- [ ] **Step 3: Build in Xcode**

Expected: clean build.

- [ ] **Step 4: Commit**

```bash
git add "app/Mile A Day/Views/NotificationInboxView.swift"
git commit -m "iOS: hype button on hype-able inbox rows"
```

---

## Task 18: iOS — add "Friend personal bests" toggle in settings

**Files:**
- Modify: the Settings view that contains the existing "Friend activity" toggle (path unknown in advance — likely `app/Mile A Day/Views/Settings/NotificationSettingsView.swift` or similar; locate via grep)

- [ ] **Step 1: Find the existing friend-activity toggle**

```bash
grep -rn "friend_activity_enabled\|Friend activity" "app/Mile A Day/Views" --include="*.swift"
```

Open the file the toggle lives in. Note the view model / persistence pattern.

- [ ] **Step 2: Add a parallel toggle**

Add a sibling `Toggle` that mirrors the friend-activity one but binds to `friend_personal_best_enabled`. Example pattern (adapt to existing structure):

```swift
Toggle("Friend personal bests", isOn: $settings.friend_personal_best_enabled)
    .tint(MADTheme.primary)
```

If the view model has a typed settings struct, extend that struct first to include the new field (same name as backend column).

- [ ] **Step 3: Update the settings request/response decoding**

Wherever the iOS settings model is decoded from `GET /notifications/settings`, ensure the new boolean field is present (default true if absent).

- [ ] **Step 4: Build in Xcode**

Expected: clean build.

- [ ] **Step 5: Commit**

```bash
git add "app/Mile A Day/Views/Settings/"
git commit -m "iOS: add Friend personal bests toggle to settings"
```

---

## Task 19: Settings — verify save path

**No file changes.** Confirms the new toggle persists end-to-end.

- [ ] **Step 1: Run app in simulator**

- [ ] **Step 2: Toggle "Friend personal bests" off**

- [ ] **Step 3: Force-close + reopen the app**

Expected: toggle remembers the off state.

- [ ] **Step 4: Re-fetch via curl**

```bash
curl -s http://localhost:8080/notifications/settings \
    -H "Authorization: Bearer $TOKEN" | jq '.friend_personal_best_enabled'
```

Expected: `false`. Toggle back on, re-check — `true`.

---

## Task 20: PR detection sanity check

**No file changes.** Confirms the backend fires the right events.

- [ ] **Step 1: With dev server running, monitor logs**

```bash
cd backend && npm run dev
```

- [ ] **Step 2: From the iOS app on User A, upload a workout that beats both PRs**

- [ ] **Step 3: Inspect User B's (a friend of A) inbox**

```bash
curl -s http://localhost:8080/notifications/inbox \
    -H "Authorization: Bearer $TOKEN_B" | jq '.notifications[] | select(.type == "friend_personal_best")'
```

Expected: two new `friend_personal_best` rows — one with `pr_type: "fastest_mile"`, one with `pr_type: "most_miles_day"`. Both have non-null hype context fields.

- [ ] **Step 4: Upload another workout that beats neither**

Expected: no new `friend_personal_best` rows.

---

## Task 21: Hype-back wording verification

**No file changes.** Confirms each context type produces the right body on the recipient's side.

- [ ] **Step 1: From User B, hype each of User A's three notifications via the inbox button (mile, badge, PR)**

- [ ] **Step 2: From User A's account, fetch the inbox**

```bash
curl -s http://localhost:8080/notifications/inbox \
    -H "Authorization: Bearer $TOKEN_A" | jq '.notifications[] | select(.type == "hype_received") | {body, data}'
```

Expected three rows with bodies:
- "{B name} hyped your daily mile 🔥"
- "{B name} hyped you earning '{badge name}' 🔥"
- "{B name} hyped your new {pr label} 🔥"

- [ ] **Step 3: Legacy push-action path**

Use a real push to User A → tap "🔥 Hype" via the system banner on User B's device → verify User A's resulting hype_received body still says `@{B name} just hyped up your recent workout!` (unchanged generic wording).

---

## Task 22: End-to-end manual test suite (spec Section "Testing")

Walk through each of the 8 manual scenarios from the spec. Track here:

- [ ] 1. Hype a friend's mile from inbox → friend gets "{You} hyped your daily mile 🔥"
- [ ] 2. Hype a friend's medal from inbox → friend gets "{You} hyped you earning '{badge}' 🔥"
- [ ] 3. Hype a friend's PR from inbox → friend gets "{You} hyped your new {pr label} 🔥"
- [ ] 4. Triple-hype same friend (medal + PR + mile) → all three succeed, 4th attempt → 429 toast
- [ ] 5. Re-hype same medal → button gone after first tap, force-refresh inbox shows it still gone, manual curl returns 409
- [ ] 6. Push-action hype path → unchanged generic wording
- [ ] 7. PR detection accuracy → no-PR workout fires nothing; one-PR fires one row; two-PR fires two rows
- [ ] 8. Settings toggle → turning off "Friend personal bests" stops PR notifications for that user

Each box gets ticked when verified on device. Bugs found here loop back to whichever task created them.

---

## Self-review

(Performed after writing the plan.)

**Spec coverage:**
- ✅ Hype button in inbox (Task 17)
- ✅ Contextual hype-back wording (Task 12)
- ✅ Friend PR notification flow (Tasks 4–8)
- ✅ `hype_log` extension + dedupe (Tasks 1, 11, 12)
- ✅ Settings toggle (Tasks 5, 18, 19)
- ✅ Inbox enrichment with `is_hyped` (Task 13)
- ✅ Badge fan-out adds `badge_name` (Task 10)
- ✅ Push-action hype unchanged (Task 12's no-context branch + Task 21 verification)
- ✅ `friend_activity` kind discriminator (Task 9) — refinement during planning, captures the streak-broken-vs-mile-completed split that the spec assumed was already clean
- ✅ Manual test scenarios (Task 22)

**Placeholder scan:**
- One `fatalError` in Task 16 Step 2 — but it's inside an example labelled "replace with real implementation," and the surrounding code shows the exact pattern. Followed by a complete swift implementation example. Acceptable as a "this is the shape, fill in the call style" instruction.
- Two ⚠️ callouts that ask the implementer to verify a variable name (Task 8) or shape (Task 13 and Task 15). Each one specifies what to check and what to do — they're guardrails, not placeholders.

**Type consistency:**
- `HypeContext` struct exists in both backend (Task 11) and iOS (Task 16) with matching field semantics.
- `friend_personal_best` notification type defined in Task 4 and used consistently in Tasks 5, 7, 8, 13, 18.
- `pr_label` field in the push data payload (Task 7) is read by the inbox enricher (Task 13). Match confirmed.
- `badge_name` added in Task 10 is read by the inbox enricher (Task 13). Match confirmed.
- `kind` discriminator added in Task 9 is checked in Task 13. Match confirmed.

No gaps; no inconsistencies.
