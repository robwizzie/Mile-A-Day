# Hype From the Notification Inbox

**Date:** 2026-05-14
**Status:** Approved (pending user spec review)

## Problem

The "hype" feature is reachable only from a push notification banner (the `🔥 Hype` action on `friend_activity` pushes). If the user dismisses the push or misses it, there's no way to hype that workout. The in-app notification inbox already shows the same friend activity (and other celebration events like medals) but offers no hype affordance.

Additionally, the hype-back notification the recipient gets is generic ("@Rob just hyped up your recent workout!") — it doesn't tell them *what* was hyped, even when the trigger was something specific like a medal or PR.

## Goals

1. Add a `🔥 Hype` button to specific celebration rows in the notification inbox.
2. Make the hype-back notification contextual: tell the recipient who hyped them **and** what was hyped (e.g., "Rob hyped you earning 'Year in miles' 🔥").
3. Build out friend personal-best notifications, which don't exist today, so PR celebrations are also hype-able.

## Non-goals

- Replacing or restyling the existing push-action hype button.
- Allowing hype on competition-related notifications (`competition_finished`, `competition_milestone`, lead changes, etc.). The competitor dynamic makes hyping a rival you're losing to feel off.
- Re-hyping the same event after a context has already been hyped (button disappears entirely after tap; backend rejects duplicate).
- Per-friend hype budgets. The daily 3-hype cap stays as-is and is shared across surfaces (push action and inbox).

## Scope: hype-able inbox notification types

