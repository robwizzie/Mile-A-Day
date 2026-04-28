# Hype Feature — Design

**Date:** 2026-04-27
**Branch:** `feature/hype-reactions`
**Status:** Approved (pending user review of this written spec)

## Summary

Add a positive social reaction — "hype" — that lets a user celebrate a friend or competition co-participant who just completed their daily mile. Hype is the affirmative mirror of the existing `nudge` ("go run!") and `flex` (trash talk while ahead) features.

The entire user experience is a rich-notification action button on the existing `friend_activity` push. There is no in-app entry point in v1.

## Goals

- Lightweight, friction-free way to send positive reinforcement to friends and competitors.
- Reuse existing notification fanout, push infrastructure, and notification-settings system.
- Avoid notification fatigue — no new push to potential senders; we extend what already fires.
- Avoid moderation surface area — single-tap, no message, no media.

## Non-Goals (v1)

- No in-app hype button, no profile/feed entry point.
- No persistent hype counter on the workout, no hype history feed for the recipient.
- No custom messages, no emoji choice — single fixed reaction.
- No watchOS support — notification actions on watch are a follow-up.

## User Flow

1. Alice completes her daily mile.
2. The existing `friend_activity` push fans out (capped) to:
   - up to 5 of Alice's friends, AND
   - up to 5 competition co-participants who share an active competition with Alice and are not already in the friend set (deduped, capped at ~10 total recipients).
3. Bob receives the push: `"Alice got their mile in! Your friend just completed their daily mile. Time to lace up!"` with a `🔥 Hype` action button.
4. Bob long-presses (or expands) the notification and taps `🔥 Hype` *without* opening the app.
5. iOS calls `POST /hype { target_user_id: <alice> }` via `APIClient.fancyFetch`.
6. Backend validates, logs, and sends a push to Alice: `"🔥 You got hyped! @bob just hyped up your recent workout!"`
7. Bob's device shows a brief local toast: `"Hype sent! 2 left today"` (or `"Out of hypes for today"` on 429).

## Scope: who can hype whom

- **Friends** (bidirectional `friendships.status = 'accepted'`), **OR**
- **Competition co-participants** — both users have `invite_status = 'accepted'` in at least one currently-active competition (start_date in the past, end_date null or future, winner null).

Validation fails with 403 if neither relationship holds.

## Rate limits

- **3 hypes per sender per 24 hours**, total across all recipients.
- Implemented as a rolling 24-hour window: `created_at >= NOW() - INTERVAL '24 hours'`. Not a midnight reset — simpler, no timezone surface area, and there is no user-visible reset clock to confuse anyone.
- Sender-side only. Recipients have no incoming-rate cap (a popular runner can be hyped by many friends).

## Eligibility for hyping

