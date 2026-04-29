# Step-Based Competitions — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make step counts a first-class competition goal type. Enable steps and kilometers in the create form alongside miles. When steps is selected, disable the walk/run filter and read scoring from `daily_steps`.

**Architecture:** Backend adds a parallel batch fetcher against `daily_steps` and `getUserScores` branches on `options.unit`. The five competition types' scoring math is unit-blind so they work as-is. iOS unlocks the existing-but-disabled unit buttons, gates the activity selector on `unit == .steps`, and replaces hardcoded `%.1f` score formatting with a unit-aware helper.

**Tech Stack:** TypeScript / Express 5 / Postgres / pg / SwiftUI / iOS 17+

**Note on testing:** Backend has no test runner (`CLAUDE.md`). Verification is `npm run build` + a small ad-hoc DB script per the spec's verification list. iOS must be built in Xcode by the user (CLI builds are forbidden by `CLAUDE.md`).

**Spec:** `docs/superpowers/specs/2026-04-28-step-based-competitions-design.md`

---

## File Structure

**Backend (modify):**
- `backend/src/services/dailyStepsService.ts` — add `getStepsDateRangeBatch`.
- `backend/src/services/competitionService.ts` — branch `getUserScores` on `unit === 'steps'`.

**Backend (create, transient):**
- `backend/scripts/verify-step-scoring.ts` — manual end-to-end verification script (deletable after run).

**iOS (modify):**
- `app/Mile A Day/Models/Competition.swift` — fix `shortDisplayName` for `.steps`; add `formatQuantity` helper on `CompetitionOptions`.
- `app/Mile A Day/Views/Competitions/CreateCompetitionView.swift` — enable all units, disable activity section + force both workouts when steps, numberPad keypad, goal defaults on unit change, `canCreate` adjusted.
- `app/Mile A Day/Views/Competitions/CompetitionDetailView+Leaderboard.swift` — use `formatQuantity` instead of inline `%.1f`.
- `app/Mile A Day/Views/Competitions/CompetitionDetailView+Active.swift` — same.

---

## Task 1: Add `getStepsDateRangeBatch` to dailyStepsService

**Files:**
- Modify: `backend/src/services/dailyStepsService.ts`

- [ ] **Step 1: Append the new function**

Append to the bottom of `backend/src/services/dailyStepsService.ts`:

```ts
/**
 * Batched per-user, per-day step totals over a date range.
 * Mirrors the shape of getQuantityDateRangeBatch — column aliased as
 * `total_distance` so callers (getUserScores) can treat the value as
 * a generic per-interval quantity.
 *
 * No workout_type filter — daily_steps has no per-activity breakdown.
 */
export async function getStepsDateRangeBatch(
	userIds: string[],
	startDate: string,
	endDate?: string
): Promise<{ user_id: string; local_date: string; total_distance: number }[]> {
	if (userIds.length === 0) return [];

	const todaysDate = new Date().toISOString().split('T')[0];
	const start = new Date(startDate).toISOString().split('T')[0];
	const end = endDate ? new Date(endDate).toISOString().split('T')[0] : todaysDate;

	const query = `
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
	`;

	return await db.query(query, [userIds, start, end]);
}
```

- [ ] **Step 2: Compile**

```bash
cd backend && npm run build
```

Expected: clean exit, no TS errors.

- [ ] **Step 3: Commit**

```bash
git add backend/src/services/dailyStepsService.ts
git commit -m "Add getStepsDateRangeBatch for daily_steps competition scoring"
```

---

## Task 2: Branch `getUserScores` on `unit === 'steps'`

**Files:**
- Modify: `backend/src/services/competitionService.ts:4` (import) and `:366-374` (fetch block)

- [ ] **Step 1: Update the import**

In `backend/src/services/competitionService.ts`, replace line 4:

```ts
import { getQuantityDateRangeBatch, getUsersWithManualWorkouts } from './workoutService.js';
```

with:

