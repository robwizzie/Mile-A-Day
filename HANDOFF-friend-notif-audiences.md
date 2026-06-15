# Handoff: Friend Notification Audiences

> **Claude: delete this file once tasks 7–11 are implemented, verified, and the
> branch is ready to merge.** It's a session-transfer note, not a deliverable.
> Do NOT commit it to `main`. Per the user's global rule, process artifacts get
> removed once the work is done.

---

## Where things stand

**Branch:** `feat/friend-notif-audiences`
**Worktree:** `.claude/worktrees/friend-notifs` (inside the repo, gitignored — NOT a sibling dir)
**Backend: DONE + smoke-tested. NOT deployed.** 13 commits, `tsc` clean. iOS: not started.

This feature adds per-event-type notification **audience** controls (who hears
about your activity, and whose you hear about) plus a private **close friends**
list and an **"ask each time"** confirmation flow.

### What the user wants (approved design — do not relitigate)

- **Close friends:** one-directional, private (Instagram-style). You pick yours;
  the other person is never told. Settable from a friend's profile (star) and a
  dedicated Close Friends list screen.
- **Audience per event type:** `none` / `close` / `all` / `ask`. `ask` is
  outgoing-only (prompts you per-workout to confirm before notifying).
- **Run vs walk split:** workout event types (`mile_completed`, `extra_workout`,
  `workout`) have separate run/walk audiences. Walk can be set to `match_run`
  ("Same as Running") to track the run setting.
- **Cascade, most-specific wins:** (event+activity row) → (event row) →
  (global `*` row) → system default. Unset = inherits. The UI shows inherited
  values as "Default · <resolved>" in gray; explicit overrides in brand pink.
- **Incoming mirrors outgoing** (same matrix, minus `ask`).
- **Ask mode is server-authoritative:** server NEVER auto-sends. On an `ask`
  workout it stashes a `pending_friend_notifications` row instead of pushing.
  The user confirms (or it expires at THEIR local midnight — same calendar day
  only). Background-synced / unseen workouts accumulate as a pending "stash."
- **New `workout` trigger:** pre-goal workouts that don't complete the mile are
  now a notifiable event, defaulting to `none` (opt-in, zero behavior change for
  existing users).

### Approved mockup

