# Hype-able Daily Challenge Completions — Design

**Date:** 2026-05-16
**Status:** Approved

## Problem

The "hype" feature lets a user cheer a friend's accomplishment from the
notification inbox. It currently supports three notification types, each with a
hype context type:

| Notification type        | Context type | Hype-able |
|--------------------------|--------------|-----------|
| `friend_activity` (mile) | `mile`       | yes       |
| `friend_badge_earned`    | `badge`      | yes       |
| `friend_personal_best`   | `pr`         | yes       |
| `friend_challenge_completed` | —        | **no**    |

`friend_challenge_completed` ("X finished today's challenge") has no hype
context derivation, no dedup key, and no backend validation, so no hype button
ever appears for it. This design makes daily challenge completions hype-able.

## Goal

Make `friend_challenge_completed` notifications hype-able, consistent with how
`mile` / `badge` / `pr` already work: a per-event dedup key, backend validation
that the friend really completed the challenge, and a contextual hype-back
notification.

## Approach

Add a new `challenge` hype context type, mirroring the existing `mile` pattern.

Rejected alternatives:
- **Reuse the `mile` context** — the `mile` validation requires ≥1 logged mile
  that day, but challenges such as "10k steps" can be completed without one, so
  valid hypes would be wrongly rejected; dedup would also collide with the real
  mile hype.
- **Context-less (legacy) hype** — loses per-event dedup (button re-hypeable),
  produces generic hype-back text, and its validation fallback ("ran today")
  fails for non-running challenges.

## Context key design

- **context_type:** `'challenge'`
- **context_id:** `"<friendUserId>:<localDate>"` (e.g. `"abc123:2026-05-16"`).
  The `user_challenge_completions` table is uniquely keyed on
  `(user_id, local_date)` — one challenge completion per user per day — so this
  is a stable, unique per-completion key. Same shape as the `mile` context_id.
- **context_label:** the challenge title (e.g. "Double Down").
- **No DB migration.** `hype_log.context_type` is a free-text column; the
  partial unique index on `(sender_id, target_id, context_type, context_id)`
  already covers any context_type value.

## Backend changes

1. **`services/hypeService.ts`** — widen `HypeContext.contextType` union to
   `'mile' | 'badge' | 'pr' | 'challenge'`.

2. **`controllers/hypeController.ts`**
   - Add `'challenge'` to the `context_type` whitelist.
   - Add a `buildHypeBackBody` case for `'challenge'`:
     `` `${senderName} hyped your '${context.contextLabel}' challenge 🔥` ``.
   - Add validation for the `challenge` context: parse the date from
     `context_id` (expect `"<userId>:YYYY-MM-DD"`), then verify the target has a
     `user_challenge_completions` row for that local date. Reject with 400 if
     not. This lets users hype older challenge notifications, consistent with
     the `mile` path.

3. **`services/dailyChallengeService.ts`** — export a new helper
   `hasChallengeCompletion(userId, localDate): Promise<boolean>` for the
   controller validation above (currently `getCompletionRow` is file-private).

4. **`controllers/inAppNotificationController.ts`**
   - Widen the `HypeDerivation` interface `hype_context_type` union to include
     `'challenge'`.
   - Add a `friend_challenge_completed` branch to `deriveHypeContext()`:
     - `hype_target_user_id` = `data.sender_id`
     - `hype_context_type` = `'challenge'`
     - `hype_context_id` = `"<sender_id>:<local_date>"` (from `data.local_date`)
     - `hype_context_label` = `data.challenge_title`, falling back to `row.body`
       (the stored notification body already is the challenge title), then to
       `"today's challenge"`.
     - Return empty derivation if `sender_id` or `local_date` is missing.

5. **`services/pushNotificationService.ts`** — in `fanOutFriendChallengePush`,
   add `challenge_title: completion.challengeTitle` to the push `data` so the
   hype label is reliable for new notifications.

## iOS changes

6. **`Views/NotificationInboxView.swift`**
   - Add a `friend_challenge_completed` case to `hypeAffordance(for:)`:
     - guard `data["sender_id"]` present
     - `localDate` = `data["local_date"]`, falling back to
       `String(notification.created_at.prefix(10))`
     - returns `HypeContext(contextType: "challenge",
       contextId: "<sender_id>:<localDate>",
       contextLabel: data["challenge_title"] ?? notification.body)`
   - Add a `friend_challenge_completed` case to `hypeTargetUserId(for:)`
     returning `data["sender_id"]`.

7. **`Services/HypeService.swift`** — update the `HypeContext.contextType` doc
   comment to list `"challenge"` (cosmetic; the field is already `String`).

The hype button rendering, optimistic grey-out, rate-limit toast, and the
older-backend context-less fallback path are all already generic — no changes.

## Edge cases

- **Pre-existing challenge notifications** (sent before `challenge_title` is
  added to the payload) remain hype-able: `local_date` is already present in
  their `data`, and the label falls back to the notification body server-side
  and on iOS.
- **Dedup:** the partial unique index on
  `(sender_id, target_id, context_type, context_id)` prevents re-hyping the same
  completion.
- **Validation failure:** if the target has no `user_challenge_completions` row
  for the parsed date, the backend returns 400, mirroring the `mile` path.
- **Self-hype / non-friend:** already blocked by existing
  `senderId === targetUserId` and `isFriendOrCoParticipant` checks.

## Out of scope

- Hyping competition notifications, friend nudges, or other non-celebratory
  notification types.
- Any change to the daily-challenge evaluation logic or the 3-hypes-per-day cap.