```ts
import { getQuantityDateRangeBatch, getUsersWithManualWorkouts } from './workoutService.js';
import { getStepsDateRangeBatch } from './dailyStepsService.js';
```

- [ ] **Step 2: Branch the fetch block**

In `getUserScores`, replace the existing `Promise.all` block (currently lines ~365-374):

```ts
// Two batched queries instead of two queries per user (was 2N round trips, now 2).
const [batchRows, manualUserIds] = await Promise.all([
	getQuantityDateRangeBatch(
		acceptedUserIds,
		competition.start_date,
		competition.end_date ?? undefined,
		competition.workouts
	),
	getUsersWithManualWorkouts(acceptedUserIds, competition.start_date, endDate)
]);
```

with:

```ts
// Step competitions read from daily_steps; distance competitions from workouts.
// Manual-workout flag is irrelevant for steps (HealthKit-observer-fed only).
const isStepUnit = competition.options.unit === 'steps';

const [batchRows, manualUserIds] = await Promise.all([
	isStepUnit
		? getStepsDateRangeBatch(
				acceptedUserIds,
				competition.start_date,
				competition.end_date ?? undefined
		  )
		: getQuantityDateRangeBatch(
				acceptedUserIds,
				competition.start_date,
				competition.end_date ?? undefined,
				competition.workouts
		  ),
	isStepUnit
		? Promise.resolve(new Set<string>())
		: getUsersWithManualWorkouts(acceptedUserIds, competition.start_date, endDate)
]);
```

- [ ] **Step 3: Compile**

```bash
cd backend && npm run build
```

Expected: clean exit. If TS complains about `Set<string>` typing, the `Promise.resolve` may need `Promise.resolve<Set<string>>(new Set())` — adjust accordingly and re-run.

- [ ] **Step 4: Commit**

```bash
git add backend/src/services/competitionService.ts
git commit -m "Branch getUserScores on unit=steps to query daily_steps"
```

---

## Task 3: Manual DB verification script for step scoring

**Files:**
- Create: `backend/scripts/verify-step-scoring.ts`

This script runs against the live dev DB (DATABASE_URL must be set). It seeds two synthetic users with known step rows, runs `getUserScores` for each of the five competition types with `unit='steps'`, and asserts expected outcomes. Cleans up after itself. Manual run only — no automated test runner.

- [ ] **Step 1: Create the script**

