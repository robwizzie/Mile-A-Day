// CI smoke test: seeds a throwaway Postgres (already migrated by
// dist/db/migrateCli.js) with two friends, workouts, a GPS route and a photo
// post, then runs the REAL feed/story/hype/signing code paths against it.
// Catches the class of outage where migrations, schema and queries drift
// apart — the exact failure mode of the v1.2 feed incident.
//
// Usage: DATABASE_URL=postgres://... node scripts/ci-smoke.mjs
import assert from "node:assert/strict";

const { PostgresService } = await import("../dist/services/DbService.js");
const { uploadWorkouts, getUserRoutes, getRecentWorkouts, getWorkoutRoute } =
  await import("../dist/services/workoutService.js");
const {
  createPost,
  getUnifiedFeed,
  getStoriesRail,
  getUserPosts,
  lockUnearnedPhotos,
} = await import("../dist/services/postService.js");
const { canonicalizeMileContext, logHypeIfUnderLimit, hasHypedMile } =
  await import("../dist/services/hypeService.js");
const { signMediaUrl, verifyPostsMediaAccess, stripMediaQuery } =
  await import("../dist/services/mediaSigningService.js");
const { getNotificationPreferences, updateNotificationPreferences } =
  await import("../dist/services/notificationSettingsService.js");

const db = PostgresService.getInstance();

const ALICE = "ci-alice";
const BOB = "ci-bob";
const localDate = new Date().toISOString().slice(0, 10);
const nowIso = new Date().toISOString();

async function cleanup() {
  // CI always runs on a fresh database; this makes local re-runs work too.
  await db.query(`DELETE FROM hype_log WHERE sender_id LIKE 'ci-%'`);
  // The route-privacy assertions block a user mid-run; a failed run must not
  // leave that block behind to poison the next one.
  await db.query(`DELETE FROM user_blocks WHERE blocker_id LIKE 'ci-%'`);
  await db.query(`DELETE FROM posts WHERE user_id LIKE 'ci-%'`);
  await db.query(
    `DELETE FROM workout_routes WHERE workout_id LIKE 'ci-workout-%'`,
  );
  await db.query(`DELETE FROM workouts WHERE user_id LIKE 'ci-%'`);
}

async function seed() {
  await cleanup();
  for (const [id, name] of [
    [ALICE, "alice"],
    [BOB, "bob"],
  ]) {
    await db.query(
      `INSERT INTO users (user_id, email, apple_sub, username, first_name)
			 VALUES ($1, $2, $3, $4, $5) ON CONFLICT (user_id) DO NOTHING`,
      [id, `${name}@ci.local`, `ci-sub-${name}`, `ci_${name}`, name],
    );
    await db.query(
      `INSERT INTO notification_settings (user_id) VALUES ($1) ON CONFLICT DO NOTHING`,
      [id],
    );
    await db
      .query(
        `INSERT INTO post_terms_acceptance (user_id) VALUES ($1) ON CONFLICT DO NOTHING`,
        [id],
      )
      .catch(() => {}); // table optional — terms gating is controller-level
  }
  for (const [a, b] of [
    [ALICE, BOB],
    [BOB, ALICE],
  ]) {
    await db.query(
      `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, 'accepted')
			 ON CONFLICT (user_id, friend_id) DO NOTHING`,
      [a, b],
    );
  }

  const workout = (id, distance) => ({
    workoutId: id,
    distance,
    localDate,
    date: nowIso,
    timezoneOffset: 0,
    workoutType: "running",
    deviceEndDate: nowIso,
    calories: 100,
    totalDuration: 600,
    source: "healthkit",
    splits: [],
  });

  await uploadWorkouts(ALICE, [workout("ci-workout-alice", 1.1)]);
  await uploadWorkouts(BOB, [
    {
      ...workout("ci-workout-bob", 1.5),
      route: [
        [40.0, -75.0],
        [40.001, -75.001],
        [40.002, -75.002],
      ],
    },
  ]);

  return createPost({
    userId: BOB,
    mediaUrl: "/uploads/posts/ci-bob-photo.jpg",
    caption: "ci smoke",
    workoutId: "ci-workout-bob",
    localDate,
    shareToFeed: true,
    shareToStory: true,
    statsSnapshot: null,
    isAuto: false,
    includeRoute: true,
  });
}