`mockup-sandbox` → http://localhost:5180/m/friend-notif-settings — **Variant B**
("Inline dropdowns"). Key UI decisions baked into that mockup:
- Big hero default selector at top ("Share your activity with" / "Hear about
  activity from"), 2×2 large buttons — this is the main control most people use.
- Per-activity cards below with dropdown rows. Each dropdown's first option is
  "Default · <resolved>"; walking rows add "Same as Running · <resolved>".
- Sharing | Incoming segmented tabs.
Restart the sandbox dev server before viewing (Tailwind v4 stale-scan gotcha).

---

## Backend API contract (LIVE on this branch, smoke-tested)

All protected (Bearer token, `req.userId`). Mount prefixes: `/friends`, `/notifications`.

### Close friends (`/friends`)
- `GET  /friends/close` → array of user objects (same shape as `/friends` list)
- `POST /friends/close/:friendId` → `{message}` | 400 `{error}` (self-add or non-accepted-friend rejected)
- `DELETE /friends/close/:friendId` → `{message}`

### Audience settings (`/notifications`)
- `GET /notifications/audience` →
  ```json
  { "settings": { "outgoing": [row...], "incoming": [row...] },
    "systemDefaults": { "outgoing": {...}, "incoming": {...} } }
  ```
  where a `row` = `{ direction, event_type, activity_type, audience, updated_at }`.
  Only explicitly-set rows are returned; resolve the rest client-side via the
  cascade using `systemDefaults`.
- `PUT /notifications/audience` body `{ direction, event_type, activity_type?, audience }`
  - `audience: null` or omitted → resets (deletes the row, reverts to cascade).
  - Returns the same shape as GET.
  - 400 on: invalid audience value; `ask` on `incoming`; `match_run` when
    `activity_type != 'walk'`; activity row on a non-activity event; bad event_type.

**Event types:** `mile_completed`, `extra_workout`, `workout`, `personal_best`,
`badge_earned`, `challenge_completed`, `streak_broken`. Global row uses `event_type='*'`.
**Activity types:** `''` (n/a), `'run'`, `'walk'`. **Audiences:** `none`,`close`,`all`,`ask`,`match_run`.
**System defaults:** outgoing all `all` EXCEPT `workout`=`none`; incoming all `all`.

### Pending / ask-mode (`/notifications`)
- `GET /notifications/pending` → `{ pending: [ {id, event_type, activity_type, workout_id, payload, local_date, created_at} ] }`
  (lazy-expires stale rows on read; only same-local-day rows returned)
- `POST /notifications/pending/:id/send` body `{ audience?: 'close'|'all' }` (default `all`)
  → `{sent: N}` | 404 not found | 403 not owner | 409 already sent/dismissed or
  current setting is `none` | 410 expired (past its local day). Atomic claim — no double-send.
  Re-checks the sender's CURRENT outgoing audience; request can't widen beyond it
  (current `close` forces `close`).
- `DELETE /notifications/pending/:id` → dismiss one → `{message}`
- `DELETE /notifications/pending` → dismiss all → `{message, count}`

### DB tables (already created in PRODUCTION)
`close_friends`, `notification_audience_settings`, `pending_friend_notifications`.
All additive. See commit `d24814c` history / the service files for exact columns.
A backend deploy is required before iOS can be verified end-to-end (old clients
are unaffected — sending is server-side, defaults preserve current behavior).

---

## Remaining work (TodoWrite tasks #6–#11)

Use the existing task list. Tasks #2–#5 are done. **Task #6 (deploy) is the gate
before iOS verification** — the user wanted to decide merge/deploy timing
themselves; ASK before pushing to `main` (production rules).

### #7 — iOS: models + API service layer
Swift services via `APIClient.fancyFetch` (pattern in `app/Mile A Day/Services/`):
- `CloseFriendsService` — list/add/remove; published close-friend-id set for UI.
- Models: `AudienceSetting`, `Audience` enum (none/close/all/ask/matchRun; absence
  of row = "default"), `PendingFriendNotification`.
- `AudienceSettingsService` — GET (rows + systemDefaults), PUT single change, and
  a **client-side resolver mirroring the backend cascade**
  (activity → match_run → event → global → systemDefault) so the UI can render
  "Default · <resolved>" labels.
- `PendingNotificationsService` — list/send/dismiss/dismissAll; fetch on app
  foreground (`scenePhase .active`), but skip the call if the user has no `ask`
  settings (cheap guard).
- `@Observable` view models (iOS 17+) per `.claude/rules/ios.md`.

### #8 — iOS: close friends UI
- `UserProfileDetailView` (`app/Mile A Day/Views/Friends/`): star toggle for
  accepted friends, optimistic. One-time hint: "Close friends can get
  notifications others don't."
- New `CloseFriendsListView` in `Views/Friends/`: list + remove + "Add" (reuse
  friend list filtered to non-close). Entry point from `FriendsListView`.
- Privacy: never reveal to the other user. No new entitlements/permissions.

### #9 — iOS: Friend Activity settings screen (approved Variant B)
New `FriendActivitySettingsView` near `NotificationSettingsView`. Implements the
mockup exactly: hero default card, "Customize per activity" cards, dropdown
rows with "Default" + "Same as Running" options, Sharing|Incoming tabs.
- "Default" selection → `PUT audience:null`. "Same as Running" → `audience:'match_run'`.
- "Other workouts" caption: "Workouts that don't complete your mile."
- Entry: a "Friend Activity ›" row in `NotificationSettingsView`. Leave the
  existing friend-activity boolean toggles + per-friend mutes in place (they're
  separate prefs that still gate sending).

### #10 — iOS: ask-mode prompts (both ship)
- **Celebration embed:** in `GoalCompletedCelebrationView` (`Views/Celebrations/`),
  when a pending item matches today's mile completion, show the notify card
  (📣 "Let your friends know?", avatar stack, Notify / Not this time). Hidden when
  no pending item.
- **Standalone pending sheet:** new `PendingNotificationsSheet` — lists pending
  items, per-item Notify/✕, "Dismiss all." Presented from `DashboardView` when
  pendings exist AND no celebration is showing for them (CelebrationManager owns
  priority). Trigger on foreground fetch + after sync completes.
- Items vanish locally on send/dismiss; stale (`local_date < today`) never shown.

### #11 — End-to-end verify + adversarial review
- User builds/runs in Xcode (no `xcodebuild` from CLI). Walk: set close friend →
  incoming `close` → verify filtering; outgoing `ask` → upload → pending appears
  → confirm → push. Midnight expiry via `/db-query` (set a pending's local_date
  to yesterday → confirm hidden + 410 on send).
- Backwards-compat spot check: no audience rows ⇒ behavior unchanged.
- `codex review --uncommitted` on the diff; address findings.
- App Review: no new entitlements/permissions; notifications user-controllable ✓.

---

## Method notes for the next session
- This is subagent-driven (per the user's default): fresh implementer subagent
  per task, then spec-compliance review, then code-quality review, fix loops.
- User's hard rules: NO `Co-Authored-By`/AI trailers in commits or PRs. NO sibling
  clone dirs — worktrees go in `.claude/worktrees/<slug>`. Backend ESM imports
  end `.js`. `main` is production — confirm before pushing.
- Backend smoke artifacts were created and fully cleaned from the DB. If you make
  new test users, delete them (mind FKs: `in_app_notifications`, `notification_log`).