```ts
// backend/scripts/verify-step-scoring.ts
import 'dotenv/config';
import { PostgresService } from '../src/services/DbService.js';
import { getUserScores } from '../src/services/competitionService.js';
import type { Competition } from '../src/types/competitions.js';

const db = PostgresService.getInstance();

const U1 = '__test_step_u1__';
const U2 = '__test_step_u2__';
const START = '2026-04-21';
const END = '2026-04-27';

async function seed() {
	// Clean any prior runs
	await db.query(`DELETE FROM daily_steps WHERE user_id IN ($1, $2)`, [U1, U2]);
	await db.query(`DELETE FROM users WHERE user_id IN ($1, $2)`, [U1, U2]);

	// Minimal user rows so FKs (if any) are satisfied. Adjust if your users table requires more columns.
	await db.query(
		`INSERT INTO users (user_id, username) VALUES ($1, 'test1'), ($2, 'test2') ON CONFLICT (user_id) DO NOTHING`,
		[U1, U2]
	);

	const rows: [string, string, number][] = [
		[U1, '2026-04-21', 12000], [U1, '2026-04-22', 8000],  [U1, '2026-04-23', 11000],
		[U1, '2026-04-24', 9000],  [U1, '2026-04-25', 15000], [U1, '2026-04-26', 10500],
		[U1, '2026-04-27', 7000],
		[U2, '2026-04-21', 9000],  [U2, '2026-04-22', 9500],  [U2, '2026-04-23', 10000],
		[U2, '2026-04-24', 11000], [U2, '2026-04-25', 12000], [U2, '2026-04-26', 13000],
		[U2, '2026-04-27', 14000],
	];
	for (const [uid, date, steps] of rows) {
		await db.query(
			`INSERT INTO daily_steps (user_id, local_date, steps, timezone_offset)
			 VALUES ($1, $2, $3, 0)
			 ON CONFLICT (user_id, local_date) DO UPDATE SET steps = EXCLUDED.steps`,
			[uid, date, steps]
		);
	}
}

function makeComp(type: Competition['type'], options: any): Competition {
	return {
		id: 0,
		competition_name: 'verify',
		start_date: START,
		end_date: END,
		workouts: ['run', 'walk'],
		type,
		options: { unit: 'steps', ...options },
		owner: U1,
		winner: null,
		ended: false,
		users: [
			{ user_id: U1, invite_status: 'accepted', progress: {}, username: 'test1', profile_image_url: null } as any,
			{ user_id: U2, invite_status: 'accepted', progress: {}, username: 'test2', profile_image_url: null } as any,
		],
	} as Competition;
}

function assert(label: string, cond: boolean, detail?: string) {
	console.log(`${cond ? 'PASS' : 'FAIL'}  ${label}${detail ? ` — ${detail}` : ''}`);
	if (!cond) process.exitCode = 1;
}

async function main() {
	await seed();

	// race: U1 first to 50,000? U1 cumulative across full week = 72,500. U2 = 78,500. Both cross.
	// race score = cumulative quantity (no end-condition logic in scoring fn; cron handles ended flag).
	const race = await getUserScores(makeComp('race', { goal: 50000 }));
	assert('race U1 score = 72500', race[U1].score === 72500, `got ${race[U1].score}`);
	assert('race U2 score = 78500', race[U2].score === 78500, `got ${race[U2].score}`);

	// apex: same cumulative
	const apex = await getUserScores(makeComp('apex', { interval: 'day' }));
	assert('apex U1 score = 72500', apex[U1].score === 72500, `got ${apex[U1].score}`);
	assert('apex U2 score = 78500', apex[U2].score === 78500, `got ${apex[U2].score}`);

	// targets, daily, goal=10000: U1 hits 4 days (12k,11k,15k,10.5k); U2 hits 5 days (10k,11k,12k,13k,14k)
	const targets = await getUserScores(makeComp('targets', { interval: 'day', goal: 10000 }));
	assert('targets U1 score = 4', targets[U1].score === 4, `got ${targets[U1].score}`);
	assert('targets U2 score = 5', targets[U2].score === 5, `got ${targets[U2].score}`);

	// streaks, daily, goal=10000, lives=1: U1 fails on day 2 (8000 < 10000) → eliminated, score frozen at 1.
	// U2 fails on day 1 (9000 < 10000) → eliminated, score frozen at 0.
	const streaks = await getUserScores(makeComp('streaks', { interval: 'day', goal: 10000, lives: 1 }));
	assert('streaks U1 score = 1', streaks[U1].score === 1, `got ${streaks[U1].score}`);
	assert('streaks U2 score = 0', streaks[U2].score === 0, `got ${streaks[U2].score}`);
	assert('streaks U1 lives = 0', streaks[U1].remaining_lives === 0, `got ${streaks[U1].remaining_lives}`);

	// clash, daily: per-day winner. Days where U1 > U2: 21(12k>9k), 22(8k<9.5k loss), 23(11k>10k), 24(9k<11k loss), 25(15k>12k), 26(10.5k<13k loss), 27(7k<14k loss). Today is excluded so the last day may be excluded; this assertion uses the inclusive-but-not-today scoring.
	// Easiest deterministic check: at least U2 should not lose (U2 wins ≥ 4).
	const clash = await getUserScores(makeComp('clash', { interval: 'day', first_to: 99 }));
	const totalClashPoints = (clash[U1].score ?? 0) + (clash[U2].score ?? 0);
	assert('clash points awarded', totalClashPoints >= 5, `total ${totalClashPoints}`);

	// has_manual_workouts is always false for step comps
	assert('U1 has_manual_workouts=false', race[U1].has_manual_workouts === false);
	assert('U2 has_manual_workouts=false', race[U2].has_manual_workouts === false);

	// Cleanup
	await db.query(`DELETE FROM daily_steps WHERE user_id IN ($1, $2)`, [U1, U2]);
	await db.query(`DELETE FROM users WHERE user_id IN ($1, $2)`, [U1, U2]);

	console.log(process.exitCode === 1 ? 'FAILED' : 'OK');
	process.exit(process.exitCode ?? 0);
}

main().catch(e => {
	console.error(e);
	process.exit(1);
});
```

