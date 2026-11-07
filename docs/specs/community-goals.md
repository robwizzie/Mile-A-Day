# Community Goals

Status: approved to build. First goal runs December 1 to 31, 2026.

## Why

Every challenge in Mile A Day today is personal or between friends. Weekly challenges share a theme, but each person sees their own target and their friends' standings. Competitions need someone to set them up. Nothing makes a solo walker feel part of everyone else.

Community Goals give all users one shared target. Each walk moves a shared journey forward, and people who take part earn a limited Flamey item.

**Success measures**

- Share of weekly active users who add at least one mile to the goal
- Day 7 and day 30 retention of goal participants against similar non-participants
- Share of participants who reach the reward minimum
- Opens of the goal screen per participant per week

## The experience

The first goal is **Coast to Coast**, a walk across the United States. The route, target and dates are data, so later goals can be anything.

1. **Dashboard card:** a new optional card shows the journey line, the next checkpoint, and "You added 12.4 mi".
2. **Goal screen:** the journey map, total miles, number of walkers, days left, checkpoints, your contribution, and the reward, and your days toward it.
3. **After a walk:** your contribution updates on the next read. No new celebration is added to the post-walk flow.
4. **Checkpoints:** at set percentages, the app marks a landmark. Each one can show a fun fact.
5. **The finish:** the goal ends on its end date, whether or not the target was reached. Everyone who met the minimum earns the reward either way.
6. **Reward:** a medal that unlocks a Flamey item, shown through the existing badge popup and Closet.

## Rules

| Rule | Decision |
|---|---|
| Who takes part | Every signed-in user, automatically. Showing the card is optional. |
| What counts | Workouts passing `countedWorkoutSql` and `deviceMeasuredWorkoutSql`, credited with `deviceMeasuredDistanceSql`, the same bar competitions use |
| What doesn't | Hand-entered workouts, the typed-over part of an edited distance, vehicle-speed exclusions, deleted or duplicate workouts, step-only days, and token-covered days |
| Length | One calendar month |
| Which days | A workout's `local_date` from `starts_on` through `ends_on` |
| Daily cap | At most 15 miles per person per local day count toward the goal (open question 3) |
| Reward tiers | 5 days: Coast Walker medal. 15 days: Trail Cap. 25 days: Trailblazer Flamey. A day counts once its goal miles reach `STREAK_QUALIFYING_MILES` |
| Community bonus | If the group reaches the target, everyone who walked gets a Streak Assist |
| Behind pace | Under 90% of a steady pace is behind. With 10 or fewer days left, the card and goal screen ask people to invite friends |
| Late syncs | Totals keep counting for 48 hours after `ends_on`, then the reward is granted |
| Reward once earned | Kept for good, even if a workout is deleted later, because it's a limited event |
| Failed goal | Rewards are still granted; only the "goal reached" moment is skipped |
| Plus | Free for everyone, with no Plus bonus |

## Backend

### Data

Migration through Drizzle, additive only.

`community_goals`

- `goal_id` text primary key, `slug` unique
- `title`, `description`
- `target_miles` numeric
- `starts_on`, `ends_on` date
- `checkpoints` jsonb: `[{ "percent": 25, "name": "...", "fact": "..." }]`
- `reward_tiers` jsonb: `[{ "days": 5, "badge_id": "...", "item_id": null, "name": "..." }]`
- `rewards_granted_at` timestamptz, null until granted

`community_goal_totals`

- `goal_id` primary key, references `community_goals`
- `total_miles` numeric, `walkers` integer, `updated_at` timestamptz

Enable row level security on both, matching other new tables.

Per-person miles and days are derived, not stored, so a deleted workout simply stops counting. It reads through `idx_workouts_user_local_date`.

### Service

New `backend/src/services/communityGoalService.ts`:

- `currentGoal()`: the active goal, or the most recently ended one for 7 days after it ends
- `contributionSql(userIdParam)`: the single definition of "what counts", used by every read below
- `refreshTotals(goalId)`: recomputes the total and walker count from workouts, applying the daily cap per user and day
- `grantRewards(goalId)`: inserts the medal into `user_badges` for everyone at the minimum, then sets `rewards_granted_at`

The stored total only ever goes up (`GREATEST(old, new)`), so a deleted account or workout can't move the public number backwards.

### Cron

New `backend/src/cron/communityGoalCron.ts`, run through `runJob`:

- Every 10 minutes while a goal is active or in its 48-hour window: `refreshTotals`
- After the window: `grantRewards` once, guarded by `rewards_granted_at`
- Checkpoint pushes, claimed in a log table so each person gets each one once

The aggregate must be measured with `EXPLAIN ANALYZE` on realistic volume. `idx_workouts_local_date_user_id` should cover it. If not, roll up per user and day instead of adding load to the live pool.

### API

Additive, so shipped apps are unaffected.

`GET /users/:userId/community-goal`, with `requireSelfAccess("userId")`:

```json
{
  "goal": {
    "goal_id": "coast-to-coast-2026",
    "title": "Coast to Coast",
    "description": "...",
    "target_miles": 2800,
    "starts_on": "2026-12-01",
    "ends_on": "2026-12-31",
    "days_left": 12,
    "state": "active",
    "total_miles": 1420.5,
    "walkers": 3120,
    "percent": 51,
    "checkpoints": [{ "percent": 25, "name": "...", "fact": "...", "reached": true }],
    "rewards": [{ "days": 5, "badge_id": "...", "item_id": null, "name": "...", "earned": false }],
    "pace": { "status": "on_track", "miles_per_day_needed": 80, "needs_more_walkers": false }
  },
  "my_miles": 12.4,
  "my_days": 6
}
```

- `goal` is null when nothing is active. The app then hides the card.
- `state` is `upcoming`, `active`, `counting` or `ended`. Clients must treat an unknown value as `ended`.
- The numbers above are placeholders.

### Reward

Use a medal, not a new kind of unlock.

- Add a skin in `backend/flamey-skins` with `"unlock": {"badge": "<badge id>"}`. Skins already support this and need no new `FlameyUnlock` case.
- `owned_item_ids` picks it up from `user_badges` with no ownership changes.
- The medal is seeded in `EXTRA_BADGES`. `refreshBadgesFromServer` then shows the popup, with no new celebration code.
- Item and badge ids must never be renamed.

## iOS

- New `Views/Community/`: `CommunityGoalCard`, `CommunityGoalView`, `CommunityGoalJourney`
- New service using `APIClient.fancyFetch`, gated on `TokenStore.hasTokens` for background callers
- `@Observable` for the new view model. Any new `Codable` field that gets persisted must be Optional.
- Add `communityGoal` to `DashboardCard` and its defaults, and show the same card at the top of Compete, so people who customised their dashboard still see it. It draws nothing when the server returns no goal. Don't add a modifier to `DashboardView.body`. The card observes its own store.
- Distances pass through `DistanceUnits.current`. The stored value stays in miles.
- Check every layout at 320pt, 375pt, 440pt, accessibility sizes, and as a Duo page through `DuoTwoPages`.
- Respect `accessibilityReduceMotion` on the journey animation.

### Notifications

At most 3 per goal per person: start, final week, and result. Mid-goal checkpoints appear in the app only.

- Pushes follow the existing weekly challenge notification setting, with no new toggle
- Declare `ClientFeatures.communityGoalV1` so only supporting builds get the push
- Route the tap through `NotificationDestination.from(type:data:)`
- Honour `shouldSendNotification`, and send at a reasonable hour in the user's local time

## Privacy and App Review

- Show only totals and your own contribution. No other person's name, miles or location appears, so v1 adds no new user-generated content.
- Goal screens never use location or routes. The journey is a drawn line, not anyone's real position.
- Stealth Mode isn't affected, because no location is involved.
- The privacy policy already covers workouts. Confirm whether "combined community totals" should be mentioned.
- Avoid health claims, and use "limited" honestly: if an item returns later, don't call it one-time.
- Use original artwork for the map, with no third-party brands or landmarks' trademarks.
- Medals stay free, so no App Review payment rules apply.

## Testing

- New `backend/scripts/community-goal-check.mjs`, added as a `run:` step in `ci.yml`. It should prove:
  - manual workouts count for nothing and edited ones count the lower figure
  - deleted and excluded workouts drop out
  - dates outside the window don't count, in time zones at both extremes
  - the daily cap applies per person
  - the total never falls
  - rewards are granted exactly once, respect the minimum, include the 48-hour window, and survive a later deletion
  - `GET` is self-only and returns a null goal when nothing is active
- `/api-test` against a local backend
- App: `devBaseURLOverride` against a local backend, seeded for upcoming, active, counting and ended states

## Rollout

1. Ship the backend first, with no goal row. Shipped apps see nothing.
2. Ship the app in a release, with the card hidden while `goal` is null.
3. Wait until enough people have updated (open question 4).
4. Insert the goal row and confirm the first totals against a manual query.
5. Watch the cron's timing and database load for the first 48 hours.

Rollback: end the goal by updating its `ends_on`, after confirming the statement and row count. No deploy is needed.

## Build order

1. Backend: tables, service, read endpoint, cron, CI check
2. iOS: card and goal screen
3. Reward: skin art, medal, grant
4. Notifications
5. Content: route, checkpoints and facts

## Later

- Year in Review slide with your share of the community's miles
- Friends on the same goal
- Team or city contributions, which need their own privacy review
- Personal journeys using the same journey screen

## Open questions

1. **Target:** a good target needs recent real mileage, which wasn't checked for this draft. Use about 80% of expected total miles for the goal's length, so it feels close without being guaranteed. A true coast-to-coast distance may be far too small or too large, so the journey can be scaled or walked more than once.
2. **Reward minimum:** decided as time-based. 15 of 31 days is the starting number, reachable after a slow start but still takes effort.
3. **Daily cap:** 15 miles limits gaming while allowing long days. Are people likely to feel penalised by it?
4. **Launch date:** decided, December 1, 2026. The app must be approved and out before then, and older versions won't show the goal, though their walks still count.
5. **Fun and Modern dashboards:** Flamey only lives on Fun. The card should work on both, but should Modern users see the Flamey reward?
6. **Offline Watch workouts:** do they always reach the server inside the 48-hour window?