| Type | Today | What's needed |
|---|---|---|
| `friend_activity` (friend completed today's mile) | ✅ in inbox | Add hype affordance |
| `friend_badge_earned` (friend earned a non-common badge) | ✅ in inbox | Add hype affordance |
| `friend_personal_best` (friend set a new PR) | ❌ doesn't exist | Build from scratch + add hype affordance |

The existing 1/hour-per-(sender, recipient) throttle on `friend_badge_earned` stays (prevents multi-badge-from-same-workout spam). No throttle on `friend_personal_best` — if a single workout breaks both PRs (fastest mile + most miles in one day), both rows appear in the inbox so the viewer can hype either or both.

## Data model

### `hype_log` — extend

Today: `(id, sender_id, target_id, created_at)`. Add three nullable columns:

```sql
ALTER TABLE hype_log
  ADD COLUMN context_type text,    -- 'mile' | 'badge' | 'pr' | NULL (legacy push-action)
  ADD COLUMN context_id text,      -- workout_id, badge_id, or '{pr_type}:{workout_id}'
  ADD COLUMN context_label text;   -- snapshot, e.g. 'Year in miles', 'Fastest mile (6:32)'

CREATE UNIQUE INDEX hype_log_context_dedupe_idx
  ON hype_log (sender_id, target_id, context_type, context_id)
  WHERE context_id IS NOT NULL;
```

The partial unique index lets two legacy (context-less) hypes coexist while preventing duplicate hypes of the same concrete event.

### `notification_settings` — extend

Add `friend_personal_best_enabled boolean NOT NULL DEFAULT TRUE`, mirroring the existing `friend_activity_enabled` toggle.

### No new tables

Friend PR detection is done by comparing pre-workout vs post-workout aggregates inside the workout upload flow — same approach the badge evaluator already uses. No need for a `user_personal_records` table.

## Backend: friend personal-best notifications

### Detection

In `workoutController.ts`, after the upload transaction commits, alongside the existing `evaluateWorkoutRewards` call:

1. **Pre-workout PRs** — query `MIN(fastest_split_pace)` and `MAX(daily_total)` across the user's workouts excluding the just-uploaded workout IDs.
2. **Post-workout PRs** — same query without the exclusion.
3. For each dimension where post > pre (faster pace or more miles), fire `fanOutFriendPersonalBestPush(senderId, prType, oldValue, newValue, workoutId)`.

Both dimensions can fire from the same workout — each gets its own fan-out call and its own inbox row.

### `fanOutFriendPersonalBestPush` (new, in `pushNotificationService.ts`)

Mirrors `fanOutFriendBadgePush` but with no throttle.

- For each accepted friend, gated by `shouldSendNotification(friendId, senderId, 'friend_personal_best')`:
  - Title: `"{Sender} set a new personal best"`
  - Body (varies by PR type):
    - `fastest_mile`: `"Fastest mile — {mm:ss} pace"`
    - `most_miles_day`: `"Most miles in a day — {miles} mi"`
  - Type: `'friend_personal_best'`
  - Data: `{ sender_id, pr_type, new_value, workout_id }`

### `pushNotificationService.NotificationType` union

Add `'friend_personal_best'`. Add the matching settings key plumbing in `notificationSettingsService.ts`.

## Backend: extended `POST /hype`

### Request shape (additive)

```typescript
{
  target_user_id: string;
  context_type?: 'mile' | 'badge' | 'pr';
  context_id?: string;
  context_label?: string;
}
```

Old callers (the push-action handler in `MADNotificationService.swift`) keep working — they send no context fields, the hype gets logged with `NULL` context, and the existing generic wording is used.

### Controller behavior (`hypeController.sendHype`)

1. Validate sender ≠ target (unchanged).
2. Validate sender + target are friends or co-competitors (unchanged).
3. **New**: if `context_type` and `context_id` are both present, check the dedupe index. If a matching row exists → `409 { error: 'already_hyped' }`.
4. Validate target completed ≥ 1.0 miles today (unchanged — keeps the gating but means PR hypes also require a mile today; this is fine because PRs come from workouts which include the mile).
5. Atomic insert into `hype_log` with the new columns, gated by the daily 3-cap (unchanged service path, just more columns to pass). If cap hit → `429 { hypes_remaining, resets_at }`.
6. Send push + inbox to target with contextual wording.

### Hype-back wording

Constructed in `hypeController.sendHype` after a successful log:

| `context_type` | Body |
|---|---|
| `mile` | `"{Sender} hyped your daily mile 🔥"` |
| `badge` | `"{Sender} hyped you earning '{context_label}' 🔥"` |
| `pr` | `"{Sender} hyped your new {context_label} 🔥"` |
| `NULL` (legacy push-action) | unchanged: `"@{Sender} just hyped up your recent workout!"` |

Delivered via `sendPush()` which already writes to `in_app_notifications`, so the recipient gets both a push banner and a persistent inbox row.

## Backend: `GET /notifications/inbox` response

Each row in `InAppNotificationResponse.notifications` gains four computed fields:

```typescript
{
  // existing
  id, title, body, type, data, is_read, created_at,

  // new — null when the row isn't hype-able
  hype_target_user_id: string | null;
  hype_context_type: 'mile' | 'badge' | 'pr' | null;
  hype_context_id: string | null;
  hype_context_label: string | null;
  is_hyped: boolean;
}
```

Computation lives in `inAppNotificationController.getInbox`. For each row:

- `friend_activity` → target = `data.user_id`, context_type = `'mile'`, context_id = `data.workout_id` (if present, else the user_id+date pair), label = `"Today's mile"`.
- `friend_badge_earned` → target = `data.sender_id`, context_type = `'badge'`, context_id = `data.badge_id`, label = `data.badge_name` (need to include this in the existing fan-out — small additive change to `fanOutFriendBadgePush`).
- `friend_personal_best` → target = `data.sender_id`, context_type = `'pr'`, context_id = `"{pr_type}:{workout_id}"`, label = `"fastest mile (6:32)"` or `"most miles in a day (8.5 mi)"`.
- All other types → all four fields `null`.

`is_hyped` is computed by joining inbox rows to `hype_log` on `(sender_id = viewer, target_id = hype_target_user_id, context_type, context_id)`. A single batched query per inbox page.

## iOS changes

### `InAppNotification` model (`Competition.swift`)

Add the five optional fields above. Default to `nil` / `false` for backward compatibility with old API responses.

### `NotificationInboxView.swift`

Row layout gains a trailing `🔥 Hype` button when `hype_target_user_id != nil && !is_hyped`. The button:

- Doesn't intercept the full-row tap gesture (uses a contained `Button` with `.buttonStyle(.borderless)` inside the row's `HStack`).
- Optimistic UI: hide the button immediately on tap, then call `HypeService.sendHype(targetUserId:context:)`.
- On 429: restore button + toast "You're out of hypes today — back tomorrow".
- On 409: keep hidden (already hyped state is correct) + silent.
- On other error: restore button + generic error toast.