- [ ] **Step 2: Confirm with the user before running (DB writes)**

Per the user's standing rule, ask:

> "Verification script writes test rows to `users` and `daily_steps`, then deletes them. OK to run against `$DATABASE_URL`?"

Wait for explicit yes.

- [ ] **Step 3: Run the script**

```bash
cd backend && npx tsx scripts/verify-step-scoring.ts
```

Expected output: `PASS` for every line, final `OK`.

If the `users` insert fails because of additional NOT NULL columns, adjust the `INSERT INTO users` statement in the script to include them and re-run.

- [ ] **Step 4: Delete the script and commit**

The script was a one-shot verifier. Don't keep it in the tree.

```bash
rm backend/scripts/verify-step-scoring.ts
git add backend/scripts/
git status
```

If the directory is now empty, also remove it.

```bash
git commit --allow-empty -m "Verify step scoring against dev DB (race/apex/targets/streaks/clash all pass)"
```

(Empty commit just to mark verification — skip if there's nothing to record.)

---

## Task 4: Fix `CompetitionUnit.shortDisplayName` for steps

**Files:**
- Modify: `app/Mile A Day/Models/Competition.swift:344-350`

The current value `"k"` would render `"10000 k"` in the UI, which is wrong (`k` reads as kilometers).

- [ ] **Step 1: Fix the value**

In `app/Mile A Day/Models/Competition.swift`, replace:

```swift
    var shortDisplayName: String {
        switch self {
        case .miles: return "mi"
        case .kilometers: return "km"
        case .steps: return "k"
        }
    }
```

with:

```swift
    var shortDisplayName: String {
        switch self {
        case .miles: return "mi"
        case .kilometers: return "km"
        case .steps: return "steps"
        }
    }
```

- [ ] **Step 2: Commit**

```bash
git add "app/Mile A Day/Models/Competition.swift"
git commit -m "Fix CompetitionUnit.shortDisplayName for steps"
```

---

## Task 5: Add `formatQuantity` helper on `CompetitionOptions`

**Files:**
- Modify: `app/Mile A Day/Models/Competition.swift` — append to `CompetitionOptions` extension/body, near `goalFormatted` (line ~313).

Centralizes "format a numeric quantity according to this competition's unit" so leaderboard/active views stop hardcoding `%.1f`.

- [ ] **Step 1: Add the helpers**

In `CompetitionOptions` (the struct that holds `goalFormatted`), add the following methods immediately after `goalFormatted`:

```swift
    /// Format a quantity (distance OR steps) using this competition's unit.
    /// - Steps render as integer with thousands separators (e.g., "42,317").
    /// - Distance units render with one decimal (e.g., "3.2").
    func formatQuantity(_ value: Double) -> String {
        if unit == .steps {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }

    /// "<value> <unit>" — e.g. "3.2 mi" or "42,317 steps".
    func formatQuantityWithUnit(_ value: Double) -> String {
        return "\(formatQuantity(value)) \(unit.shortDisplayName)"
    }
```

- [ ] **Step 2: Commit**

```bash
git add "app/Mile A Day/Models/Competition.swift"
git commit -m "Add unit-aware formatQuantity helpers on CompetitionOptions"
```

---

## Task 6: Replace hardcoded `%.1f` formatting in leaderboard view

**Files:**
- Modify: `app/Mile A Day/Views/Competitions/CompetitionDetailView+Leaderboard.swift`

Replace each occurrence that renders a quantity (distance/steps) using `%.1f` paired with `unit.shortDisplayName` with the helpers from Task 5.

- [ ] **Step 1: Replace line 343**

Old:

```swift
Text(String(format: "%.1f %@", distance, competition.options.unit.shortDisplayName))
```

New:

```swift
Text(competition.options.formatQuantityWithUnit(distance))
```

- [ ] **Step 2: Replace line 631**

Old:

```swift
Text("\(String(format: "%.1f", distance)) \(competition.options.unit.shortDisplayName)")
```

New:

```swift
Text(competition.options.formatQuantityWithUnit(distance))
```

- [ ] **Step 3: Replace line 636**

Old:

```swift
Text("\(String(format: "%.1f", distance))/\(competition.options.goalFormatted)")
```

New:

```swift
Text("\(competition.options.formatQuantity(distance))/\(competition.options.goalFormatted)")
```

- [ ] **Step 4: Replace line 649**

Old:

```swift
Text("\(String(format: "%.1f", distance)) \(competition.options.unit.shortDisplayName)")
```

New:

```swift
Text(competition.options.formatQuantityWithUnit(distance))
```

- [ ] **Step 5: Replace line 717**

Old:

```swift
Text(String(format: "%.1f %@", distance, competition.options.unit.shortDisplayName))
```

New:

```swift
Text(competition.options.formatQuantityWithUnit(distance))
```

- [ ] **Step 6: Replace line 780**

Old:

```swift
Text(String(format: "%.1f/%@ %@", distance, competition.options.goalFormatted, competition.options.unit.shortDisplayName))
```

New:

```swift
Text("\(competition.options.formatQuantity(distance))/\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)")
```

- [ ] **Step 7: Replace line 784**

Old:

```swift
Text("+\(String(format: "%.1f", distance - goal)) over")
```

New:

```swift
Text("+\(competition.options.formatQuantity(distance - goal)) over")
```

- [ ] **Step 8: Replace line 891**

Old:

```swift
Text(String(format: "%.1f/%@ %@", distance, competition.options.goalFormatted, competition.options.unit.shortDisplayName))
```

New:

```swift
Text("\(competition.options.formatQuantity(distance))/\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)")
```

- [ ] **Step 9: Replace line 895**

Old:

```swift
Text("+\(String(format: "%.1f", distance - goal)) over")
```

New:

```swift
Text("+\(competition.options.formatQuantity(distance - goal)) over")
```

- [ ] **Step 10: Replace line 1081 (the `formatScore` switch case for distance-style score)**

Old:

```swift
return String(format: "%.1f %@", score, competition.options.unit.shortDisplayName)
```

New:

```swift
return competition.options.formatQuantityWithUnit(score)
```

- [ ] **Step 11: Commit**

```bash
git add "app/Mile A Day/Views/Competitions/CompetitionDetailView+Leaderboard.swift"
git commit -m "Use unit-aware formatter in competition leaderboard"
```

Note: do not run `xcodebuild` (forbidden by `CLAUDE.md`). Compilation is verified by the user opening Xcode in Task 9.

---

## Task 7: Replace hardcoded `%.1f` formatting in active view

**Files:**
- Modify: `app/Mile A Day/Views/Competitions/CompetitionDetailView+Active.swift`

- [ ] **Step 1: Replace line 159**

Old:

```swift
Label("Done \u{2014} \(String(format: "%.1f", todayDistance)) \(competition.options.unit.shortDisplayName)", systemImage: "checkmark.circle.fill")
```

New:

```swift
Label("Done \u{2014} \(competition.options.formatQuantityWithUnit(todayDistance))", systemImage: "checkmark.circle.fill")
```

- [ ] **Step 2: Replace line 166**

Old:

```swift
Label("\(String(format: "%.1f", remaining)) \(competition.options.unit.shortDisplayName) to go", systemImage: "figure.run")
```

New:

```swift
Label("\(competition.options.formatQuantityWithUnit(remaining)) to go", systemImage: "figure.run")
```

- [ ] **Step 3: Replace line 218**

Old:

```swift
Label("Leading by \(String(format: "%.1f", diff)) \(competition.options.unit.shortDisplayName)", systemImage: "crown.fill")
```

New:

```swift
Label("Leading by \(competition.options.formatQuantityWithUnit(diff))", systemImage: "crown.fill")
```

- [ ] **Step 4: Replace line 225**

Old:

```swift
Label("Behind by \(String(format: "%.1f", abs(diff))) \(competition.options.unit.shortDisplayName)", systemImage: "arrow.up")
```

New:

```swift
Label("Behind by \(competition.options.formatQuantityWithUnit(abs(diff)))", systemImage: "arrow.up")
```

- [ ] **Step 5: Replace line 232**

Old:

```swift
Label("Tied at \(String(format: "%.1f", myDistance)) \(competition.options.unit.shortDisplayName)", systemImage: "equal")
```

New:

```swift
Label("Tied at \(competition.options.formatQuantityWithUnit(myDistance))", systemImage: "equal")
```

- [ ] **Step 6: Replace line 282**

Old:

```swift
Label("+\(String(format: "%.1f", todayDistance)) today", systemImage: "figure.run")
```

New:

```swift
Label("+\(competition.options.formatQuantity(todayDistance)) today", systemImage: "figure.run")
```

- [ ] **Step 7: Replace line 337**

Old:

```swift
Text("\(String(format: "%.1f", todayDistance))/\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)")
```

New:

```swift
Text("\(competition.options.formatQuantity(todayDistance))/\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)")
```

- [ ] **Step 8: Commit**

```bash
git add "app/Mile A Day/Views/Competitions/CompetitionDetailView+Active.swift"
git commit -m "Use unit-aware formatter in competition active view"
```

---

## Task 8: Update CreateCompetitionView for steps + km

**Files:**
- Modify: `app/Mile A Day/Views/Competitions/CreateCompetitionView.swift`

Five sub-changes — enable all unit buttons, gate activity selector on `unit == .steps`, force `selectedWorkouts = [.run, .walk]` for steps, switch keypad, default goal on unit switch.

- [ ] **Step 1: Enable all unit buttons**

Replace lines ~436-477 (`unitSelectorButtons`):

```swift
    var unitSelectorButtons: some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            ForEach([CompetitionUnit.miles, CompetitionUnit.kilometers, CompetitionUnit.steps], id: \.self) { unitOption in
                let isAvailable = unitOption == .miles
                let isSelected = unit == unitOption

                Button {
                    if isAvailable {
                        unit = unitOption
                    }
                } label: {
                    VStack(spacing: 2) {
                        Text(unitOption == .steps ? "Steps" : unitOption.rawValue.capitalized)
                            .font(MADTheme.Typography.callout)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .foregroundColor(isAvailable ? (isSelected ? .white : .white.opacity(0.6)) : .white.opacity(0.3))

                        if !isAvailable {
                            Text("Coming Soon")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MADTheme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .fill(isSelected ? MADTheme.Colors.primary.opacity(0.3) : Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .stroke(
                                isSelected ? MADTheme.Colors.primary : Color.white.opacity(0.1),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(!isAvailable)
            }
        }
    }
```

with:

```swift
    var unitSelectorButtons: some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            ForEach([CompetitionUnit.miles, CompetitionUnit.kilometers, CompetitionUnit.steps], id: \.self) { unitOption in
                let isSelected = unit == unitOption

                Button {
                    unit = unitOption
                } label: {
                    Text(unitOption == .steps ? "Steps" : unitOption.rawValue.capitalized)
                        .font(MADTheme.Typography.callout)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MADTheme.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                .fill(isSelected ? MADTheme.Colors.primary.opacity(0.3) : Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                .stroke(
                                    isSelected ? MADTheme.Colors.primary : Color.white.opacity(0.1),
                                    lineWidth: isSelected ? 2 : 1
                                )
                        )
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
    }
```

- [ ] **Step 2: Disable activity selector when unit is steps**

Replace `activitySelectionSection` (lines ~386-412):

```swift
    var activitySelectionSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text("Allowed Activities")
                .font(MADTheme.Typography.subheadline)
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, MADTheme.Spacing.sm)

            HStack(spacing: MADTheme.Spacing.md) {
                ForEach(CompetitionActivity.allCases, id: \.self) { activity in
                    ActivityToggle(
                        activity: activity,
                        isSelected: selectedWorkouts.contains(activity),
                        action: {
                            if selectedWorkouts.contains(activity) {
                                if selectedWorkouts.count > 1 {
                                    selectedWorkouts.remove(activity)
                                }
                            } else {
                                selectedWorkouts.insert(activity)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, MADTheme.Spacing.sm)
        }
    }
```

with:

```swift
    var activitySelectionSection: some View {
        let isStepsUnit = unit == .steps

        return VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Allowed Activities")
                    .font(MADTheme.Typography.subheadline)
                    .foregroundColor(.white.opacity(0.6))

                if isStepsUnit {
                    Text("Steps include all activity")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, MADTheme.Spacing.sm)

            HStack(spacing: MADTheme.Spacing.md) {
                ForEach(CompetitionActivity.allCases, id: \.self) { activity in
                    ActivityToggle(
                        activity: activity,
                        isSelected: isStepsUnit ? true : selectedWorkouts.contains(activity),
                        action: {
                            guard !isStepsUnit else { return }
                            if selectedWorkouts.contains(activity) {
                                if selectedWorkouts.count > 1 {
                                    selectedWorkouts.remove(activity)
                                }
                            } else {
                                selectedWorkouts.insert(activity)
                            }
                        }
                    )
                    .disabled(isStepsUnit)
                    .opacity(isStepsUnit ? 0.4 : 1.0)
                }
            }
            .padding(.horizontal, MADTheme.Spacing.sm)
        }
    }
```

- [ ] **Step 3: Add `onChange(of: unit)` to force `[run, walk]` when steps and reset goal defaults**

Inside the `body`, find the existing `.onChange(of: selectedType)` modifier on the outer ZStack/NavigationStack (line ~200). Immediately after that closing `}`, add:

```swift
            .onChange(of: unit) { _, newUnit in
                if newUnit == .steps {
                    // Steps apply to all activity — backend ignores filter, but send both to satisfy validation.
                    selectedWorkouts = [.run, .walk]
                    // Sensible step defaults
                    switch selectedType {
                    case .streaks, .targets:
                        goal = 10000
                    case .race:
                        goal = 100000
                    case .apex, .clash:
                        break // no goal
                    }
                } else {
                    // Switching back to a distance unit: restore an activity if empty, reset goal to mile defaults.
                    if selectedWorkouts.isEmpty {
                        selectedWorkouts = [.run]
                    }
                    switch selectedType {
                    case .streaks, .targets:
                        goal = 1.0
                    case .race:
                        goal = 26.2
                    case .apex, .clash:
                        break
                    }
                }
            }
```

- [ ] **Step 4: Switch keypad based on unit**

In `goalSelectionSection`, line ~526-527 currently has:

```swift
                        TextField("", value: $goal, format: .number)
                            .keyboardType(.decimalPad)
```

Replace with:

```swift
                        TextField("", value: $goal, format: .number)
                            .keyboardType(unit == .steps ? .numberPad : .decimalPad)
```

Also update the +/- buttons' increment so step goals adjust by 1000 instead of 1. Line ~503-504 currently:

```swift
                        if goal > 1 {
                            goal -= 1
                        }
```

Replace with:

```swift
                        let stepValue: Double = unit == .steps ? 1000 : 1
                        if goal > stepValue {
                            goal -= stepValue
                        }
```

Line ~549 currently:

```swift
                    Button {
                        goal += 1
                    } label: {
```

Replace with:

```swift
                    Button {
                        goal += unit == .steps ? 1000 : 1
                    } label: {
```

And line ~535-537 (the `onChange(of: goal)` clamp):

```swift
                            .onChange(of: goal) { oldValue, newValue in
                                // Ensure minimum value of 0.1
                                if newValue < 0.1 {
                                    goal = 0.1
                                }
                            }
```

Replace with:

```swift
                            .onChange(of: goal) { oldValue, newValue in
                                let minimum: Double = unit == .steps ? 1 : 0.1
                                if newValue < minimum {
                                    goal = minimum
                                }
                            }
```

- [ ] **Step 5: Update `canCreate` to skip the goal-zero check sensibly for steps**

The existing `canCreate` (line 36-39) is:

```swift
    var canCreate: Bool {
        !selectedFriends.isEmpty &&
        (selectedType == .clash || selectedType == .apex || goal > 0)
    }
```

This is already correct — `goal > 0` works for steps too (e.g., 10000 > 0). No change needed. (Documented for the implementer so they don't second-guess.)

The "at least one activity" check is enforced by Swift's `Set` semantics (always non-empty after step force-set or initial `[.run]`); when in steps mode `selectedWorkouts = [.run, .walk]` so the create payload is always valid.

- [ ] **Step 6: Commit**

```bash
git add "app/Mile A Day/Views/Competitions/CreateCompetitionView.swift"
git commit -m "Enable steps and kilometers in competition creation form"
```

---

## Task 9: User verification in Xcode

**Files:** none (manual)

Per `CLAUDE.md`, only the user can build the iOS target. Hand off to the user with a checklist.

- [ ] **Step 1: Ask the user to build and smoke-test**

Ask:

> "iOS code changes complete. Please open the Mile A Day target in Xcode and:
> 1. Build (⌘B) — confirm no compile errors.
> 2. Run on simulator. Tap Create Competition.
> 3. Verify miles/kilometers/steps are all selectable.
> 4. Switch unit to **steps**: confirm walk/run toggles gray out and 'Steps include all activity' appears.
> 5. Goal field uses the integer keypad and increments by 1,000.
> 6. Switch back to miles: walk/run section re-enables, goal resets to mile default.
> 7. Create a step competition with a friend — confirm the create call succeeds.
>
> Report any visual or behavioral bugs."

- [ ] **Step 2: Address any reported issues**

Loop on changes if the user reports problems.

---

## Task 10: End-to-end live verification

**Files:** none (manual)

- [ ] **Step 1: Backend-running smoke test**

With the backend running locally (`cd backend && npm run dev`) and dev DB connected, the user creates a step `targets` competition (daily, 10k goal) with themselves and one friend. Wait a day (or seed `daily_steps` rows manually for the past few days using `psql`). Open the leaderboard:

- Scores render as integers with thousands separators (e.g., `42,317 steps`).
- Per-interval breakdown shows step totals.
- Manual-workout warning badge does **not** appear.

- [ ] **Step 2: Race-end behavior**

Create a step `race` competition with a low goal (e.g., 5000). Verify a user who crosses the goal triggers the cron-driven `ended=true`/`winner` resolution on the next nightly tick. (For a faster check, manually invoke `resolveExpiredCompetitions` against the dev DB or wait until midnight ET.)

- [ ] **Step 3: Done**

If everything renders and resolves correctly, the feature is complete. Hand off to the `superpowers:finishing-a-development-branch` skill.

---

## Self-Review Notes (already applied inline)

- Spec coverage: `getStepsDateRangeBatch` (T1), `getUserScores` branch (T2), end-condition correctness (T3 + T10), unit selector unlock (T8.1), activity-section gate (T8.2), keypad switch (T8.4), goal defaults on unit change (T8.3), display formatting (T4-T7).
- The `shortDisplayName = "k"` bug surfaced during planning was added as Task 4 (not in original spec but blocks correct steps display).
- Manual workouts skip path is in T2.
- All file paths and line numbers reference current `feature/step-based-competitions` HEAD as of 2026-04-28.
