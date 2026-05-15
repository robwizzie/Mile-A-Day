# Mile-completion notification stats — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the friends-facing "X got their mile in!" notification show distance, time, and best mile-split pace in both the APNs push body and the in-app notification inbox row.

**Architecture:** Backend-only. One new service helper aggregates today's workout stats from `workouts` + `workout_splits`. Body string is built in `notifyFriendsOfMileCompletion` using small inline formatters. `sendPush` already persists `title`/`body` to `in_app_notifications` (pushNotificationService.ts:288, 292), so the same body covers both surfaces — no iOS work.

**Tech Stack:** Node.js + TypeScript (ESM), Express 5, PostgreSQL via `pg.Pool` wrapped by `PostgresService`. No backend test runner is configured (`CLAUDE.md` gotcha #5), so verification is manual via curl + DB inspection.

**Spec:** `docs/superpowers/specs/2026-05-14-mile-completion-stats-design.md`

**File map:**
- Modify: `backend/src/services/workoutService.ts` — add `getTodayStats(userId)` near `getTodayMiles` (line ~247).
- Modify: `backend/src/services/notificationService.ts:17-89` — add inline formatters; wire `getTodayStats` + new body string into `notifyFriendsOfMileCompletion`.
- No new files. No iOS changes. No schema changes.

---

### Task 1: Add `getTodayStats` to workoutService

**Files:**
- Modify: `backend/src/services/workoutService.ts` (insert immediately after `getTodayMiles`, which ends around line 247)

**Design notes:**
- Single SQL using the same tz-offset CTE pattern as `getTodayMiles` so "today" matches what gated the notification.
- Joins `workouts` + `workout_splits` with a `LEFT JOIN` so workouts without splits still contribute distance/duration.
- `bestSplitPaceSecMi` is `MIN(ws.split_pace)` over splits with `split_distance >= 0.95`; falls back to `MIN(w.total_duration / NULLIF(w.distance,0))` over today's workouts with `distance >= 0.95`. Falls back to `NULL` when neither is available.

- [ ] **Step 1: Add the function**

Insert the following block in `backend/src/services/workoutService.ts` immediately after the closing `}` of `getTodayMiles` (around line 247, before `export async function getQuantityDateRange`):

```typescript
export interface TodayStats {
	miles: number;
	durationSeconds: number;
	bestSplitPaceSecMi: number | null;
}

/**
 * Aggregate today's workout stats for a user, using the user's local-date
 * predicate (same as getTodayMiles).
 *
 * bestSplitPaceSecMi: MIN split pace (sec/mi) across today's splits where
 * split_distance >= 0.95. Falls back to MIN(total_duration / distance) over
 * today's workouts with distance >= 0.95. NULL if neither is available.
 */
export async function getTodayStats(userId: string): Promise<TodayStats> {
	const query = `
	WITH user_tz AS (
		SELECT COALESCE(
			(SELECT timezone_offset FROM workouts WHERE user_id = $1 ORDER BY device_end_date DESC LIMIT 1),
			0
		) AS tz_offset
	),
	today_workouts AS (
		SELECT w.workout_id, w.distance, w.total_duration
		FROM workouts w, user_tz
		WHERE w.user_id = $1
			AND w.local_date = (NOW() + (user_tz.tz_offset || ' minutes')::interval)::date
	),
	totals AS (
		SELECT
			COALESCE(SUM(distance), 0) AS miles,
			COALESCE(SUM(total_duration), 0) AS duration_seconds
		FROM today_workouts
	),
	split_best AS (
		SELECT MIN(ws.split_pace) AS pace
		FROM today_workouts tw
		JOIN workout_splits ws ON ws.workout_id = tw.workout_id
		WHERE ws.split_distance >= 0.95
	),
	workout_best AS (
		SELECT MIN(total_duration / NULLIF(distance, 0)) AS pace
		FROM today_workouts
		WHERE distance >= 0.95
	)
	SELECT
		t.miles::float8 AS miles,
		t.duration_seconds::float8 AS duration_seconds,
		COALESCE(sb.pace, wb.pace) AS best_split_pace_sec_mi
	FROM totals t
	LEFT JOIN split_best sb ON TRUE
	LEFT JOIN workout_best wb ON TRUE
	`;

	const rows = await db.query<{
		miles: number | string;
		duration_seconds: number | string;
		best_split_pace_sec_mi: number | string | null;
	}>(query, [userId]);

	const row = rows[0];
	const toNum = (v: number | string | null | undefined): number => (v == null ? 0 : typeof v === 'string' ? Number(v) : v);
	const pace = row?.best_split_pace_sec_mi;

	return {
		miles: toNum(row?.miles),
		durationSeconds: toNum(row?.duration_seconds),
		bestSplitPaceSecMi: pace == null ? null : Number(pace)
	};
}
```

- [ ] **Step 2: Verify it type-checks**

Run from the repo root:

```bash
cd backend && npm run build
```

Expected: build succeeds, no TypeScript errors.

- [ ] **Step 3: Sanity-check the SQL with a known user**

Pick a user_id with at least one workout today (use `/db-query` skill or a direct `psql`). The query body in this step is the exact CTE from above — substitute `$1` with the test user_id. Example with `/db-query`:

```sql
WITH user_tz AS (
	SELECT COALESCE(
		(SELECT timezone_offset FROM workouts WHERE user_id = 'TEST_USER_ID' ORDER BY device_end_date DESC LIMIT 1),
		0
	) AS tz_offset
),
today_workouts AS (
	SELECT w.workout_id, w.distance, w.total_duration
	FROM workouts w, user_tz
	WHERE w.user_id = 'TEST_USER_ID'
		AND w.local_date = (NOW() + (user_tz.tz_offset || ' minutes')::interval)::date
),
totals AS (
	SELECT COALESCE(SUM(distance),0) AS miles, COALESCE(SUM(total_duration),0) AS duration_seconds FROM today_workouts
),
split_best AS (
	SELECT MIN(ws.split_pace) AS pace
	FROM today_workouts tw
	JOIN workout_splits ws ON ws.workout_id = tw.workout_id
	WHERE ws.split_distance >= 0.95
),
workout_best AS (
	SELECT MIN(total_duration / NULLIF(distance,0)) AS pace FROM today_workouts WHERE distance >= 0.95
)
SELECT t.miles::float8 AS miles, t.duration_seconds::float8 AS duration_seconds,
       COALESCE(sb.pace, wb.pace) AS best_split_pace_sec_mi
FROM totals t LEFT JOIN split_best sb ON TRUE LEFT JOIN workout_best wb ON TRUE;
```

Expected: one row with `miles >= 0`, `duration_seconds >= 0`, and `best_split_pace_sec_mi` either a number (sec/mi) or `NULL`. Spot-check against `SELECT distance, total_duration FROM workouts WHERE user_id=... AND local_date=...`.

- [ ] **Step 4: Commit**

```bash
git add backend/src/services/workoutService.ts
git commit -m "feat(workouts): add getTodayStats aggregating today's distance, duration, best pace"
```

---

### Task 2: Add format helpers to notificationService

**Files:**
- Modify: `backend/src/services/notificationService.ts` (insert near the top of the file, after the imports and before the `notifyFriendsOfMileCompletion` function)

**Design notes:**
- Three pure functions. File-local. Promote to a util module only if a second caller appears (YAGNI).
- Tested implicitly via the manual notification check in Task 4 (no separate harness).

- [ ] **Step 1: Add the helpers**

In `backend/src/services/notificationService.ts`, insert this block immediately after the `const db = PostgresService.getInstance();` line and before the `// ─── Workout Completion Notifications ──────────────────────────────` comment:

```typescript
// ─── Format helpers (file-local) ───────────────────────────────────

function formatMiles(miles: number): string {
	return `${miles.toFixed(2)} mi`;
}

function formatDuration(seconds: number): string {
	const s = Math.max(0, Math.round(seconds));
	const h = Math.floor(s / 3600);
	const m = Math.floor((s % 3600) / 60);
	const sec = s % 60;
	const pad = (n: number) => n.toString().padStart(2, '0');
	if (h > 0) return `${h}:${pad(m)}:${pad(sec)}`;
	return `${m}:${pad(sec)}`;
}

function formatPace(secondsPerMile: number): string {
	const s = Math.max(0, Math.round(secondsPerMile));
	const m = Math.floor(s / 60);
	const sec = s % 60;
	return `${m}:${sec.toString().padStart(2, '0')}/mi`;
}
```

- [ ] **Step 2: Verify it type-checks**

```bash
cd backend && npm run build
```

Expected: build succeeds.

- [ ] **Step 3: Spot-check formatter output**

These are tiny pure functions and there is no test runner. Verify by adding a temporary one-shot script (do NOT commit) or by spot-checking inline in a node REPL. Examples to confirm by eye:

| Input | Expected |
|-------|----------|
| `formatMiles(5.024)` | `5.02 mi` |
| `formatMiles(1.0)` | `1.00 mi` |
| `formatDuration(2533)` | `42:13` |
| `formatDuration(4062)` | `1:07:42` |
| `formatDuration(59)` | `0:59` |
| `formatPace(474)` | `7:54/mi` |
| `formatPace(420)` | `7:00/mi` |

Optional quick check via node:

```bash
cd backend && node --input-type=module -e "
const fm = (n) => n.toFixed(2) + ' mi';
const fd = (s) => { const x = Math.round(s); const h = Math.floor(x/3600); const m = Math.floor((x%3600)/60); const sec = x%60; const p = n => n.toString().padStart(2,'0'); return h>0 ? h+':'+p(m)+':'+p(sec) : m+':'+p(sec); };
const fp = (s) => { const x = Math.round(s); const m = Math.floor(x/60); const sec = x%60; return m+':'+sec.toString().padStart(2,'0')+'/mi'; };
console.log(fm(5.024), '|', fd(2533), '|', fd(4062), '|', fp(474));
"
```

Expected output: `5.02 mi | 42:13 | 1:07:42 | 7:54/mi`.

- [ ] **Step 4: Commit**

```bash
git add backend/src/services/notificationService.ts
git commit -m "feat(notifications): add inline format helpers for miles/duration/pace"
```

---

### Task 3: Wire stats + helpers into `notifyFriendsOfMileCompletion`

**Files:**
- Modify: `backend/src/services/notificationService.ts:6` (add `getTodayStats` import)
- Modify: `backend/src/services/notificationService.ts:67-68` (replace body construction)

- [ ] **Step 1: Import `getTodayStats`**

Change line 6 of `backend/src/services/notificationService.ts` from:

```typescript
import { getActiveStreak, getTodayMiles } from './workoutService.js';
```

to:

```typescript
import { getActiveStreak, getTodayMiles, getTodayStats } from './workoutService.js';
```

- [ ] **Step 2: Replace body construction**

In `notifyFriendsOfMileCompletion`, the current lines 67–68 are:

```typescript
		const title = `${user.username} got their mile in!`;
		const body = 'Your friend just completed their daily mile. Time to lace up!';
```

Replace with:

```typescript
		const title = `${user.username} got their mile in!`;

		// Build a stat-line body. If stats fail or are degenerate, fall back to
		// the generic body so the notification still goes out.
		const FALLBACK_BODY = 'Your friend just completed their daily mile. Time to lace up!';
		let body = FALLBACK_BODY;
		try {
			const stats = await getTodayStats(userId);
			if (stats.miles > 0) {
				const parts = [formatMiles(stats.miles), formatDuration(stats.durationSeconds)];
				if (stats.bestSplitPaceSecMi != null && stats.bestSplitPaceSecMi > 0) {
					parts.push(`best pace ${formatPace(stats.bestSplitPaceSecMi)}`);
				}
				body = parts.join(' · ');
			}
		} catch (err: any) {
			console.error('[Notifications] Error building mile completion stats body, using fallback:', err.message);
		}
```

- [ ] **Step 3: Type-check**

```bash
cd backend && npm run build
```

Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add backend/src/services/notificationService.ts
git commit -m "feat(notifications): surface distance/time/best pace in mile-completion body"
```

---

### Task 4: Manual end-to-end verification

There is no test runner in `backend/`. Verification is manual using the dev server, the existing API, and direct DB inspection. This task is verification only — no code changes.

**Setup:**

- [ ] **Step 1: Start the backend dev server**

```bash
cd backend && npm run dev
```

Expected: `[server] Listening on …`. Keep this running.

- [ ] **Step 2: Identify a test user with at least one friend**

Use `/db-query` (or `psql`) to find a `user_id` who has at least one accepted friend:

```sql
SELECT u.user_id, u.username,
       (SELECT COUNT(*) FROM friendships f WHERE f.user_id = u.user_id AND f.status = 'accepted') AS friend_count
FROM users u
ORDER BY friend_count DESC
LIMIT 5;
```

Note the chosen `user_id` (call it `RUNNER_ID`) and one of their accepted friends (`FRIEND_ID`). Choose a user safe to test against (or a dedicated dev account).

- [ ] **Step 3: Clear today's notification gate for the runner**

`notifyFriendsOfMileCompletion` short-circuits if already fired today. Clear it for the test:

```sql
DELETE FROM workout_completion_notifications
WHERE user_id = 'RUNNER_ID'
  AND notified_date = (NOW() AT TIME ZONE 'UTC')::date;
```

Also delete any prior in-app notification rows from this test so the new one is easy to spot:

```sql
-- Optional cleanup; only run if you want a clean inbox view
DELETE FROM in_app_notifications
WHERE user_id = 'FRIEND_ID'
  AND type = 'friend_activity'
  AND created_at > NOW() - INTERVAL '1 hour';
```

**Scenario A — single workout > 1 mile with splits (the common case):**

- [ ] **Step 4: Insert a synthetic workout + splits for the runner**

```sql
-- A 5.02 mi workout that took 42:13 with a fastest split of 7:54/mi (474 s)
INSERT INTO workouts (user_id, workout_id, distance, local_date, date, timezone_offset, workout_type, device_end_date, calories, total_duration, source)
VALUES (
  'RUNNER_ID',
  'test-mile-stats-001',
  5.02,
  (NOW())::date,
  NOW(),
  0,
  'running',
  NOW(),
  500,
  2533,
  'manual'
)
ON CONFLICT (workout_id) DO UPDATE
  SET distance = EXCLUDED.distance, total_duration = EXCLUDED.total_duration, local_date = EXCLUDED.local_date;

INSERT INTO workout_splits (workout_id, split_number, split_duration, split_distance, split_pace) VALUES
  ('test-mile-stats-001', 1, 510, 1.00, 510),
  ('test-mile-stats-001', 2, 504, 1.00, 504),
  ('test-mile-stats-001', 3, 474, 1.00, 474),  -- fastest
  ('test-mile-stats-001', 4, 510, 1.00, 510),
  ('test-mile-stats-001', 5, 535, 1.02, 525)
ON CONFLICT (workout_id, split_number) DO UPDATE
  SET split_duration = EXCLUDED.split_duration, split_distance = EXCLUDED.split_distance, split_pace = EXCLUDED.split_pace;
```

- [ ] **Step 5: Trigger the notification via the API**

POST to the workouts endpoint to invoke `uploadWorkouts` (which calls `notifyFriendsOfMileCompletion` after `todayMiles >= 1.0`). Use an empty array — the workout above is already in the DB, the controller's downstream notification path still runs because today's miles is well over 1.

Get an auth token for `RUNNER_ID` (use existing dev tooling or `/api-test`). Then:

```bash
curl -X POST https://mad.mindgoblin.tech/workouts/RUNNER_ID \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '[]'
```

If you're running the local dev server, use `http://localhost:PORT/workouts/RUNNER_ID` instead.

Expected: `200 OK` with `{ "message": "Successfully uploaded workouts.", ... }`. Server logs should show `[Notifications] Sent mile completion to N recipients of RUNNER_USERNAME`.

- [ ] **Step 6: Verify the in-app notification body**

```sql
SELECT title, body, type, data, created_at
FROM in_app_notifications
WHERE user_id = 'FRIEND_ID'
  AND type = 'friend_activity'
ORDER BY created_at DESC
LIMIT 1;
```

Expected:
- `title`: `RUNNER_USERNAME got their mile in!`
- `body`: `5.02 mi · 42:13 · best pace 7:54/mi`
- `data` includes `kind: "mile_completed"`.

- [ ] **Step 7: Verify the push payload (if APNs sandbox is configured)**

If APNs is configured for the dev environment and the friend's account has a registered device token, confirm the push body matches the body above on the friend's device. Otherwise: the `in_app_notifications` row (Step 6) is the canonical proof since `sendPush` writes the exact same `title`/`body` to it.

**Scenario B — no qualifying splits (no split-pace data):**

- [ ] **Step 8: Insert a workout without splits and re-trigger**

```sql
-- Clear today's gate + delete prior synthetic workouts
DELETE FROM workout_completion_notifications WHERE user_id = 'RUNNER_ID' AND notified_date = (NOW() AT TIME ZONE 'UTC')::date;
DELETE FROM workout_splits WHERE workout_id IN ('test-mile-stats-001', 'test-mile-stats-002');
DELETE FROM workouts WHERE workout_id IN ('test-mile-stats-001', 'test-mile-stats-002');

-- A 1.10 mi workout in 9:30 (570 s) with no splits
INSERT INTO workouts (user_id, workout_id, distance, local_date, date, timezone_offset, workout_type, device_end_date, calories, total_duration, source)
VALUES ('RUNNER_ID', 'test-mile-stats-002', 1.10, (NOW())::date, NOW(), 0, 'running', NOW(), 120, 570, 'manual');
```

Re-issue the curl from Step 5, then re-run the SELECT from Step 6.

Expected body: `1.10 mi · 9:30 · best pace 8:38/mi` — `bestSplitPaceSecMi` falls back to `total_duration / distance = 570 / 1.10 = 518 s` → `8:38/mi`.

**Scenario C — only sub-mile workouts (no pace segment):**

- [ ] **Step 9: Insert two 0.6 mi workouts and re-trigger**

```sql
DELETE FROM workout_completion_notifications WHERE user_id = 'RUNNER_ID' AND notified_date = (NOW() AT TIME ZONE 'UTC')::date;
DELETE FROM workouts WHERE workout_id IN ('test-mile-stats-002', 'test-mile-stats-003', 'test-mile-stats-004');

INSERT INTO workouts (user_id, workout_id, distance, local_date, date, timezone_offset, workout_type, device_end_date, calories, total_duration, source) VALUES
  ('RUNNER_ID', 'test-mile-stats-003', 0.60, (NOW())::date, NOW(), 0, 'running', NOW(), 70, 330, 'manual'),
  ('RUNNER_ID', 'test-mile-stats-004', 0.60, (NOW())::date, NOW(), 0, 'running', NOW(), 70, 350, 'manual');
```

Re-issue the curl from Step 5, then re-run the SELECT from Step 6.

Expected body: `1.20 mi · 11:20` (no `best pace` segment — neither split nor workout has `distance >= 0.95`).

**Cleanup:**

- [ ] **Step 10: Remove synthetic test rows**

```sql
DELETE FROM workout_splits WHERE workout_id IN ('test-mile-stats-001', 'test-mile-stats-002', 'test-mile-stats-003', 'test-mile-stats-004');
DELETE FROM workouts WHERE workout_id IN ('test-mile-stats-001', 'test-mile-stats-002', 'test-mile-stats-003', 'test-mile-stats-004');
DELETE FROM workout_completion_notifications WHERE user_id = 'RUNNER_ID' AND notified_date = (NOW() AT TIME ZONE 'UTC')::date;
```

- [ ] **Step 11: Final sanity build**

```bash
cd backend && npm run build
```

Expected: clean build.

No commit for this task — verification only.

---

## Self-Review notes

- Spec requirements mapped to tasks:
  - "Distance / time / best pace in body" → Task 3 body construction.
  - "Aggregate over today's workouts" → Task 1 SQL filtered by today's `local_date`.
  - "Best pace = MIN(split_pace) with split_distance >= 0.95, fall back to MIN(total_duration / distance) where distance >= 0.95, else NULL" → Task 1 `split_best` / `workout_best` CTEs.
  - "Format helpers" → Task 2.
  - "Push and in-app inbox row share body" → no work needed; verified manually in Task 4 Step 6.
  - "Fall back to generic body on failure" → Task 3 try/catch + `if (stats.miles > 0)` guard.
- Type consistency: `getTodayStats` returns `{ miles, durationSeconds, bestSplitPaceSecMi }`; consumers in Task 3 use the exact same names. Formatter signatures match call sites.
- No placeholders. All SQL, all code, all commands are concrete.