### `HypeService.swift`

Add a new overload:

```swift
func sendHype(
    targetUserId: String,
    contextType: String,
    contextId: String,
    contextLabel: String
) async throws -> HypeResponse
```

Plumb the four context fields into the request body. The existing no-context `sendHype(targetUserId:)` keeps working for the push-action path.

### `MADNotificationService.swift`

No changes — `handleHypeAction` keeps calling the context-less variant.

### Settings UI

Add a "Friend personal bests" toggle alongside the existing "Friend activity" toggle, bound to `friend_personal_best_enabled`.

### Badge fan-out — small additive

`fanOutFriendBadgePush` currently sends `data: { sender_id, badge_id, rarity }`. Add `badge_name` to the data payload so the inbox controller can populate `hype_context_label` for `friend_badge_earned` rows without an extra join.

## Edge cases

- **Target deleted their workout** between notification fire and hype tap → 404 or stale data. Server already validates "target completed ≥ 1.0 miles today"; if they undid it, hype fails with the existing error path. Acceptable.
- **Hyping someone who unfriended you** → existing friendship/competitor check rejects with the existing error. Acceptable.
- **PR fan-out racing badge evaluation** → both run after the workout transaction commits. They're independent fire-and-forget calls. Order doesn't matter; a single workout can produce one mile row + one badge row + two PR rows for friends to hype.
- **Push action hype while inbox row also exists** → push-action hype logs with no context; the inbox row's `is_hyped` check looks for `(sender, target, context_type, context_id)` and finds no match → button still shows. This is acceptable: the two flows are independent. If we want them unified we'd need to retrofit the push action to send context, which is a separate piece of work.

## Implementation order

A single PR is fine but the work breaks into roughly four chunks:

1. **DB migration** — `hype_log` columns + unique partial index, `notification_settings.friend_personal_best_enabled`.
2. **Friend PR notifications** — detection logic, `fanOutFriendPersonalBestPush`, settings plumbing.
3. **Hype API + hype-back wording** — extend `POST /hype`, add 409 path, contextual hype-back, badge fan-out adds `badge_name`.
4. **Inbox enrichment + iOS** — compute hype fields in `getInbox`, add iOS button, settings UI toggle.

Each chunk is independently testable, but they ship together since the iOS UI depends on all three backend pieces.

## Testing

No automated test suite exists for backend or iOS. Manual verification:

1. **Hype a friend's mile from inbox** → friend gets a push + inbox row that says "{You} hyped your daily mile 🔥".
2. **Hype a friend's medal from inbox** → friend gets a push + inbox row that says "{You} hyped you earning '{badge name}' 🔥".
3. **Hype a friend's PR from inbox** → friend gets a push + inbox row that says "{You} hyped your new fastest mile (6:32) 🔥".
4. **Triple-hype the same friend** → friend has medal + PR + mile in one day; you can spend all 3 daily hypes on them; 4th attempt returns 429.
5. **Re-hype same medal** → button disappeared after first tap; after force-refreshing inbox, button stays gone; manual API call returns 409.
6. **Push-action hype path** → unchanged generic wording works as today.
7. **PR detection** — a workout that doesn't beat any record produces no PR notification; a workout that beats one produces one row; a workout that beats both produces two rows.
8. **Settings toggle** — turning off "Friend personal bests" stops PR pushes/inbox rows for that user.