const post = await seed();
assert.ok(post?.post_id, "createPost returned a post row");

// Unified feed as Alice: must include Bob's photo post AND his GPS route.
const feed = await getUnifiedFeed(ALICE, 20, null);
assert.ok(feed.length >= 1, `unified feed has rows (got ${feed.length})`);
const feedPost = feed.find((r) => r.kind === "post" && r.id === post.post_id);
assert.ok(feedPost, "Bob's post is visible in Alice's unified feed");
assert.ok(
  feed.some((r) => r.route != null),
  "route data attached to a feed row (include_route + share_route_maps)",
);

// Stories rail as Alice: Bob's fresh story must appear.
const rail = await getStoriesRail(ALICE);
assert.ok(
  rail.some((g) => g.user_id === BOB),
  "Bob's story shows on Alice's rail",
);

// Bob's profile posts as Alice.
const posts = await getUserPosts(ALICE, BOB, 20, null);
assert.ok(
  posts.some((p) => p.post_id === post.post_id),
  "Bob's post shows on his profile grid",
);

// Heatmap endpoint query.
const routes = await getUserRoutes(BOB);
assert.equal(routes.length, 1, "Bob has one stored route");
assert.equal(routes[0].workout_id, "ci-workout-bob");

// Mile hype: feed workout-card hypes keep the exact workout id so a second
// same-day workout remains hypeable. Legacy notification-style composite keys
// are still normalized to the target user.
const ctx = await canonicalizeMileContext(BOB, {
  contextType: "mile",
  contextId: "ci-workout-bob",
  contextLabel: "mile",
});
assert.equal(ctx.contextId, "ci-workout-bob", "feed mile key stays exact");
const legacyCtx = await canonicalizeMileContext(BOB, {
  contextType: "mile",
  contextId: `${ALICE}:${localDate}`,
  contextLabel: "mile",
});
assert.equal(
  legacyCtx.contextId,
  `${BOB}:${localDate}`,
  "legacy mile key canonicalized",
);
const hype = await logHypeIfUnderLimit(ALICE, BOB, ctx);
assert.ok(hype?.id, "hype logged");
assert.equal(await hasHypedMile(ALICE, BOB, ctx.contextId), true);
const feedAfterHype = await getUnifiedFeed(ALICE, 20, null);
assert.ok(feedAfterHype.length >= 1, "feed still reads after hype");
const hypedFeedPost = feedAfterHype.find(
  (r) => r.kind === "post" && r.id === post.post_id,
);
assert.equal(
  hypedFeedPost?.is_hyped,
  true,
  "exact workout hype marks post hyped",
);

// Signed media urls: sign, verify via the real middleware, and reject tampering.
process.env.MEDIA_SIGNING_SECRET ||= "ci-signing-secret";
const signed = signMediaUrl("/uploads/posts/ci-bob-photo.jpg");
assert.match(signed, /\?e=\d+&s=[0-9a-f]{32}$/, "signed url shape");
assert.equal(stripMediaQuery(signed), "/uploads/posts/ci-bob-photo.jpg");

function runMiddleware(url) {
  const u = new URL(url, "http://localhost");
  const req = {
    path: u.pathname.replace(/^\/uploads\/posts/, ""),
    query: Object.fromEntries(u.searchParams),
  };
  let status = null;
  let passed = false;
  const res = {
    status: (s) => ({ json: () => (status = s) }),
  };
  verifyPostsMediaAccess(req, res, () => (passed = true));
  return { status, passed };
}
assert.equal(runMiddleware(signed).passed, true, "valid signature passes");
assert.equal(
  runMiddleware(signed.replace(/&s=../, "&s=zz")).status,
  403,
  "tampered signature rejected",
);
assert.equal(
  runMiddleware("/uploads/posts/ci-bob-photo.jpg").status,
  403,
  "unsigned request rejected",
);

