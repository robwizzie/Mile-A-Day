# Streak attribution by workout start time

## Problem

A workout's streak day is currently derived from `workout.endDate`. A run that
starts at 11:59 PM on the 14th and ends at 12:10 AM on the 15th counts toward
the 15th. It should count toward the 14th — the day the user started running.

## Goal

Attribute a workout to the calendar day it **started**, not the day it ended.

## Approach

iOS-only change. Every site where the iOS app derives the *calendar day* a
workout belongs to switches from `workout.endDate` to `workout.startDate`. The
backend needs no changes: it groups its streak query by the `local_date` value
that iOS computes and uploads.

Rejected alternatives:
- Adding a `device_start_date` column to the backend — the server never
  recomputes days itself, so it is unnecessary (YAGNI).
- Splitting a boundary-crossing workout's distance between the two days — the
  whole workout counts toward the start day, matching the requested behavior,
  and HealthKit does not cleanly expose per-minute distance.

## Scope

### Change (`endDate` → `startDate` for day derivation)

1. `WorkoutProcessor.determineLocalDateWithOffset`
   (`app/Mile A Day/Models/WorkoutProcessor.swift`, ~line 58) — the canonical
   `localDate`. This value is stored in `WorkoutRecord`, uploaded to the
   backend as `local_date`, and drives the backend streak query.
2. `groupWorkoutsByDeviceDay`
   (`app/Mile A Day/Models/HealthKitManager.swift`, ~line 872).
3. `groupWorkoutsWithTimezoneAwareness` unusual-hour detection
   (`app/Mile A Day/Models/HealthKitManager+DataFetching.swift`, ~line 468).
4. `calculateCurrentStreakStats` day grouping
   (`app/Mile A Day/Models/HealthKitManager+StreakCalculation.swift`, ~line 119).
5. `getWorkoutsForCurrentStreak` day filter
   (`app/Mile A Day/Models/HealthKitManager+StreakCalculation.swift`, ~line 358).

### Out of scope (intentionally keep `endDate`)

These uses of `endDate` concern *when a workout finished*, not which day it
counts for, and must not change:
- "Latest workout" tracking (`cachedLatestWorkoutDate`).
- Sort descriptors.
- Fastest-mile / pace calculations.

### Backend

No changes. New uploads carry start-time-based `local_date`; the streak query
in `getActiveStreak` already groups by `local_date`.

## Data migration: going forward only

No backfill. Already-stored workouts keep their end-time-based `local_date`.

Known consequence: iOS recomputes its local streak fresh from HealthKit on
every launch, so the iOS-displayed streak reflects start-time attribution for
all history immediately. The backend only updates a workout's `local_date`
when that workout is re-uploaded (`uploadWorkouts` does
`ON CONFLICT ... DO UPDATE SET local_date`). For a user with an old
midnight-crossing workout, the iOS streak and the backend (leaderboard) streak
may briefly disagree until that workout re-syncs. This is accepted and
self-healing.

## Testing

No automated test runner exists for iOS. Verification is manual via Xcode:
- A workout starting before midnight and ending after counts toward the start
  day in the streak and the calendar view.
- A normal same-day workout is unaffected.
- The unusual-hour timezone correction still keys off a consistent timestamp
  (now start time) and does not double-shift boundary workouts.
