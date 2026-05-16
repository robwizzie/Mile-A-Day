# Streak Attribution by Workout Start Time Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Attribute a workout to the calendar day it started rather than the day it ended, so a run begun before midnight counts toward that day.

**Architecture:** iOS-only change. Five sites derive a workout's calendar day from `workout.endDate`; each switches to `workout.startDate`. The backend is untouched — it groups its streak query by the `local_date` value iOS computes and uploads.

**Tech Stack:** Swift / SwiftUI, HealthKit (`HKWorkout`).

> **No automated test runner exists for the iOS app** (per `CLAUDE.md`). These tasks therefore use code-change + commit steps, with a single manual Xcode verification task at the end. Do not attempt `xcodebuild` from the CLI.

---

### Task 1: Canonical local-date derivation (WorkoutProcessor)

This is the value stored in `WorkoutRecord` and uploaded to the backend as `local_date`, which drives the backend streak query.

**Files:**
- Modify: `app/Mile A Day/Models/WorkoutProcessor.swift:58`

- [ ] **Step 1: Change the day-derivation timestamp**

In `determineLocalDateWithOffset(for:)`, change line 58 from:

```swift
        let deviceDate = workout.endDate
```

to:

```swift
        let deviceDate = workout.startDate
```

No other line in the function changes — every later reference uses the local `deviceDate` variable.

- [ ] **Step 2: Commit**

```bash
git add "app/Mile A Day/Models/WorkoutProcessor.swift"
git commit -m "Attribute workout local date to its start day"
```

---

### Task 2: Device-day grouping helper

`groupWorkoutsByDeviceDay` is used by streak, personal-record, and timezone-aware grouping paths.

**Files:**
- Modify: `app/Mile A Day/Models/HealthKitManager.swift:872`

- [ ] **Step 1: Change the grouping timestamp**

In `groupWorkoutsByDeviceDay(workouts:)`, change line 872 from:

```swift
            let dateComponents = calendar.dateComponents([.year, .month, .day], from: workout.endDate)
```

to:

```swift
            let dateComponents = calendar.dateComponents([.year, .month, .day], from: workout.startDate)
```

- [ ] **Step 2: Commit**

```bash
git add "app/Mile A Day/Models/HealthKitManager.swift"
git commit -m "Group workouts by device day using start time"
```

---

### Task 3: Timezone-aware unusual-hour detection

The unusual-hour heuristic in `groupWorkoutsWithTimezoneAwareness` must detect the hour from the same timestamp now used for day attribution.

**Files:**
- Modify: `app/Mile A Day/Models/HealthKitManager+DataFetching.swift:468,477`

- [ ] **Step 1: Change the unusual-hour source timestamp**

In `groupWorkoutsWithTimezoneAwareness(workouts:)`, change line 468 from:

```swift
                let workoutHour = calendar.component(.hour, from: workout.endDate)
```

to:

```swift
                let workoutHour = calendar.component(.hour, from: workout.startDate)
```

- [ ] **Step 2: Change the timezone-correction base timestamp**

Change line 477 from:

```swift
                        if let correctedDate = calendar.date(byAdding: .hour, value: offset, to: workout.endDate) {
```

to:

```swift
                        if let correctedDate = calendar.date(byAdding: .hour, value: offset, to: workout.startDate) {
```

This keeps the correction consistent: the hour is read and shifted from the same timestamp the day is derived from.

- [ ] **Step 3: Commit**

```bash
git add "app/Mile A Day/Models/HealthKitManager+DataFetching.swift"
git commit -m "Detect timezone-shifted workouts using start time"
```

---

### Task 4: Current-streak day grouping and filtering

Two sites in the streak-stats path bucket workouts by day.

**Files:**
- Modify: `app/Mile A Day/Models/HealthKitManager+StreakCalculation.swift:120,358`

- [ ] **Step 1: Change the streak-stats day grouping**

In `calculateCurrentStreakStats()`, change line 120 from:

```swift
            Calendar.current.startOfDay(for: workout.endDate)
```

to:

```swift
            Calendar.current.startOfDay(for: workout.startDate)
```

- [ ] **Step 2: Change the current-streak day filter**

In `getWorkoutsForCurrentStreak()`, change line 358 from:

```swift
            let workoutDay = calendar.startOfDay(for: workout.endDate)
```

to:

```swift
            let workoutDay = calendar.startOfDay(for: workout.startDate)
```

Leave the surrounding `streakStartDate <= workoutDay <= today` comparison unchanged.

- [ ] **Step 3: Commit**

```bash
git add "app/Mile A Day/Models/HealthKitManager+StreakCalculation.swift"
git commit -m "Bucket current-streak workouts by start day"
```

---

### Task 5: Manual verification in Xcode

No automated tests exist; verify behavior by hand.

- [ ] **Step 1: Build the "Mile A Day" target in Xcode**

Open the project in Xcode and build the main "Mile A Day" target. Expected: build succeeds with no new warnings or errors in the modified files.

- [ ] **Step 2: Verify a midnight-crossing workout**

Using a HealthKit run that starts before midnight and ends after (e.g. 11:59 PM → 12:10 AM), confirm:
- The workout appears on the **start** day in the calendar/streak view.
- It contributes to the streak on the start day.

- [ ] **Step 3: Verify normal workouts are unaffected**

Confirm a same-day daytime workout still counts toward the day it occurred and the streak count is unchanged for ordinary history.

- [ ] **Step 4: Verify no double-shift on boundary workouts**

Confirm a workout starting at 11:59 PM (a normal-enough hour for start-time logic) is not additionally moved by the unusual-hour timezone correction.