// Earn-to-view gate: a viewer who hasn't run yet loses today's PHOTOS and
// nothing else. Both halves matter — leaking a photo breaks the promise, and
// over-flagging hides auto route/stats cards the viewer is meant to swipe.
const openGate = { completed: false, localDate };
const row = (over) => ({
  user_id: BOB,
  local_date: localDate,
  is_auto: false,
  media_url: "/uploads/posts/ci-bob-photo.jpg",
  story_photo_url: null,
  ...over,
});
const gated = lockUnearnedPhotos(
  [
    row({ is_auto: true, media_url: "/uploads/posts/ci-auto-card.jpg" }),
    row({
      is_auto: true,
      media_url: "/uploads/posts/ci-auto-card.jpg",
      story_photo_url: "/uploads/posts/ci-story.jpg",
    }),
    row({}),
    row({ user_id: ALICE }),
    row({ local_date: "2000-01-01" }),
  ],
  ALICE,
  openGate,
);
const [autoOnly, autoWithStory, userPhoto, own, older] = gated;
assert.equal(
  autoOnly.media_url,
  "/uploads/posts/ci-auto-card.jpg",
  "auto card survives the gate",
);
assert.ok(
  !autoOnly.photo_locked,
  "auto card with nothing withheld is NOT flagged locked",
);
assert.equal(
  autoWithStory.story_photo_url,
  null,
  "today's story photo withheld",
);
assert.equal(
  autoWithStory.media_url,
  "/uploads/posts/ci-auto-card.jpg",
  "auto card still swipeable behind a locked story photo",
);
assert.equal(
  autoWithStory.photo_locked,
  true,
  "withheld story photo flags the row",
);
assert.equal(userPhoto.media_url, "", "today's real photo withheld");
assert.equal(userPhoto.photo_locked, true, "withheld photo flags the row");
assert.equal(
  own.media_url,
  "/uploads/posts/ci-bob-photo.jpg",
  "own photo never gated",
);
assert.ok(!own.photo_locked, "own post never flagged");
assert.equal(
  older.media_url,
  "/uploads/posts/ci-bob-photo.jpg",
  "older photo never gated",
);
assert.ok(!older.photo_locked, "older post never flagged");

const earned = lockUnearnedPhotos([row({})], ALICE, {
  completed: true,
  localDate,
});
assert.equal(
  earned[0].media_url,
  "/uploads/posts/ci-bob-photo.jpg",
  "finishing the mile unlocks today's photos",
);
assert.ok(!earned[0].photo_locked, "completed viewer sees no lock");

// Recent workouts carry has_route / has_photo, so a friend's workout row can
// show the same Route/Photo chips the owner sees. Bob's run has a GPS route and
// a real photo post; Alice's has neither.
// Read as ALICE, Bob's friend — the flags are viewer-dependent, so who's
// asking is part of the question.
const bobRecent = await getRecentWorkouts(BOB, 10, ALICE);
assert.equal(bobRecent.length, 1, "Bob has one recent workout");
assert.equal(bobRecent[0].workout_id, "ci-workout-bob");
assert.equal(bobRecent[0].has_route, true, "Bob's run reports its GPS route");
assert.equal(bobRecent[0].has_photo, true, "Bob's run reports its real photo");
assert.equal(bobRecent[0].distance, 1.5, "the workout's own columns survive");

const aliceRecent = await getRecentWorkouts(ALICE, 10, ALICE);
assert.equal(aliceRecent.length, 1, "Alice has one recent workout");
assert.equal(aliceRecent[0].has_route, false, "no route → has_route false");
assert.equal(aliceRecent[0].has_photo, false, "no post → has_photo false");

// An auto route/stats card is NOT a photo — only a deliberate one counts.
await db.query(
  `INSERT INTO posts (user_id, media_url, workout_id, local_date, share_to_feed, share_to_story, is_auto)
	 VALUES ($1, $2, $3, $4, TRUE, FALSE, TRUE)`,
  [ALICE, "/uploads/posts/ci-alice-auto.jpg", "ci-workout-alice", localDate],
);
const aliceAfterAuto = await getRecentWorkouts(ALICE, 10, ALICE);
assert.equal(
  aliceAfterAuto.length,
  1,
  "auto post doesn't duplicate the workout",
);
assert.equal(
  aliceAfterAuto[0].has_photo,
  false,
  "an auto route/stats card must not count as a photo",
);

