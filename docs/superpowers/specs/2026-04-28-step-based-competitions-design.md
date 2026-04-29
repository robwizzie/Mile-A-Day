# Step-Based Competitions — Design

**Date:** 2026-04-28
**Branch:** `feature/step-based-competitions`
**Status:** Approved for planning

## Goal

Make step counts a first-class goal type in competitions, alongside miles. As a side change, also enable kilometers (currently disabled in the UI but already supported by the underlying distance pipeline).

When a user creates a competition with `unit = steps`, the walk/run activity selector is disabled — daily steps are total-only and apply to all activity.

## Out of Scope

- Timezone correctness for `daily_steps.local_date` (will be addressed separately).
- DB schema changes — `daily_steps` already exists and is fed by the iOS `DailyStepsSyncService`.
- New backend endpoints — daily steps sync endpoint already in production.
- Website / marketing site changes.
- Backfill of existing competitions — they retain their original unit and workouts settings.

## Backend

### New function: `getStepsDateRangeBatch`

Add to `backend/src/services/dailyStepsService.ts`:

```ts
export async function getStepsDateRangeBatch(
  userIds: string[],
  startDate: string,
  endDate?: string
): Promise<{ user_id: string; local_date: string; total_distance: number }[]>
```

Implementation:

```sql
SELECT
  user_id,
  TO_CHAR(local_date, 'YYYY-MM-DD') AS local_date,
  SUM(steps)::int AS total_distance
FROM daily_steps
WHERE user_id = ANY($1::text[])
  AND local_date >= $2
  AND local_date <= $3
GROUP BY user_id, local_date
ORDER BY user_id, local_date ASC
```

Notes:
- Returns `0` rows for users with no step data — `getUserScores` already initializes empty buckets per user.
- Aliasing the column as `total_distance` is intentional: the downstream bucketing code is unit-blind. The name is legacy.
- No `workout_type` filter — daily steps have no per-activity breakdown.

### Branch in `getUserScores`

`backend/src/services/competitionService.ts:367` currently calls `getQuantityDateRangeBatch` unconditionally. Change to:

```ts
const fetchQuantity = competition.options.unit === 'steps'
  ? getStepsDateRangeBatch(acceptedUserIds, competition.start_date, competition.end_date ?? undefined)
  : getQuantityDateRangeBatch(acceptedUserIds, competition.start_date, competition.end_date ?? undefined, competition.workouts);

const [batchRows, manualUserIds] = await Promise.all([
  fetchQuantity,
  competition.options.unit === 'steps'
    ? Promise.resolve(new Set<string>())
    : getUsersWithManualWorkouts(acceptedUserIds, competition.start_date, endDate)
]);
```

`has_manual_workouts` is always `false` for step competitions.

### Goal-completion semantics

The five competition types operate on per-interval buckets (`userData[uid].intervals[intervalKey]`) and their scoring math is unit-blind. They work as-is:

| Type | End / scoring rule | Step-goal behavior |
|---|---|---|
| `race` | `score >= goal` ends the competition; first to cross wins | Cumulative steps; e.g., goal `1_000_000` |
| `streaks` | per-interval check: meet `goal` or lose a life | e.g., daily ≥ 10,000 steps |
| `targets` | per-interval point if interval sum ≥ `goal` | e.g., weekly ≥ 50,000 steps |
| `clash` | per-interval head-to-head winner | per-interval step totals compete |
| `apex` | sum of all intervals at end | total steps over the period |

`resolveExpiredCompetitions` in `competitionCron.ts` is also unit-blind — it consults `getUserScores` output. No additional branching needed there.

### Validation

`competitionController.ts` `checkKeys` already requires `goal` + `unit` for `streaks`/`targets`/`race` and `unit` for `clash`/`apex`. No schema change.

Soft validation: when `unit === 'steps'`, the `workouts` array is functionally ignored. iOS sends `['run','walk']` defensively. The backend should accept any valid value of `workouts` for step competitions and not require special handling.

## iOS

### `CreateCompetitionView.swift`

1. **Enable all units** — remove the `isAvailable = unitOption == .miles` gate at line 439. All three buttons enabled.
2. **Walk/run section disabled when `unit == .steps`**:
   - `activitySelectionSection` renders with grayed-out toggles and helper text "Steps include all activity".
   - `selectedWorkouts` is force-set to `[.run, .walk]` so the create payload satisfies the backend.
   - `canCreate`'s "at least one activity selected" rule is skipped when `unit == .steps`.
3. **Goal defaults on unit change**:
   - On switch to `.steps`: reset goal to a sensible step default — `10_000` for daily-interval types (`streaks`, `targets`); `100_000` for `race`; not applicable for `clash`/`apex`.
   - On switch from `.steps` → `.miles`/`.kilometers`: reset to mile-appropriate defaults (existing behavior).
   - On switch back to a unit that supports walk/run: re-enable the activity section and restore prior `selectedWorkouts` (or default to `[.run]`).
4. **Goal input keypad**: when `unit == .steps`, use `.numberPad` (whole numbers only). For miles/km, use `.decimalPad` (existing).

### Display formatting

`CompetitionOptions.goalFormatted` (`Competition.swift:313`) already returns integer formatting for `.steps`. Verify in `CompetitionDetailView+Leaderboard` and `CompetitionDetailView+Active` that user scores use the same formatter — scores must render as `42,317` not `42317.0`.

### Service / payload

`CompetitionService.createCompetition` doesn't need a signature change — `unit` and `workouts` already exist on `CompetitionOptionsRequest`. The view ensures `workouts = [run, walk]` and `unit = steps` are both set in the request body.

## Verification

For each competition type, the implementation must verify (manually or via test) that with `unit = 'steps'`:
- Score is computed from `daily_steps.steps`, not `workouts.distance`.
- Scoring buckets aggregate correctly per interval.
- End conditions trigger correctly (`race` goal crossing, `streaks` life loss, `targets` weekly threshold counts, `clash` per-interval winners, `apex` summed totals).
- `winner`, `ended`, and `placement` are populated as for mile competitions.
- iOS leaderboard renders integer scores cleanly.

## Risks

- **Mid-competition unit switches** — not allowed; competition options are immutable after creation. No risk.
- **Step data backfill** — competitions starting before users have any `daily_steps` rows will simply show zero scores until data arrives. This matches mile-comp behavior pre-workout.
- **Manual-workout warning UI** — step comps will never set `has_manual_workouts = true`. Acceptable — daily_steps is HealthKit-observer-fed only.
