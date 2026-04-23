# Badges & Daily Challenges — Backend Design

**Audience:** Backend engineer implementing the server side.
**Status:** Spec / not implemented yet. The iOS side today is entirely local (UserDefaults).
**Goal:** Move the badge + daily-challenge system onto Postgres so state survives reinstalls, syncs across devices, is auditable/anti-cheatable, and — the big one — can power social features (friends viewing each other's medals, daily-challenge completion feed).

---

## 1. Context

The iOS app currently tracks 73 badge templates (streak, miles, pace, daily-distance, special, challenge, hidden) + 7 rotating daily challenges entirely in `UserDefaults`. That works for a single device but is blocking:

- **Cross-device sync** — user logs in on a new phone, history is gone.
- **Social features** — a user should be able to tap a friend and see their medals and whether they finished today's challenge.
- **Server-authoritative anti-cheat** — right now a user could edit local state and fake badges. For anything we want to show to friends, the server must own the evaluation.
- **Workout correlation** — "you earned the Marathon Runner medal on this run" storytelling. Requires per-badge linkage to a `workout_id`.
- **Admin tuning** — changing a challenge rule or adding a new badge shouldn't require an App Store release.

The iOS side has already been refactored behind a `ChallengeServiceProtocol` seam (see `app/Mile A Day/Services/ChallengeService.swift`). A `RemoteChallengeService` can drop in once endpoints exist; views don't need to change.

## 2. Goals / Non-Goals

**Goals**
- All badge + challenge state lives in Postgres, authored by the server.
- Evaluation runs server-side after every workout upload.
- Friends can view each other's badges + today's-challenge completion.
- Each earned badge / completed challenge can be correlated with the workout that triggered it.
- One-time migration of existing local state from devices already in the wild.
- Admin can add/tune badges and challenges without an app release.

**Non-Goals (this round)**
- Leaderboards for badges (may follow).
- Public (non-friend) profile visibility.
- Badge trading / sharing to external platforms.
- Real-time push ("your friend just unlocked X") — covered as a stretch in §10.

## 3. System Overview

```
iOS app ──POST /workouts/:userId/upload──▶ workoutService.uploadWorkouts()
                                             │
                                             ▼
                                          badgeService.evaluateForWorkouts()   ◀── NEW
                                             │  (streak, miles, pace, daily_dist, hidden)
                                             │
                                             ▼
                                          challengeService.evaluateForDay()    ◀── NEW
                                             │  (did this workout complete today's challenge?)
                                             │
                                             ▼
                                          Returns { newlyEarnedBadges, completedChallenges }
                                             │
                                             ▼
                                          pushNotificationService.sendPush(...)
                                             │
                                             ▼
iOS app ──GET /me/badges─────────▶ returns full state (earned + locked catalog)
iOS app ──GET /users/:id/badges──▶ returns a friend's earned badges (privacy-gated)
iOS app ──GET /challenges/today──▶ returns today's challenge for the user
iOS app ──GET /me/challenges─────▶ full challenge completion history + streak
```

**Core principle:** client never POSTs "I earned X". Evaluation is server-side and deterministic, keyed off workouts that the client already sends via the existing `/workouts/:userId/upload` flow.

## 4. Database Schema

All DDL is idempotent. No existing migrations framework in this repo — deploy via manual `psql` run, matching current convention.

### 4.1 `badges` — catalog of every possible badge

```sql
CREATE TABLE IF NOT EXISTS badges (
    badge_id         TEXT PRIMARY KEY,                              -- e.g. 'streak_30', 'challenge_100'
    category         TEXT NOT NULL,                                 -- 'streak' | 'miles' | 'pace' | 'daily_distance' | 'challenge' | 'special' | 'hidden'
    name             TEXT NOT NULL,
    description      TEXT NOT NULL,
    icon             TEXT NOT NULL,                                 -- SF Symbol name (iOS renders)
    rarity           TEXT NOT NULL CHECK (rarity IN ('common','rare','legendary')),
    requirement      NUMERIC,                                       -- numeric threshold (days, miles, pace in min/mi, etc.)
    is_hidden        BOOLEAN NOT NULL DEFAULT FALSE,                -- hidden = not in locked list on client
    sort_order       INTEGER NOT NULL DEFAULT 0,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_badges_category ON badges(category);
```

Seed data (73 rows): see Appendix A.

### 4.2 `user_badges` — what each user has earned

```sql
CREATE TABLE IF NOT EXISTS user_badges (
    id                        BIGSERIAL PRIMARY KEY,
    user_id                   UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    badge_id                  TEXT NOT NULL REFERENCES badges(badge_id) ON DELETE CASCADE,
    earned_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_new                    BOOLEAN NOT NULL DEFAULT TRUE,        -- drives the "trophy.fill" toolbar indicator; cleared when user views Medals
    triggering_workout_id     TEXT REFERENCES workouts(workout_id) ON DELETE SET NULL,
    progress_snapshot         JSONB,                                -- what the stat was when earned: { streak: 30, totalMiles: 142.3, ... }
    UNIQUE (user_id, badge_id)
);

CREATE INDEX IF NOT EXISTS idx_user_badges_user ON user_badges(user_id);
CREATE INDEX IF NOT EXISTS idx_user_badges_user_new ON user_badges(user_id) WHERE is_new = TRUE;
CREATE INDEX IF NOT EXISTS idx_user_badges_workout ON user_badges(triggering_workout_id);
```

Notes:
- `UNIQUE(user_id, badge_id)` — user can never earn the same badge twice. Use `ON CONFLICT DO NOTHING` on insert.
- `triggering_workout_id` is `NULL` for "aggregate" badges (streak counts, lifetime miles at the time the service re-evaluates but we can't pinpoint a single workout). For "workout-linkable" badges (e.g. `daily_marathon`, `pace_7min`), populate it. See §6 inventory for which are which.
- `progress_snapshot` lets the detail view say "Earned on your 30th consecutive day, total miles 142.3".

### 4.3 `daily_challenges` — catalog of challenge templates

```sql
CREATE TABLE IF NOT EXISTS daily_challenges (
    challenge_key    TEXT PRIMARY KEY,                              -- 'beat_your_pace', 'double_down', ...
    title            TEXT NOT NULL,
    description_template TEXT NOT NULL,                             -- may contain {avg_pace} placeholder for pace challenges
    icon             TEXT NOT NULL,
    gradient_start   TEXT NOT NULL,                                 -- hex, for iOS tinting
    gradient_end     TEXT NOT NULL,
    type             TEXT NOT NULL CHECK (type IN ('pace','distance','time','activity','steps')),
    active           BOOLEAN NOT NULL DEFAULT TRUE,
    rotation_index   INTEGER NOT NULL UNIQUE,                        -- 0..N-1; selection = day_of_year % count(active)
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

Seed data (7 rows): see Appendix B.

### 4.4 `user_challenge_completions` — daily completion history

```sql
CREATE TABLE IF NOT EXISTS user_challenge_completions (
    id                        BIGSERIAL PRIMARY KEY,
    user_id                   UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    local_date                DATE NOT NULL,                        -- user's local date, matches workouts.local_date
    challenge_key             TEXT NOT NULL REFERENCES daily_challenges(challenge_key),
    completed_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completing_workout_id     TEXT REFERENCES workouts(workout_id) ON DELETE SET NULL,
    UNIQUE (user_id, local_date)
);

CREATE INDEX IF NOT EXISTS idx_ucc_user ON user_challenge_completions(user_id);
CREATE INDEX IF NOT EXISTS idx_ucc_user_date ON user_challenge_completions(user_id, local_date DESC);
```

Notes:
- One completion per user per day (enforced). The challenge key is captured so "Beat Your Pace on Apr 22" is queryable later even if the rotation changes.
- `completing_workout_id` is the workout whose upload caused the completion to fire. For step challenges this may be the workout closest in time to the step threshold crossing.

## 5. API Contracts

All routes below are protected unless noted. Mount in `server.ts` **after** `app.use(authenticateToken)`. Path structure matches existing conventions (`/workouts/:userId/...`).

### 5.1 Badges

#### `GET /badges/catalog`
Public endpoint (mount before auth). Returns the full badge catalog minus hidden badges. Used by iOS to render the locked-medal grid.
```json
{
  "badges": [
    {
      "badgeId": "streak_30",
      "category": "streak",
      "name": "Monthly Master",
      "description": "30 day streak!",
      "icon": "flame.fill",
      "rarity": "rare",
      "requirement": 30,
      "sortOrder": 7
    }, ...
  ]
}
```
`is_hidden = TRUE` rows are filtered out — they're surprises revealed only when earned.

#### `GET /users/:userId/badges`
Returns a user's earned badges. Accessible by the user themselves or any accepted friend.
- If `req.userId === :userId` → return all earned rows (incl. hidden).
- Else, check `friendships` for accepted relationship. 403 if not friends.

Response:
```json
{
  "userId": "uuid...",
  "badges": [
    {
      "badgeId": "streak_30",
      "name": "Monthly Master",
      "description": "30 day streak!",
      "icon": "flame.fill",
      "rarity": "rare",
      "earnedAt": "2026-03-14T22:03:11Z",
      "isNew": false,
      "triggeringWorkoutId": "uuid...",
      "progressSnapshot": { "streak": 30, "totalMiles": 142.3 }
    }, ...
  ]
}
```

#### `POST /me/badges/mark-viewed`
Clears `is_new = FALSE` for all of the caller's badges. Called by iOS when the user opens `BadgesView`.
Response: `{ "updated": 3 }`

#### `POST /me/badges/import`  *(migration — see §9)*
One-time idempotent batch import of local badges + challenge completions for existing users. Body:
```json
{
  "badges": [{ "badgeId": "streak_30", "earnedAt": "2026-01-01T00:00:00Z" }, ...],
  "challengeCompletions": [{ "localDate": "2026-04-01", "challengeKey": "double_down" }, ...]
}
```
Uses `ON CONFLICT DO NOTHING`. Safe to retry.

### 5.2 Daily Challenges

#### `GET /challenges/today`
Returns today's challenge for the caller (pace descriptions are user-personalized).
```json
{
  "localDate": "2026-04-22",
  "challenge": {
    "key": "beat_your_pace",
    "title": "Beat Your Pace",
    "description": "Run faster than 8:30 min/mi today",
    "icon": "bolt.fill",
    "gradientStart": "#FF9500",
    "gradientEnd": "#FF3B30",
    "type": "pace"
  },
  "progress": 0.6,
  "completed": false,
  "completedAt": null
}
```

#### `GET /me/challenges`
Returns the caller's full completion history + derived stats.
```json
{
  "totalCompleted": 42,
  "currentStreak": 9,
  "completions": [
    {
      "localDate": "2026-04-22",
      "challengeKey": "beat_your_pace",
      "title": "Beat Your Pace",
      "icon": "bolt.fill",
      "completingWorkoutId": "uuid...",
      "completedAt": "2026-04-22T13:12:04Z"
    }, ...
  ]
}
```

#### `GET /users/:userId/challenges/today`
Did my friend finish today? Friend-visibility guarded. Lightweight:
```json
{ "userId": "uuid...", "localDate": "2026-04-22", "completed": true, "challengeKey": "beat_your_pace" }
```

### 5.3 Social feed (stretch)

#### `GET /me/feed/challenges/today`
Returns the caller's accepted friends + their today-completion status. One row per friend. Used for a "friends' daily challenge" strip on the dashboard.

## 6. Server-Side Evaluation Logic

### 6.1 Hook point

`backend/src/services/workoutService.ts` — at the end of `uploadWorkouts()` (after the transaction commits, around line 74), call:

```ts
const results = await evaluateWorkoutRewards(userId, uploadedWorkoutIds);
// results = { newlyEarnedBadges, newChallengeCompletion }
```

Run this **after** `uploadWorkoutsDb` commits so the badge evaluator queries a consistent DB state. Append badge/challenge notifications to the existing notification chain already in `workoutController.ts:38–63`.

### 6.2 Badge evaluation

`badgeService.evaluateForUser(userId, newWorkoutIds)` should:

1. Compute current aggregates from `workouts`:
   - `streak` — longest trailing consecutive-day count where the user has at least one qualifying workout (`distance >= 0.95` per iOS rule).
   - `totalMiles` — `SUM(distance)` across all workouts.
   - `fastestMilePace` — min pace across all `workout_splits.split_pace` (seconds per mile → convert to minutes).
   - `mostMilesInOneDay` — max `SUM(distance) GROUP BY local_date`.
   - `firstWorkoutDate` — earliest `device_end_date`.
2. For each badge in the catalog, check the rule (see Appendix A). If satisfied AND not already in `user_badges`, insert.
3. For workout-linkable badges, set `triggering_workout_id` to the specific workout in `newWorkoutIds` that crossed the threshold (or the most recent qualifying one).
4. Snapshot the aggregates into `progress_snapshot`.

Evaluate **hidden badges last**, and only evaluate those whose predicate references aggregates that just changed (optimization; correctness is fine with "evaluate all every time" for now — costs are tiny).

### 6.3 Challenge evaluation

`challengeService.evaluateForDay(userId, localDate, newWorkoutIds)`:

1. Select today's challenge: `SELECT * FROM daily_challenges WHERE rotation_index = (day_of_year(localDate) % count) AND active`.
2. If a row already exists in `user_challenge_completions` for `(user_id, local_date)`, noop.
3. Evaluate the predicate for today's challenge using that day's workouts + steps (see Appendix B for predicates).
4. If satisfied, INSERT with `completing_workout_id` = the newest workout in `newWorkoutIds` for that `local_date` (or the earliest that satisfies, engineer's choice — document whichever is chosen).
5. After inserting, re-run badge evaluation for the `challenge_*` milestone tier since the completion count just went up.

**Steps input:** iOS already sends `totalDuration`, distances, and workout type — it does NOT send step counts. For `ten_k_steps`, two options:
- **Option A (simpler):** client POSTs a lightweight `steps` field on workout upload (extend the payload). Backend treats it as authoritative for that day.
- **Option B:** add `POST /me/steps/daily` endpoint for the client to report daily step total from HealthKit (idempotent, `(user_id, local_date)` unique).

Recommend Option A — one field on the existing upload payload.

### 6.4 De-dup & idempotency

- Workout uploads are already idempotent (insert `ON CONFLICT (workout_id) DO UPDATE`).
- `user_badges` uses `UNIQUE (user_id, badge_id)` — badge evaluator re-runs are safe.
- `user_challenge_completions` uses `UNIQUE (user_id, local_date)` — re-runs are safe.

## 7. Social Visibility Rules

Reuse the existing `friendships` table. Helper in `friendshipService.ts`:

```ts
async function areFriends(a: string, b: string): Promise<boolean> {
  // returns true iff an accepted row exists in either direction
}
```

Apply in badge/challenge read endpoints:
- Self → always allowed.
- Friend (accepted either direction) → allowed.
- Otherwise → 403.

Future: a `users.privacy_mode` column (`public` | `friends_only`) can override this. Out of scope for v1.

## 8. Notifications

Extend `pushNotificationService` types with:
- `badge_earned` — payload `{ badgeId, name, rarity }`. Fired by badge evaluator when a new row is inserted.
- `friend_badge_earned` — fan-out to each accepted friend when a user earns a rare+ badge. Throttle: max 1 per friend per hour to avoid spam on a multi-badge day.
- `friend_challenge_completed` — fan-out to accepted friends when a user completes today's challenge. Batchable via the existing `flushBatchedNotifications()` 10 AM cron.

## 9. Migration of Existing Local State

Some users have months of local-only badges and challenge history. Don't lose it.

**Strategy:**
1. Ship a new app build that calls `POST /me/badges/import` on first launch after upgrade, with the device's local UserDefaults contents.
2. Endpoint uses `ON CONFLICT DO NOTHING` — a user on multiple devices can safely re-import.
3. After a successful import, iOS sets a `didImportLegacyBadges` flag and never calls it again.
4. Server-side re-evaluation will also catch these retroactively based on workouts, so local import is mostly a safety net for badges whose evaluation can't be reconstructed from workout history (notably: earlier challenge completions where no workout ID is stored).

For fresh installs, server evaluates from workout history on the first sync — no import needed.

## 10. Rollout Plan

**Phase 1 — schema + catalog** (1 day)
- Create 4 tables + indexes.
- Seed `badges` and `daily_challenges` from Appendix A / B.

**Phase 2 — read endpoints** (1 day)
- `GET /badges/catalog`, `GET /users/:userId/badges`, `GET /challenges/today`, `GET /me/challenges`.
- iOS wires `RemoteChallengeService` implementing `ChallengeServiceProtocol`, swaps in at the `ChallengeService.shared` binding. Views unchanged.

**Phase 3 — evaluation** (2–3 days)
- `badgeService.evaluateForUser`, `challengeService.evaluateForDay`, call sites in `workoutService.uploadWorkouts`.
- Backfill: one-off script iterates every user, calls the evaluator once. Populates historical badges from existing workouts table.

**Phase 4 — migration + notifications** (1 day)
- `POST /me/badges/import`.
- Wire `badge_earned` + `friend_challenge_completed` push types.

**Phase 5 — friend views in iOS** (1 day)
- Friend profile medal grid, friend challenge-today indicator.

Keep Phase 1+2 behind a feature flag-ish hack (iOS reads a config endpoint / defaults to local if 404) so you can ship backend in isolation first.

## 11. Open Questions / Decisions for the Engineer

1. **Steps input for `ten_k_steps`** — confirm Option A vs B (§6.3).
2. **Hidden badge exposure** — should `GET /users/:userId/badges` include hidden badges a friend has earned, or only non-hidden? Recommend: included when earned (the whole point of hidden is that earning them is the reveal).
3. **Pace unit** — catalog stores pace in `min/mi` decimals (e.g. `7.0`). Confirm `workout_splits.split_pace` is seconds-per-mile (as iOS encodes). Evaluator: `paceMinutesPerMile = split_pace / 60`.
4. **Timezone for daily rollover** — iOS uses `local_date` already stored on every workout. Use that everywhere; do not derive from `NOW()` in UTC.
5. **Admin UI** — out of scope now. Badges/challenges can be tuned directly in Postgres for v1.

---

## Appendix A — Badge Catalog Seed Data

**Categories:** `streak`, `miles`, `pace`, `daily_distance`, `challenge`, `special`, `hidden`

### Streak badges (23) — earn when `streak >= requirement`
`consistency_3` (3, common, "Getting Started") · `consistency_5` (5, common, "Building Habits") · `streak_7` (7, common, "Week Warrior") · `streak_10` (10, common, "Ten Days Strong") · `streak_14` (14, common, "Fortnight Fighter") · `streak_21` (21, common, "Three Week Champion") · `streak_30` (30, rare, "Monthly Master") · `streak_45` (45, rare, "45 Day Legend") · `streak_50` (50, rare, "Half Century") · `streak_60` (60, common, "Two Month Milestone") · `streak_75` (75, rare, "Consistency King") · `streak_90` (90, common, "Quarter Year Hero") · `streak_100` (100, rare, "Century Club") · `streak_120` (120, common, "Four Month Fury") · `streak_150` (150, rare, "Unstoppable Force") · `streak_180` (180, rare, "Half Year Hero") · `streak_200` (200, rare, "Double Century") · `streak_250` (250, legendary, "Legendary Streak") · `streak_300` (300, common, "300 Club") · `streak_365` (365, legendary, "Year Warrior") · `streak_500` (500, legendary, "Elite Runner") · `streak_730` (730, legendary, "Two Year Titan") · `streak_1000` (1000, legendary, "Immortal")

*Triggering workout:* the workout on the Nth consecutive day (use the most recent workout in the new batch whose `local_date` corresponds to day N).

### Miles badges (12) — earn when `totalMiles >= requirement`
`miles_25/50/100/150/200/250` (common) · `miles_500/750/1000` (rare) · `miles_1500/2000/2500` (legendary)

*Triggering workout:* the workout whose upload caused `SUM(distance)` to cross the threshold.

### Pace badges (8) — earn when any `workout_splits.split_pace` corresponds to `<= requirement` min/mi
`pace_12min/11min/10min/9min` (common) · `pace_8min/7min` (rare) · `pace_6min/5min` (legendary)

*Triggering workout:* the workout containing the qualifying split.

### Daily distance badges (12) — earn when `MAX(SUM(distance) GROUP BY local_date) >= requirement`
`daily_2/3/5/10k/8/10` (common) · `daily_half/15/20` (rare) · `daily_marathon/50k/ultra` (legendary). `daily_10k` requires 6.2, `daily_half` requires 13.1, `daily_marathon` requires 26.2, `daily_50k` requires 31.0, `daily_ultra` requires 50.0.

*Triggering workout:* the workout on the qualifying day; if multiple workouts that day, the one whose completion pushed the day total over the line.

### Challenge badges (6) — earn when `COUNT(user_challenge_completions) >= requirement`
`challenge_1` (1, common) · `challenge_5` (5, common) · `challenge_10` (10, common) · `challenge_25` (25, rare) · `challenge_50` (50, rare) · `challenge_100` (100, legendary)

*Triggering workout:* the `completing_workout_id` of the Nth completion.

### Special badges (2)
- `special_first_mile` — `totalMiles >= 1.0`. Common. Triggering workout = first qualifying workout.
- `special_first_week` — `streak >= 7`. Rare. Aggregate.

### Hidden badges (11) — all legendary, `is_hidden = TRUE`
| badge_id | trigger |
|---|---|
| `hidden_perfect_10` | Any day has `SUM(distance) BETWEEN 10.00 AND 10.09` |
| `hidden_lucky_7` | `streak == 7` AND the day-7 workout has distance `>= 7.0` |
| `hidden_double_trouble` | `totalMiles BETWEEN 22.0 AND 23.0` |
| `hidden_century_double` | `streak >= 100` AND `totalMiles >= 100` |
| `hidden_speed_endurance` | Any split pace `<= 8.0` min/mi AND any day total `>= 5.0` mi |
| `hidden_marathon_pace` | Any day total `>= 26.2` mi AND any split pace `<= 10.0` min/mi |
| `hidden_triple_threat` | `streak >= 30` AND `totalMiles >= 30` AND any day `>= 3.0` mi |
| `hidden_50_50` | `streak >= 50` AND `totalMiles >= 50` |
| `hidden_year_miles` | `totalMiles >= 365` |
| `hidden_thousand_club` | `streak >= 1000` OR `totalMiles >= 1000` |
| `hidden_pace_perfect` | Any split pace `<= 7.0` min/mi AND any day `>= 10.0` mi |

## Appendix B — Daily Challenge Seed Data

Rotation: `day_of_year(local_date) % 7`.

| rotation_index | challenge_key | title | type | description_template | completion predicate |
|---|---|---|---|---|---|
| 0 | `beat_your_pace` | Beat Your Pace | pace | `Run faster than {avg_pace} min/mi today` (where `avg_pace = user.fastest_mile_pace + 0.5`; fallback: "Set a new personal best pace today") | any split on today's workouts has `split_pace / 60 <= user.fastest_mile_pace` (i.e., a new PR) |
| 1 | `double_down` | Double Down | distance | `Run 2+ miles today instead of just 1` | `SUM(distance) WHERE local_date = today >= 2.0` |
| 2 | `early_bird` | Early Bird | time | `Complete your mile before noon` | a qualifying workout (distance >= goal_miles × 0.95) finished with `EXTRACT(HOUR FROM device_end_date AT TIME ZONE user_tz) < 12` |
| 3 | `walk_it_out` | Walk It Out | activity | `Walk your mile today — slow and steady` | `SUM(distance) WHERE local_date=today AND workout_type='walking' >= goal_miles × 0.95` |
| 4 | `speed_round` | Speed Round | pace | `Finish your mile in under 12 minutes` | any split today has `split_pace / 60 <= 12.0` AND `SUM(distance) today >= 1.0` |
| 5 | `bonus_mile` | Bonus Mile | distance | `Run an extra half mile beyond your goal` | `SUM(distance) today >= goal_miles + 0.5` |
| 6 | `ten_k_steps` | 10K Steps | steps | `Hit 10,000 steps alongside your mile` | client-reported daily step total `>= 10,000` |

`goal_miles` lives on `users` (default 1.0). Challenge evaluator needs to read it.

---

## Appendix C — Complete DDL (copy/paste)

```sql
-- 1. badges catalog
CREATE TABLE IF NOT EXISTS badges (
    badge_id     TEXT PRIMARY KEY,
    category     TEXT NOT NULL,
    name         TEXT NOT NULL,
    description  TEXT NOT NULL,
    icon         TEXT NOT NULL,
    rarity       TEXT NOT NULL CHECK (rarity IN ('common','rare','legendary')),
    requirement  NUMERIC,
    is_hidden    BOOLEAN NOT NULL DEFAULT FALSE,
    sort_order   INTEGER NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_badges_category ON badges(category);

-- 2. user-earned badges
CREATE TABLE IF NOT EXISTS user_badges (
    id                     BIGSERIAL PRIMARY KEY,
    user_id                UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    badge_id               TEXT NOT NULL REFERENCES badges(badge_id) ON DELETE CASCADE,
    earned_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_new                 BOOLEAN NOT NULL DEFAULT TRUE,
    triggering_workout_id  TEXT REFERENCES workouts(workout_id) ON DELETE SET NULL,
    progress_snapshot      JSONB,
    UNIQUE (user_id, badge_id)
);
CREATE INDEX IF NOT EXISTS idx_user_badges_user      ON user_badges(user_id);
CREATE INDEX IF NOT EXISTS idx_user_badges_user_new  ON user_badges(user_id) WHERE is_new = TRUE;
CREATE INDEX IF NOT EXISTS idx_user_badges_workout   ON user_badges(triggering_workout_id);

-- 3. challenge catalog
CREATE TABLE IF NOT EXISTS daily_challenges (
    challenge_key         TEXT PRIMARY KEY,
    title                 TEXT NOT NULL,
    description_template  TEXT NOT NULL,
    icon                  TEXT NOT NULL,
    gradient_start        TEXT NOT NULL,
    gradient_end          TEXT NOT NULL,
    type                  TEXT NOT NULL CHECK (type IN ('pace','distance','time','activity','steps')),
    active                BOOLEAN NOT NULL DEFAULT TRUE,
    rotation_index        INTEGER NOT NULL UNIQUE,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. completion history
CREATE TABLE IF NOT EXISTS user_challenge_completions (
    id                     BIGSERIAL PRIMARY KEY,
    user_id                UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    local_date             DATE NOT NULL,
    challenge_key          TEXT NOT NULL REFERENCES daily_challenges(challenge_key),
    completed_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completing_workout_id  TEXT REFERENCES workouts(workout_id) ON DELETE SET NULL,
    UNIQUE (user_id, local_date)
);
CREATE INDEX IF NOT EXISTS idx_ucc_user      ON user_challenge_completions(user_id);
CREATE INDEX IF NOT EXISTS idx_ucc_user_date ON user_challenge_completions(user_id, local_date DESC);
```

## Appendix D — Relevant Existing Backend Files

| File | Why it matters |
|---|---|
| `backend/src/services/workoutService.ts` | `uploadWorkouts()` — hook badge+challenge evaluation at end of function (≈ line 74). |
| `backend/src/controllers/workoutController.ts` | Existing notification chain pattern (lines 38–63) to match when firing badge/challenge pushes. |
| `backend/src/middleware/auth.ts` | `authenticateToken` + `requireSelfAccess('userId')`. Apply `requireSelfAccess` to `/me/...` and accept friend-scope on `/users/:userId/badges`. |
| `backend/src/services/friendshipService.ts` | `getFriends(userId)` + status='accepted' pattern for visibility checks. |
| `backend/src/services/pushNotificationService.ts` | Add `badge_earned`, `friend_badge_earned`, `friend_challenge_completed` types. |
| `backend/src/cron/notificationCron.ts` | Add daily cron (1 AM ET) for cleanup / weekly stats if needed. |
| `backend/src/server.ts` | Mount new routes after `authenticateToken` except `GET /badges/catalog` (before). Import `dotenv/config` is already first line — keep new service imports after. |

## Appendix E — iOS Source References

For reading the current client-side rules while porting:
- `app/Mile A Day/Models/User.swift` — `getLockedBadges()`, `getBadgeName()`, `getBadgeDescription()`, `Badge.rarity` computed prop.
- `app/Mile A Day/Models/UserManager.swift` — `checkForRetroactiveBadges()` at ~line 250–350 (current evaluator we're porting).
- `app/Mile A Day/Models/DailyChallengeCatalog.swift` — `pool()`, `todays(for:)`, `progress(for:...)`.
- `app/Mile A Day/Services/ChallengeService.swift` — protocol the iOS side calls; `RemoteChallengeService` will satisfy it.
- `app/Mile A Day/Services/WorkoutSyncService.swift` — payload shape sent to `POST /workouts/:userId/upload`.

End of doc.