// A workout with BOTH a feed post and a separate story-only post must still
// yield exactly one row — the guard against the LEFT JOIN multiplying rows.
await db.query(
  `INSERT INTO posts (user_id, media_url, workout_id, local_date, share_to_feed, share_to_story, is_auto)
	 VALUES ($1, $2, $3, $4, FALSE, TRUE, FALSE)`,
  [BOB, "/uploads/posts/ci-bob-story.jpg", "ci-workout-bob", localDate],
);
const bobTwoPosts = await getRecentWorkouts(BOB, 10, ALICE);
assert.equal(bobTwoPosts.length, 1, "two posts on one workout → still one row");
assert.equal(bobTwoPosts[0].has_photo, true);

// The controller passes null when ?limit is absent — LIMIT NULL means "all".
const bobNoLimit = await getRecentWorkouts(BOB, null, ALICE);
assert.equal(bobNoLimit.length, 1, "a null limit returns rows, not zero");

// --- Route privacy. Routes start at people's homes; these are the assertions
// that keep them from leaking. Alice and Bob are accepted friends (seed).
const CI_ROUTE_LEN = 3;

// A friend may see the route, and the owner always may.
assert.equal(
  (await getWorkoutRoute(BOB, "ci-workout-bob", ALICE))?.length,
  CI_ROUTE_LEN,
  "a friend sees the route by default",
);
assert.equal(
  (await getWorkoutRoute(BOB, "ci-workout-bob", BOB))?.length,
  CI_ROUTE_LEN,
  "the owner always sees their own route",
);

// A STRANGER may not — authentication alone is not access.
await db.query(
  `INSERT INTO users (user_id, email, apple_sub, username, first_name)
	 VALUES ($1, $2, $3, $4, $5) ON CONFLICT (user_id) DO NOTHING`,
  [
    "ci-stranger",
    "stranger@ci.local",
    "ci-sub-stranger",
    "ci_stranger",
    "stranger",
  ],
);
assert.equal(
  await getWorkoutRoute(BOB, "ci-workout-bob", "ci-stranger"),
  null,
  "a non-friend gets NO route, however authenticated they are",
);

// A blocked friend may not, in either direction.
await db.query(
  `INSERT INTO user_blocks (blocker_id, blocked_id) VALUES ($1, $2)
	 ON CONFLICT DO NOTHING`,
  [BOB, ALICE],
);
assert.equal(
  await getWorkoutRoute(BOB, "ci-workout-bob", ALICE),
  null,
  "blocking hides the route from the blocked friend",
);
await db.query(`DELETE FROM user_blocks WHERE blocker_id LIKE 'ci-%'`);

// share_route_maps = false hides it from friends, but never from the owner.
await db.query(
  `UPDATE notification_settings SET share_route_maps = FALSE WHERE user_id = $1`,
  [BOB],
);
assert.equal(
  await getWorkoutRoute(BOB, "ci-workout-bob", ALICE),
  null,
  "share_route_maps=false hides the route from friends",
);
assert.equal(
  (await getWorkoutRoute(BOB, "ci-workout-bob", BOB))?.length,
  CI_ROUTE_LEN,
  "share_route_maps=false still shows the owner their own route",
);
// ...and it must not even ADMIT a route exists to anyone else.
assert.equal(
  (await getRecentWorkouts(BOB, 10, ALICE))[0].has_route,
  false,
  "share_route_maps=false hides route EXISTENCE from friends too",
);
assert.equal(
  (await getRecentWorkouts(BOB, 10, BOB))[0].has_route,
  true,
  "share_route_maps=false still reports the route to the owner",
);
// A missing viewer is a stranger, not a free pass.
assert.equal(
  (await getRecentWorkouts(BOB, 10, null))[0].has_route,
  false,
  "no viewer id → fail closed, not open",
);
await db.query(
  `UPDATE notification_settings SET share_route_maps = TRUE WHERE user_id = $1`,
  [BOB],
);
assert.equal(
  (await getRecentWorkouts(BOB, 10, ALICE))[0].has_route,
  true,
  "consent restored → friends see the route again",
);

// A workout id that isn't the named owner's must never resolve.
assert.equal(
  await getWorkoutRoute(ALICE, "ci-workout-bob", ALICE),
  null,
  "a workout id belonging to someone else resolves to nothing",
);

