# Mile-completion notification: surface distance, time, best pace

**Date:** 2026-05-14
**Branch:** `worktree-mile-completion-stats`

## Goal

When a user completes their daily mile, the friends-facing notification
("X got their mile in!") should surface concrete workout stats — distance,
time, and best pace — instead of the current generic body.

Both the **APNs push** and the corresponding **in-app inbox row** are
covered by this change, because `sendPush` persists the same `title`/`body`
to `in_app_notifications` (see
`backend/src/services/pushNotificationService.ts:292`). One body change
updates both surfaces.

## Scope

**In scope**

- `notifyFriendsOfMileCompletion` in
  `backend/src/services/notificationService.ts` — change the body text it
  builds, leave the title and recipient logic alone.
- New helper in `backend/src/services/workoutService.ts` to compute today's
  aggregate stats (miles, total duration, best mile-split pace) for a user.
- Tiny format helpers (miles / duration / pace) inline in
  `notificationService.ts`. No new util module unless they get reused.

**Explicitly out of scope**

- The user's own local "Way to go!" notification
  (`app/Mile A Day/Core/Services/MADNotificationService.swift:93`). Not
  changing.
- The in-app `GoalCompletedCelebrationView` sheet. Already has its own
  stats UI.
- The `WorkoutRecapView` live-tracker recap. Already shows distance / time
  / avg pace.
- Backfilling historical `in_app_notifications` rows. They keep their old
  generic body.
- iOS client changes. `NotificationInboxView` renders `notification.body`
  as-is, so the new stats line appears automatically.

## User-visible change

Title (unchanged):

    Alex got their mile in!

Body (before):

    Your friend just completed their daily mile. Time to lace up!

Body (after):

    5.02 mi · 42:13 · best pace 7:54/mi

Same body appears in the push notification and in the in-app notification
inbox row.

## Stat semantics

The notification fires once per day per user, gated atomically by
`workout_completion_notifications` (notificationService.ts:21–28). It is
not tied to a single workout — multiple sub-mile workouts could cumulatively
trip the goal. So stats are computed across **all of today's workouts** for
that user, in the user's local day boundary as already enforced by
`getTodayMiles`.

- **Distance (`miles`)** — sum of `workouts.distance` for today.
- **Time (`durationSeconds`)** — sum of `workouts.total_duration` for
  today.
- **Best pace (`bestSplitPaceSecMi`)** — `MIN(workout_splits.split_pace)`
  across today's workouts, restricted to splits whose `split_distance >=
  0.95` mi. The 0.95 floor avoids reporting a 7-second 0.1-mi sprint as
  a "mile pace." If no qualifying split exists, fall back to the best
  avg pace across today's workouts (`MIN(total_duration /
  NULLIF(distance,0))` where `distance >= 0.95`). If neither is
  available (degenerate case: many tiny workouts), omit the pace
  segment from the body.

## Formatting

| Field    | Format                          | Example       |
|----------|---------------------------------|---------------|
| Distance | `X.XX mi` (two decimals)        | `5.02 mi`     |
| Duration | `M:SS` < 1h, else `H:MM:SS`     | `42:13`, `1:07:42` |
| Pace     | `M:SS/mi`                       | `7:54/mi`     |

Body template:

    {distance} · {duration} · best pace {pace}/mi

If pace is unavailable:

    {distance} · {duration}

Total body length: ~36 chars typical, comfortably under the ~110-char push
truncation point on lock screens.

## Implementation surface

1. **`workoutService.getTodayStats(userId)`** — new exported function.

   Returns:

       {
         miles: number,
         durationSeconds: number,
         bestSplitPaceSecMi: number | null
       }

   Single SQL query joining `workouts` (filtered to today in user's
   timezone, same predicate as `getTodayMiles`) and `workout_splits`. One
   row per user; `bestSplitPaceSecMi` is `MIN(ws.split_pace)` filtered to
   `ws.split_distance >= 0.95`, or `NULL` if no qualifying split.

   The fallback (avg-pace across qualifying workouts when no split-level
   data exists) is computed in the same query as a `COALESCE` of the
   split-min and `MIN(w.total_duration / NULLIF(w.distance,0))` over
   workouts with `distance >= 0.95`.

2. **Format helpers in `notificationService.ts`** (file-local):

       function formatMiles(miles: number): string
       function formatDuration(seconds: number): string
       function formatPace(secondsPerMile: number): string

   Keep them tiny and inline. Promote to a utility module only if a
   second caller appears.

3. **`notifyFriendsOfMileCompletion`** — between line 65 (early return on
   no recipients) and line 67 (title construction):

   - Call `getTodayStats(userId)`. Wrap in try/catch and on failure fall
     back to the existing generic body string, so a stats failure never
     blocks the notification.
   - If `miles > 0`, build the new body using the helpers above.
   - Otherwise (defensive) use the existing generic body.

4. **No iOS changes.**

## Failure modes

- `getTodayStats` throws → log, fall back to original body. Notification
  still goes out.
- `getTodayStats` returns `miles = 0` (shouldn't happen — caller already
  checked `todayMiles >= 1.0`) → fall back to original body.
- `bestSplitPaceSecMi` is `null` → drop the "best pace" segment, keep
  distance and duration.
- Splits table empty for that user → fallback path handles it via
  avg-pace, then degrades to no-pace body.

## Testing

There is no test runner configured in `backend/` (per CLAUDE.md
Gotcha #5). Verification will be manual:

- Run the backend locally with `DATABASE_URL` set.
- Use the existing dev tooling / `/api-test` skill to POST workouts that
  trip the goal for a test user with a friend account.
- Inspect the resulting `in_app_notifications` row to confirm the new body
  format.
- Inspect APNs sandbox push (or `notification_log` row) to confirm the
  same body.
- Edge cases to manually exercise:
  - Single workout > 1 mi with splits → expect distance + duration + best
    pace.
  - Several sub-mile workouts that sum to > 1 mi → expect distance +
    duration, no pace (no qualifying split).
  - Workout without splits (legacy data) → fallback avg-pace path.

## Risks / rollback

- Push body is purely cosmetic; mis-formatting cannot break a user's data.
- Worst case: revert the single commit; behavior returns to current
  generic body.
- No schema changes. No migration.
