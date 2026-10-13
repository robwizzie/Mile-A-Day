---
paths: backend/**
---

# Backend Conventions
One line per rule. The why, incidents and evidence live in `docs/conventions/backend.md` under the same heading: read it before changing that area, and put any new explanation there, not here. `Check: x-check` = run `backend/scripts/x-check.mjs`.
Details: docs/conventions/backend.md § Backend Conventions
- Keep feed reads bounded: each `UNIFIED_FEED_SQL` arm is a per-owner LATERAL `LIMIT` with the cursor pushed in; hype predicates carry `CONTEXTFUL`; keep `jit = off`. Verify by diffing old vs new output.
- Photo gate `getPostWindowStatus`: `cameraOpen` (10 min) only for live `photo_source`, else `photoOpen`; gate `POST /posts` AND `PATCH {add_to_feed}`; keep `post_window_closed`, `posted_fresh`.
- Serve `moving_seconds` only via `displayMovingSecondsSql` (NULL under 50% of `total_duration`, per leg); iOS mirror `DisplayPace`.
- Weekly `last_week` reads the SERVED row (`final_value`, else fresh `measure()`); never re-pick a past week.
- Goal checks use `DAILY_GOAL_TOLERANCE` (0.95), never `>= 1.0`; `user_daily_challenges` stamps what was SERVED; split-based challenge queries also need `countedWorkoutSql('w')`.
- `sweepCrewPhotoNudges` is library-tier copy, re-checks `photoOpen`, claims `photo_nudge_sent_at` (no default); `BUDDY_GROUP_JSON` miles are derived, never stored.
- `getBuddyHistory`: post ids via `buddySessionPostIds` behind `DIRECT_POST_ACCESS_SQL`; NULL `final_distance_miles` = "not synced". Check: `buddy-history-check`.
- Crew slides via `PUT /posts/:id/crew-photo`; resolve `coauthors[].route` at READ under each owner's `share_route_maps`; `lockUnearnedPhotos` blanks slides. Check: `buddy-group-post-check`.
- One post per walk through every door: guard a declared `buddy_session_id` even without `workout_id`; `linkSessionPosts`; link at `finishParticipation`. Check: `buddy-post-doors-check`.
- `createPost` refuses a 2nd card per walk (`buddyWalkPostForWorkout`, incl. time OVERLAP) as 409 `workout_already_posted` + `reason`/`post_id`/`mine`; exclude by WORKOUT, not author.
- `is_paused` (nullable, no default, unclamped) via `recordProgress`; `last_heard_seconds` is an AGE, never a timestamp. Check: `buddy-live-check`.
- `updateParticipantSettings` moves only `joined`↔`ready`, never rewrites `active`; push the host once. Check: `buddy-ready-check`.
- Keep `JOIN_POLICY_ALLOWS_SQL` and `assertJoinPolicyAllows` in agreement; restricted walks: `join_closed`, `invites_host_only`. Check: `buddy-join-policy-check`.
- `mergeSession` joins via `joinSession`, returns `left_behind`, cancels the source silently with `merged_into`. Check: `buddy-merge-check`.
- `…/invite` for any member/phase; `…/request` parks `'requested'` (no slot; only in `join_requests`, never `participants`); one `JOINABLE_WINDOW_SQL`.
- A join into a running session lands `'active'`; keep `getJoinableFriendSessions` = `friendsOutNow`; cancel releases as `'left'`, never `'finished'`.
- Buddy day = HOST's (`SESSION_LOCAL_DATE_SQL`); `closeSession` runs `linkSyncedWorkouts` first; no-progress sweep CANCELS; `startSessionNow` moves `ends_at`. Check: `buddy-lifecycle-check`.
- Gaps-and-islands: `ORDER BY d DESC` pairs with `d + rn`, ASC with `d - rn`; verify on seeded dates.
- `streak_events.prior_streak` is write-once; user-facing reads re-derive it (`stampedBreakDetail`).
- `workouts.feed_role` is FEED display only, never in `SUM(distance)`; written only by `feedRoleStatements` (advisory lock), after every mutation incl. the OLD local_date.
- Splice `duplicateExclusionStatements` after the upsert, before `feedRoleStatements`; write only NULL `exclusion_reason`; gate on `users.dedupe_since`.
- Streak Assist = recipient token + donor's extra mile, coverage only on accept; targets via `pickTargetDay`; re-check `stampedBreakDetail().bridged`; show `restored_streak`.
- `refundEarnedCoverage` DELETES a run day's `streak_coverage` row; every spend writes `prior_last_used` + `spent_stamp`. Check: `streak-check` §G2.
- Today surfaces read `today_covered` / `fetchTodayCoverage`; never re-derive coverage from `frozen_dates`.
- Streak is STORED: write via `refreshCurrentStreak`, read via `readStoredStreak`/`effectiveStreakSql`; every qualifying mutation awaits `refreshCurrentStreak`. Check: `streak-check`.
- Coauthor switches stay independent (NULL = permissive); reach gate goes INSIDE `collabReachSql`'s non-self arm; `setCoauthorFeedVisibility` writes both shapes.
- `dual_media_url` rides `POST_COLUMNS`, `FEED_ENTRY_PROJECTION`, `MULTI_COAUTHORS_JSON`; validate via `normalizeDualMediaUrl`, write wholesale; lock/sweep/repair it too.
- Grid params absent ⇒ byte-identical output; `userGridWhere` binds by placeholder; covers via `normalizeHighlightCoverImage`. Check: `grid-controls-check`.
- Admin analytics: bounded aggregates + TTL cache; DELTA assertions only; import constants from `streakFeatureService.ts`. Check: `admin-analytics-check`.
- Stealth is a RECORDING rule (`stealth_windows`, sticky `workouts.stealth`): a stealth workout has NO `workout_routes` row; serve `stealth` owner-only.
- Serve routes to non-owners only via `servedRouteFrom(...)`; a cut change ⇒ NULL `privacy_bounds`, bump marker, update `RoutePrivacyTrim`. Check: `route-privacy-check`.
- Resolve `users.referral_detail` against usernames (trim, case-fold, strip `@`); report unmatched separately.
- `profile_banner_url` is written only by `POST /users/:id/banner/upload`; `PATCH /users/:id` can only CLEAR it.
- Flamey gates on `dashboard_style = 'fun'`; `flamey` block friends-only; pokes need both sides Fun; date medals by history (`redateBadges`). Check: `flamey-check`.
- `PUT …/flamey-look` rejects unknown/unowned (`invalid_flamey_look`); `servedFlameyLook` drops revoked items without rewriting. Check: `flamey-closet-check`.
- Flamey names go through `parseDisplayName`; `earned_detail` is one query per badge FAMILY reusing evaluator rules. Check: `flamey-profile-check`.
- Medals judge WHOLE history; `recalibrateBadges` is award-only; > `BADGE_PUSH_BURST_LIMIT` ⇒ one summary push. Check: `badge-recalibrate-check`.
- Rate limits key on `clientIp()`, never `req.ip`; `TRUST_PROXY_HOPS`, never `true`; unknown IP ⇒ skip. Check: `rate-limit-check`.
- Shoes are OWNER-ONLY (only `shoeService` reads them); one rule `shoeActivitySql` (iOS `ShoeActivity.of`); mileage derived. Check: `shoes-check`.
- `/public/users/:username` comes only from `publicProfileService.getPublicProfile`: streak via `effectiveStreakSql` (also `getPublicPostPreview`); `total_miles`/`friend_count`/`medals` null for `workout_visibility = 'private'`. Check: `public-profile-check`.

## Architecture: Routes -> Controllers -> Services
Details: docs/conventions/backend.md § Architecture: Routes -> Controllers -> Services
- `routes/`: thin Routers wiring verbs to controllers + middleware.
- `controllers/`: parse params/body, call services, format responses.
- `services/`: business logic + DB queries; no Express types.
- `services/postService.ts` is a barrel over `services/posts/*`: import via it, re-export new names, keep posts/* acyclic.
- `types/`: domain interfaces.
- `cron/`: scheduled jobs.

## Database
Details: docs/conventions/backend.md § Database
- Get the pool via `PostgresService.getInstance()`.
- Raw parameterized SQL and Drizzle share one pool; new code may use the ORM.
- Connection string comes from `DATABASE_URL`.
- `server.ts` must `import 'dotenv/config'` as its FIRST line.

## Drizzle ORM + Migrations
Details: docs/conventions/backend.md § Drizzle ORM + Migrations
- `src/db/drizzle/schema.ts` is the source of truth (`drizzle.config.ts`).
- ORM keys are camelCase, raw SQL snake_case: don't swap under existing callers.
- Keep date/timestamp columns `mode: 'string'`.
- Edit `schema.ts` → `npm run db:generate` → review; never edit an applied migration; they auto-apply at boot.
- Merged migration branches corrupt `meta/_journal.json`: regenerate one side; `npx drizzle-kit check` must pass.
- Run `scripts/drizzle-baseline.mjs` once per environment.
- After `drizzle-kit pull`, fix defaults, strip default `.op(...)`, add `.js` in `relations.ts`.
- Cast a `$n` used as both INSERT value and operand (`$1::varchar`), and each `INSERT … SELECT` param.
- Never put `timestamptz::text` in URLs; use `URL_SAFE_CURSOR` (iOS: `PostService.queryValueAllowed`).

## Auth Pattern
Details: docs/conventions/backend.md § Auth Pattern
- Public routes mount BEFORE `authenticateToken`; `/dev/*` 403s unless `NODE_ENV=development`.
- Protected routes mount AFTER; `req.userId` comes from the middleware.
- Use `requireSelfAccess('paramName')` for own-resource routes.
- MCP connector (`src/mcp`): who gets in AND which Apple ID is whom come only from env `MCP_ALLOWED_USERS` (+ `role = 'admin'`); `mcp_*` tables `.enableRLS()`; commits need the dry run's `confirm_token`; write role never `pg_write_all_data`; never `query_timeout`, a plain `Cursor` (use `SafeCursor`), or a checked-out client without an `error` listener. Check: `mcp-check`.

## Adding a New Endpoint
Details: docs/conventions/backend.md § Adding a New Endpoint
Service (`services/`) → controller (`controllers/`) → route (`routes/`) → if a new route file, register in `server.ts` (before/after `authenticateToken` per auth needs).

## Daily Challenges
Details: docs/conventions/backend.md § Daily Challenges
- The reminder names the challenge via `challengeForNotification`, never stamping `user_daily_challenges`; a pinned duel outranks it.
- `head_to_head` is scored end-of-day by `h2hChallengeCron`; repeat via `rotationSequence`, never a 2nd catalog row; `recentRivalPenalty` ranks, never filters.
- Live H2H pushes reuse `lead_change` + `challenge_key: 'head_to_head'`, debounced on `lead_notified_state`.
- Rivals pin per day in `h2h_matchups`; never fork `challengeRotation.ts`/`hasH2hRivalCandidates`.

## Competition Resolution
Details: docs/conventions/backend.md § Competition Resolution
- Score a team as ONE entity (`scoreEntities`), never a sum of members; outcomes via `teamAwareOutcome`. Check: `competition-team-scoring-check`.
- Standings recompute LIVE on every read, so stored `end_date` bounds which days count.
- Seed check dates relative to the constant (`beforeCutoff(n)`), never to today.
- Score device-measured miles only (`deviceMeasuredOnly` on all four reads); keep `source='manual'` sticky. Check: `competition-scoring-check`.
- Early resolution sets `end_date` = `lastCompletedIntervalEnd`, never today.

## Hypes & Posts
Details: docs/conventions/backend.md § Hypes & Posts
- 'mile' hypes key on `<userId>:<localDate>`; match via `mileHypeKeyMatchSql`.
- Keep the `express.json` limit at 2mb.
- `posts.is_auto` is tri-state; a user post replaces only an auto post, else 409.
- Wrap `media_url` responses in `signMediaUrlsDeep(...)`; `stripMediaQuery(...)` inputs; store bare paths.
- Others' photos go behind `DIRECT_POST_ACCESS_SQL` (`visiblePostAuthor(s)`) + `lockUnearnedPhotos`.
- One walk = one feed card: resolve the walk via `buddy_session_participants`, never stored links.
- Live auto cards store `media_url = ''`; `AUTO_FLAG_SQL` gates on `live_auto_card_v1`. Check: `live-auto-card-check`.
- Crew session = `CREW_SESSION_SQL`; duel standing via one `standing()`.
- Crew figures read `CREW_WORKOUT_ID_SQL`; `coauthors[].distance_miles` reads the participant row.
- `comment_preview` filters `user_blocks` directly (not the `blocked` CTE); the count doesn't.
- `postCommentMatchSql` is the only "comments of this post" rule, for threads and every count.
- Collabs: hypes authorize on `visiblePostAuthors`, file on `posts.user_id`; use `collabActiveSql`; `coauthorOnProfileSql` is grid-only.
- Every post-shaped read ships `AUTHOR_ROUTE_SQL`, no `is_auto` gate.
- `author_flamey` = `authorFlameySql("u")`, no subquery. Check: `flamey-author-look-check`.
- Mention/comment/collab pushes carry `post_id`; mentions are cap-exempt.
- Coauthors are `'accepted'` at insert; "Remove me" gated on `collabTagV1`.
- Social pushes gate on `shouldSendNotification(..., "hype")`; mention replaces the comment push.
- Gate feed-dependent features with `userHasFeedFeature`.

## Push Notifications
Details: docs/conventions/backend.md § Push Notifications
- Every cron job runs through `runJob(name, fn)`, never a bare try/catch. Check: `cron-runner-check`.
- Last call (`lastCallService`) re-verifies via `refreshCurrentStreak` and SKIPS quiet hours; `streak_last_call` is HIGH_PRIORITY + cap-exempt.
- `daily_reminder` `data.kind` is additive; keep legacy routing.
- Win-back is reminder COPY (`WIN_BACK_DAYS`), never a second push. Check: `win-back-check`.
- Weekly recap: Sunday week (`sundayWeekStartSql`); per-device variant, keep the legacy push; claim in `weekly_recap_log`. Check: `weekly-recap-check`.
- The 18/day cap is for chatter only; addressed-to-you pushes go in `CAP_EXEMPT_TYPES`.
- Pick the APNs host via `device_tokens.environment`, not `APNS_PRODUCTION`.
- Hype banners ring once per pair+context via `hype_notify_log` (`claimFirstHypeNotification`; never delete rows).
- Self-hypes allowed but never notified, badged or listed as received.
- Keep `HYPE_DAILY_ABUSE_CEILING`.
- `ADD COLUMN … DEFAULT now()` stamps old rows: backfill claim columns in the same migration; judge eligibility per USER.
- Only small backfills in migrations (30s boot timeout); big ones and `CREATE INDEX CONCURRENTLY` run post-`listen()`.
- Held pushes flush as a morning briefing (`planBriefing`). Check: `morning-briefing-check`.
- Push `data` values must be strings; inbox previews authorize via `visiblePostPreviews`.
- Gate client-visible changes PER DEVICE (`client_features`, `userSupports`); never reuse a string; env flags are kill switches only.
- Widget refresh = silent `widget_refresh` push, only to `widget_refresh_push_v1` devices with matching `widget_kinds`, one per window. Check: `widget-refresh-check`.
- Every desk PWA push (`pushTo`) must show in the remote's Activity (`boxActivity`): read it from its own table, else add the kind to `LOGGED_KINDS` (`desk_push_log`). Check: `display-check`.

## ESM Reminder
Details: docs/conventions/backend.md § ESM Reminder
All imports MUST end with `.js` extension, e.g. `import { foo } from './services/fooService.js';`
- `getRecentWorkouts` gates on `VIEWER_MAY_SEE_WORKOUT_CONTENT_SQL`; `/friends/list/:userId` is friends+self: empty array, never 403.
- Route `times`/`started_at` share the points' downsample (`sanitizeRoute`) and gates; `started_at` as epoch seconds.
- `checkLeadChanges` ranks ENTITIES (teams in team comps).
- Highlight members are (post, `slide_key`); `highlightMemberWhere` gates on `p.user_id`; `getHighlight` serves the key, never a url.
- `setCrewCaption` is NOT behind the posting window.
- Walkers reach the post via `VIEWER_WAS_ON_THIS_WALK`, driven from `idx_post_coauthors_user`.
- Grid/tagged reads and writes carry a `post_coauthors` arm (`coauthorOnProfileMultiSql`).
- The photo-first gate reads the GRID OWNER's `auto_posts_on_profile`.
- Any table storing an `uploads/posts/` path joins `sweepOrphanedMedia`. Check: `orphan-sweep-check`.
- Rank via `rankCompetitors`/`levelWith` (iOS `Competition.ranked`); checks call `resolveCompetitionIfComplete(id)`.
- `supersedePreGoalWorkoutNotification` gates on `mileIsReachingFriends`; call it from the claimed early return and unconditionally on the edit path. Check: `friend-notification-dedupe-check`.
- One walk = one friend announcement: supersede the pre-goal row, keyed on `completedByWorkoutId`; EXPIRE, never delete.
- Admin Network serves 0.25° cells + counts only, never a point. Check: `admin-network-check`.