// --- workout_visibility: 'friends' (default) | 'public' | 'private'.
// A setting that doesn't actually gate is worse than no setting, so assert all
// three states on the surfaces they govern.
const setVisibility = (userId, value) =>
  db.query(
    `UPDATE notification_settings SET workout_visibility = $2 WHERE user_id = $1`,
    [userId, value],
  );

// The column ships defaulted to 'friends' — nothing changes for existing users.
const defaultVis = await db.query(
  `SELECT workout_visibility FROM notification_settings WHERE user_id = $1`,
  [BOB],
);
assert.equal(
  defaultVis[0].workout_visibility,
  "friends",
  "workout_visibility defaults to friends",
);

// The CHECK constraint rejects anything else.
await assert.rejects(
  () => setVisibility(BOB, "everyone"),
  "an invalid visibility is rejected by the DB, not silently stored",
);

// 'private': gone from a friend's profile grid, gone from their feed, no route.
await setVisibility(BOB, "private");
assert.equal(
  (await getUserPosts(ALICE, BOB, 24)).length,
  0,
  "private hides the profile grid from friends",
);
assert.equal(
  (await getUnifiedFeed(ALICE, 20)).filter((e) => e.user_id === BOB).length,
  0,
  "private removes the user from friends' feeds",
);
assert.equal(
  await getWorkoutRoute(BOB, "ci-workout-bob", ALICE),
  null,
  "private hides routes from friends",
);
assert.equal(
  (await getRecentWorkouts(BOB, 10, ALICE))[0].has_photo,
  false,
  "private hides photo existence from friends",
);
// ...but never from the owner.
assert.ok(
  (await getUserPosts(BOB, BOB, 24)).length >= 1,
  "private never hides your own posts from you",
);
assert.equal(
  (await getWorkoutRoute(BOB, "ci-workout-bob", BOB))?.length,
  CI_ROUTE_LEN,
  "private never hides your own route from you",
);

// 'public': a stranger may see the profile grid; blocks still win.
await setVisibility(BOB, "public");
assert.ok(
  (await getUserPosts("ci-stranger", BOB, 24)).length >= 1,
  "public lets a non-friend see the profile grid",
);
assert.equal(
  (await getWorkoutRoute(BOB, "ci-workout-bob", "ci-stranger"))?.length,
  CI_ROUTE_LEN,
  "public lets a non-friend see the route",
);
await db.query(
  `INSERT INTO user_blocks (blocker_id, blocked_id) VALUES ($1, $2)
	 ON CONFLICT DO NOTHING`,
  [BOB, "ci-stranger"],
);
assert.equal(
  (await getUserPosts("ci-stranger", BOB, 24)).length,
  0,
  "a block beats 'public'",
);
await db.query(`DELETE FROM user_blocks WHERE blocker_id LIKE 'ci-%'`);

// 'friends' (default): friend yes, stranger no.
await setVisibility(BOB, "friends");
assert.ok(
  (await getUserPosts(ALICE, BOB, 24)).length >= 1,
  "friends lets an accepted friend see the profile grid",
);
assert.equal(
  (await getUserPosts("ci-stranger", BOB, 24)).length,
  0,
  "friends hides the profile grid from a non-friend",
);

// The settings round-trip the app actually uses. updateNotificationPreferences
// silently skips keys it doesn't recognise, so a typo in the field name would
// no-op rather than fail — assert the value really comes back changed.
const afterPut = await updateNotificationPreferences(BOB, {
  workout_visibility: "public",
});
assert.equal(
  afterPut.workout_visibility,
  "public",
  "PUT /notifications/preferences persists workout_visibility",
);
assert.equal(
  (await getNotificationPreferences(BOB)).workout_visibility,
  "public",
  "GET /notifications/preferences reports workout_visibility",
);
// An unrelated update must not disturb it.
await updateNotificationPreferences(BOB, { share_route_maps: true });
assert.equal(
  (await getNotificationPreferences(BOB)).workout_visibility,
  "public",
  "updating another preference leaves visibility alone",
);
await updateNotificationPreferences(BOB, { workout_visibility: "friends" });

console.log("ci-smoke: all assertions passed");
process.exit(0);