- Target user must have `getTodayMiles(targetId) >= 1.0` (same helper that powers `friendNudge`'s "already completed" check). If target hasn't run today, the endpoint returns 400.
- Sender cannot hype themselves.

## Data Model

One new table, used purely for rate-limit accounting and audit. No counter table, no message column, no workout_id.

```sql
CREATE TABLE hype_log (
  id          BIGSERIAL PRIMARY KEY,
  sender_id   UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  target_id   UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX hype_log_sender_created_idx ON hype_log (sender_id, created_at DESC);
```

Schema is applied manually against PostgreSQL — this repo has no migrations system (per `.claude/rules/backend.md`).

## Backend API

### Files to add

- `backend/src/services/hypeService.ts`
  - `canHype(senderId: string): Promise<boolean>` — `true` if sender has fewer than 3 rows in last 24h.
  - `getDailyHypeCount(senderId: string): Promise<number>`
  - `logHype(senderId: string, targetId: string): Promise<void>`
- `backend/src/controllers/hypeController.ts` — request/response handling, validation pipeline.
- `backend/src/routes/hypeRoutes.ts` — wires `POST /hype` and `GET /hype/status` to the controller.
- `server.ts` — register `hypeRoutes` *after* `authenticateToken`.

### `POST /hype`

- Auth: required.
- Body: `{ target_user_id: string }`
- Validation order (mirrors `flexController`):
  1. `target_user_id` present and != `req.userId` → 400.
  2. Sender and target are friends OR share an active competition → else 403.
  3. `getTodayMiles(targetId) >= 1.0` → else 400 with `"This user hasn't completed their mile today"`.
  4. `canHype(senderId)` → else 429 with `{ error, hypes_remaining: 0 }`.
- On success:
  - Insert into `hype_log`.
  - If `shouldSendNotification(targetId, senderId, 'hype')` is true, send push.
  - Respond 200 with `{ message: "Hype sent", hypes_remaining: <n> }`.

**Push payload (to recipient):**

```
title: "🔥 You got hyped!"
body:  "@<senderUsername> just hyped up your recent workout!"
type:  "hype_received"
data:  { user_id: <senderId> }
```

### `GET /hype/status`

- Auth: required.
- Response: `{ hypes_remaining: number, resets_at: string /* ISO of oldest-of-the-3 + 24h, or null if unused */ }`.
- Used by iOS to disable the action button gracefully.

### Notification settings

Add `'hype'` to the valid `notification_type` values used by `notificationSettingsService`. Default: enabled. Existing per-user-pair preference rows govern delivery.

## Backend changes to existing push

`backend/src/services/notificationService.ts` — the `friend_activity` fanout:

1. Add `category: 'FRIEND_ACTIVITY'` to the APNs payload so iOS knows which actions to render. (Older iOS clients without the registered category will simply ignore it — safe rollout.)
2. The `data: { user_id: <runnerId> }` payload is already present; iOS reads this as the hype target.
3. Add a parallel fanout to competition co-participants:
   - Query users in any active competition with the runner where `cu.invite_status = 'accepted'`.
   - Subtract the friend set already notified.
   - Cap to 5 additional recipients.
   - Same `shouldSendNotification(recipient, runner, 'friend_activity')` gate.
4. Combined cap: ~10 recipients per completion event. Use a `Set<userId>` to dedupe.

## iOS Changes

### Notification category registration

In the `UNUserNotificationCenter` configuration at app launch (likely `NotificationService.swift` or `AppDelegate`):

```swift
let hypeAction = UNNotificationAction(
    identifier: "HYPE_ACTION",
    title: "🔥 Hype",
    options: []
)
let category = UNNotificationCategory(
    identifier: "FRIEND_ACTIVITY",
    actions: [hypeAction],
    intentIdentifiers: [],
    options: []
)
UNUserNotificationCenter.current().setNotificationCategories([category])
```

### Action handler

In `userNotificationCenter(_:didReceive:withCompletionHandler:)`:

- If `actionIdentifier == "HYPE_ACTION"`:
  - Read `target_user_id` from `response.notification.request.content.userInfo["user_id"]`.
  - Call `HypeService.sendHype(targetUserId:)` via `APIClient.fancyFetch`.
  - On 200: schedule a local notification toast `"Hype sent! \(remaining) left today"`.
  - On 429: schedule a local notification toast `"Out of hypes for today"`.
  - On any other failure: schedule `"Couldn't send hype, try opening the app"`.

### New service

`app/Mile A Day/Services/HypeService.swift`:

```swift
struct HypeResponse: Decodable {
    let message: String
    let hypesRemaining: Int
}

@MainActor
final class HypeService {
    static func sendHype(targetUserId: String) async throws -> HypeResponse {
        // POST /hype via APIClient.fancyFetch
    }
}
```

The action handler runs in the system's notification handler, which can execute network requests in the background without launching the app. `APIClient.fancyFetch` already has token refresh, so auth Just Works.

## Edge Cases

- **Race on the rate limit:** two simultaneous hype requests could both pass the pre-check before either inserts. Mitigation: post-insert recount; if > 3, delete the just-inserted row and return 429. Simpler than `SELECT … FOR UPDATE`, and 1-row over-shoot is acceptable in the worst rollback gap.
- **Target deleted their workout between push and tap:** the `getTodayMiles >= 1.0` check fails → 400 → "out of date" toast.
- **Notification fanout dedup:** when the runner shares N competitions with the same co-participant, the co-participant receives at most one push. Use a `Set<userId>` already-notified during the fanout.
- **Privacy / blocking:** if a friend-block or report system exists, hyping a blocked user must silently 403. The planning phase should investigate the existence of a block table and add the gate if present.

## Failure modes

| Scenario | User experience |
|---|---|
| Network failure on action tap | Local toast: "Couldn't send hype, try opening the app" |
| 429 (rate limited) | Local toast: "Out of hypes for today" |
| 400 (target deleted run) | Local toast: "Couldn't send hype" |
| Recipient disabled `'hype'` notifications | Endpoint still returns 200 (logged, no push delivered) |

## Rollout

1. Apply DB migration manually (`hype_log` table + index).
2. Land backend changes (services, controller, route, augmented `friend_activity` push payload, competition co-participant fanout, `'hype'` notification setting).
3. Verify backend manually via `/api-test` (see Testing section).
4. Land iOS changes (category registration, action handler, `HypeService`).
5. Verify on a physical device.
6. Ship in next iOS release.

No feature flag — the surface is small and the worst failure mode is a 4xx the toast handles. The new `category` payload on the existing push is forward-compatible with older clients.

## Testing (manual — no test harness in this repo)

### Backend

- `npm run build` clean after each code change.
- `npm run dev` and drive `/hype`:
  - 200 happy path (friend, completed mile today).
  - 200 from competition co-participant who isn't a friend.
  - 400 target hasn't completed mile today.
  - 400 self-hype attempt.
  - 403 not friends and no shared active competition.
  - 429 on 4th request inside 24h window.
  - Recipient with `'hype'` disabled → 200, no push.
- DB checks via `/db-query`: `hype_log` row count matches calls; the rate-limit query returns the expected count across the 24h boundary.

### iOS

- Build in Xcode, install on a physical device (notification actions require a real device).
- Trigger a friend's workout completion in staging.
- Confirm the push arrives with the `🔥 Hype` action.
- Tap the action *without* opening the app — confirm `POST /hype` hit in server logs and the confirmation toast appears.
- Burn through 4 hypes from the same device — confirm the 4th shows "Out of hypes for today".

## Out of scope (future work, not v1)

- In-app hype button on friend cards / activity feed.
- Persistent hype count on the recipient's workout.
- Custom messages or emoji selection.
- watchOS notification action.
- Hype-related badges or streak interactions.
