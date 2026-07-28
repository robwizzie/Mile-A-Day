# Gotchas

Learned mistakes — things that bit us once and shouldn't bite us again. Grows via `/learn` (post-feature sweep) and `/remember "rule"` (mid-session).

Each entry: one-line rule + brief why.

<!-- Format:
## <Topic>
**Rule**: <one-line actionable rule>
**Why**: <the incident or constraint that produced this rule>
**Source**: <commit hash, PR number, or "session 2026-04-26">
-->

## SwiftUI conditional view identity in presentation closures
**Rule**: Never branch between two initializers of the same view type inside a `fullScreenCover`/`sheet` content closure — compute the differing parameters and create ONE view.
**Why**: `if/else` branches have distinct structural identity. The dashboard's workout cover branched on `InProgressWorkoutStore.load()?.isActive`; when the workout finished and the store cleared, the branch flipped, SwiftUI rebuilt `WorkoutTrackingView` with fresh `@State`, and the post-workout recap was silently replaced by the activity-selection screen.
**Source**: session 2026-06-11

When you correct Claude on something non-obvious, run `/remember "rule"` to add it. After a feature ships, run `/learn` to sweep corrections from the session into here.

## Unified feed is slow in the CTE, not the projection
**Rule**: Do NOT try to speed up `getUnifiedFeed` by stripping columns out of `FEED_ENTRY_PROJECTION`. The heavy columns already sit behind the `LIMIT` barrier (`candidates` unions cheap keys → `page` sorts+limits → outer SELECT projects). The remaining cost is the `candidates` CTE: two large scans UNION ALL'd, a correlated `NOT EXISTS` on `posts p2` per workout row, and two `NOT IN (SELECT uid FROM blocked)` anti-joins. Profile with `EXPLAIN (ANALYZE, BUFFERS)` before changing anything.
**Why**: The projection was replaced with hardcoded `false`/`null` and the feed was still 22s — no speedup, and it shipped to prod with no route maps, no hype/comment counts, no story photos, and (worst) no `COALESCE(roll.distance, wt.distance)`, so multi-segment days under-reported distance (3x0.33 read "0.33 mi"). It also diverged `getUnifiedFeed` from `getFeedEntryForPost`, which shares that projection. `tsc` catches none of this.
**Source**: reverted in 226a340, session 2026-07-27

## Never cache rows that a controller mutates in place
**Rule**: An in-memory cache must return a deep copy, or nothing downstream may mutate the rows. `lockUnearnedPhotos` mutates feed rows in place (`media_url = ""`, `photo_locked = true`); `signMediaUrlsDeep` is safe (it deep-copies and re-signs). Any such cache also needs bounded eviction — a plain `Map` keyed by user id leaks on a live server.
**Why**: A 60s feed cache returned `cached.items` by reference, so the photo-lock mutation stuck: completing your mile mid-TTL still showed blanked photos.
**Source**: reverted in 226a340, session 2026-07-27

## Don't widen statement_timeout to paper over a slow query
**Rule**: If you must change `statement_timeout` per query, use `SET LOCAL` inside a transaction — never `SET` on a pooled client with the reset in a `finally`. `await client.query()` in a `finally` runs on a possibly-faulted connection; if it throws, `client.release()` never runs and the connection leaks. Pool max is 20, so ~20 failures hang every endpoint, not just the slow one.
**Why**: `queryWithExtendedTimeout` did exactly this to give the 22s feed query a 60s rope.
**Source**: reverted in 226a340, session 2026-07-27

## APNs token is nil at launch — don't unregister against it
**Rule**: `MADNotificationService.currentDeviceToken` is only assigned in the `didRegisterForRemoteNotifications` callback, so it is nil anywhere in `AppDelegate`'s launch task. Never compare a stored token against it to decide what to unregister.
**Why**: A DEBUG-only "stale token cleanup" guarded on `oldToken != currentDeviceToken`, which is always true at launch — so it `DELETE`d the user's valid token every dev launch, racing the new registration and making "I never get notifications" worse.
**Source**: reverted in 226a340, session 2026-07-27
