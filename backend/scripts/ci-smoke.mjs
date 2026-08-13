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
  getFeedEntryForPost,
  getStoriesRail,
  getUserPosts,
  getUserTaggedPosts,
  respondToCoauthorInvite,
  setCoauthorProfileVisibility,
  visiblePostAuthors,
  acceptedCoauthor,
  lockUnearnedPhotos,
} = await import("../dist/services/postService.js");
const { canonicalizeMileContext, logHypeIfUnderLimit, hasHypedMile } =
  await import("../dist/services/hypeService.js");
const { signMediaUrl, verifyPostsMediaAccess, stripMediaQuery } =
  await import("../dist/services/mediaSigningService.js");
const { getNotificationPreferences, updateNotificationPreferences } =
  await import("../dist/services/notificationSettingsService.js");
const { getFriendGhosts } = await import("../dist/services/ghostService.js");
const {
  seedWeeklyChallenges,
  weekWindowForUser,
  serveWeek,
  measure,
  measureBatch,
  getCatalog,
  resolveTarget,
  evaluateWeeklyChallengeForUser,
  getWeeklyLeaderboard,
} = await import("../dist/services/weeklyChallengeService.js");
// Hype authorization is controller-level (it's where the friend/visibility
// gate lives), so the collab assertions below drive the real handlers.
const { sendHype, getContextHypersController } =
  await import("../dist/controllers/hypeController.js");

const db = PostgresService.getInstance();

const ALICE = "ci-alice";
const BOB = "ci-bob";
// Collab-permission witnesses: each is friends with exactly ONE side of the
// collab, so a rule that leaks or over-blocks shows up on one of them.
const CARL = "ci-carl"; // Bob's friend only  (reach via the COAUTHOR)
const DANA = "ci-dana"; // Alice's friend only (reach via the AUTHOR)
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
  // The collab-permission assertions flip users to 'private' mid-run, and the
  // grid-vs-tagged ones flip tags off the grid; a failed run must not leave
  // either behind to poison the next one.
  await db.query(
    `UPDATE notification_settings
		 SET workout_visibility = 'friends', tagged_posts_on_profile = TRUE
		 WHERE user_id LIKE 'ci-%'`,
  );
}

async function seed() {
  await cleanup();
  for (const [id, name] of [
    [ALICE, "alice"],
    [BOB, "bob"],
    [CARL, "carl"],
    [DANA, "dana"],
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
    [BOB, CARL],
    [CARL, BOB],
    [ALICE, DANA],
    [DANA, ALICE],
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
// FRESH is server truth now, visible to OTHER viewers (it used to be a
// client-local badge only the poster saw). Bob's post was created moments
// after his workout reached the backend → the legacy derivation marks it.
assert.equal(
  feedPost.is_fresh,
  true,
  "post created right after its workout arrived reads fresh to other viewers",
);

// The SAME post, opened directly (a push tap, a shared link, a grid tap).
// getFeedEntryForPost shares FEED_ENTRY_PROJECTION with the feed precisely so
// the two render from identical data, and it builds its own `page` CTE to feed
// it — so a column added on one side and not the other silently changes what
// one of them shows. Assert they agree field for field, and that the gate
// still refuses a stranger.
const direct = await getFeedEntryForPost(ALICE, post.post_id);
assert.ok(direct, "post opens directly for a viewer who can see it");
assert.deepEqual(
  { ...direct, cursor: null },
  { ...feedPost, cursor: null },
  "post opened directly matches the same post in the feed, field for field",
);

// --- Fresh-workout hold. A just-synced workout with no post (Alice's) stays
// off FRIENDS' feeds while its 10-minute photo window is open, so a photo
// posted in the window lands together with the route instead of after it.
// The owner keeps seeing their own workout the whole time.
const bobFeedFresh = await getUnifiedFeed(BOB, 20, null);
assert.ok(
  !bobFeedFresh.some((e) => e.kind === "workout" && e.user_id === ALICE),
  "a friend's just-synced workout card is held while its photo window is open",
);
assert.ok(
  (await getUnifiedFeed(ALICE, 20, null)).some(
    (e) => e.kind === "workout" && e.user_id === ALICE,
  ),
  "the owner still sees their own fresh workout immediately",
);
// Age the sync past the window (both columns — GREATEST anchors the hold):
// the card must now appear for friends, and stays visible for the rest of
// this suite exactly as it did before the hold existed.
await db.query(
  `UPDATE workouts
	 SET created_at = created_at - INTERVAL '11 minutes',
		 device_end_date = device_end_date - INTERVAL '11 minutes'
	 WHERE workout_id = 'ci-workout-alice'`,
);
assert.ok(
  (await getUnifiedFeed(BOB, 20, null)).some(
    (e) => e.kind === "workout" && e.user_id === ALICE,
  ),
  "the held card appears for friends once the photo window lapses",
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

// Tagged tab (getUserTaggedPosts): caption @mentions use exact-token matching,
// and a collab invite only counts once ACCEPTED.
const alicePost = (
  caption,
  mediaUrl,
  coauthorUserId = null,
  postedLive = false,
) =>
  createPost({
    userId: ALICE,
    mediaUrl,
    caption,
    workoutId: null,
    localDate,
    shareToFeed: true,
    shareToStory: false,
    statsSnapshot: null,
    isAuto: false,
    includeRoute: false,
    coauthorUserId,
    postedLive,
  });
const mentionPost = await alicePost(
  "post-run coffee with @ci_bob",
  "/uploads/posts/ci-alice-mention.jpg",
);
const superstringPost = await alicePost(
  "shoutout @ci_bobber",
  "/uploads/posts/ci-alice-superstring.jpg",
);
const collabPost = await alicePost(
  "ran it together",
  "/uploads/posts/ci-alice-collab.jpg",
  BOB,
  true, // posted_live claim — the client-owned FRESH path
);
// Tagging is IMMEDIATE (Instagram-style): no pending state, no accept step.
// The coauthor's control is removing themselves afterwards.
assert.equal(
  collabPost.coauthor_status,
  "accepted",
  "a collab tags the coauthor straight away",
);
let tagged = await getUserTaggedPosts(ALICE, BOB, 20, null);
assert.ok(
  tagged.some((p) => p.post_id === mentionPost.post_id),
  "@ci_bob mention shows in Bob's tagged tab",
);
assert.ok(
  !tagged.some((p) => p.post_id === superstringPost.post_id),
  "@ci_bobber does NOT count as a ci_bob mention (exact token match)",
);
assert.ok(
  tagged.some(
    (p) => p.post_id === collabPost.post_id && p.coauthor_status === "accepted",
  ),
  "the tag is in Bob's tagged tab with no accept step",
);
// …and on his own grid, which is what "you're on this post" has to mean.
assert.ok(
  (await getUserPosts(BOB, BOB, 24)).some(
    (p) => p.post_id === collabPost.post_id,
  ),
  "a tagged collab lands on the coauthor's own profile grid",
);

// --- Tags on the grid vs the Tagged tab ---------------------------------
// Hiding a collab from your grid must move NOTHING else: the tag stays live,
// the Tagged tab keeps it, the author's grid keeps it, and both circles still
// get it in the feed. That separation is the whole feature — a regression
// here reads as "the app deleted my friend's post".
const bobGridHas = async (postId) =>
  (await getUserPosts(BOB, BOB, 24)).some((p) => p.post_id === postId);
const bobTaggedHas = async (postId) =>
  (await getUserTaggedPosts(BOB, BOB, 20, null)).some(
    (p) => p.post_id === postId,
  );

// The setting alone, with no per-post override (every existing tag's state).
await updateNotificationPreferences(BOB, { tagged_posts_on_profile: false });
assert.equal(
  await bobGridHas(collabPost.post_id),
  false,
  "tags-off-my-grid retroactively covers tags the user already had",
);
assert.ok(
  await bobTaggedHas(collabPost.post_id),
  "…while the Tagged tab keeps it (that's where it's supposed to live)",
);
assert.ok(
  (await getUserPosts(BOB, ALICE, 24)).some(
    (p) => p.post_id === collabPost.post_id,
  ),
  "…and it never leaves the AUTHOR's grid — it's their post",
);
assert.ok(
  (await getUnifiedFeed(CARL, 30, null)).some(
    (r) => r.kind === "post" && r.id === collabPost.post_id,
  ),
  "…and collab reach to the coauthor's circle is untouched",
);
// A per-post override beats the setting, in both directions.
assert.ok(
  await setCoauthorProfileVisibility(BOB, collabPost.post_id, true),
  "the coauthor may pin one collab back onto their grid",
);
assert.ok(
  await bobGridHas(collabPost.post_id),
  "…and an explicit override wins over the setting being off",
);
await updateNotificationPreferences(BOB, { tagged_posts_on_profile: true });
assert.ok(
  await setCoauthorProfileVisibility(BOB, collabPost.post_id, false),
  "…and the reverse override applies with the setting on",
);
assert.equal(
  await bobGridHas(collabPost.post_id),
  false,
  "…hiding one collab leaves the setting alone",
);
assert.ok(
  await bobTaggedHas(collabPost.post_id),
  "…and a per-post hide still isn't an untag",
);
// Only the coauthor may curate their own grid.
assert.equal(
  await setCoauthorProfileVisibility(CARL, collabPost.post_id, false),
  null,
  "a third party can't touch someone else's collab visibility",
);
assert.equal(
  await setCoauthorProfileVisibility(ALICE, collabPost.post_id, false),
  null,
  "…and neither can the post's own author",
);
// Restore the default state for everything downstream.
await setCoauthorProfileVisibility(BOB, collabPost.post_id, true);

// An older build still sends accept:true. That has to succeed as a no-op
// rather than 404 on a collab the user is already part of.
const collabAccept = await respondToCoauthorInvite(
  BOB,
  collabPost.post_id,
  true,
);
assert.equal(
  collabAccept?.author_id,
  ALICE,
  "a legacy accept on an already-accepted tag is idempotent",
);
assert.ok(
  !(await getUserTaggedPosts(ALICE, ALICE, 20, null)).some(
    (p) => p.post_id === mentionPost.post_id,
  ),
  "your own posts never show in your own tagged tab",
);
// FRESH both paths, as seen by Bob: the posted_live claim marks a post with
// no linked workout; a plain post with no claim and no workout stays unfresh.
const bobFeed = await getUnifiedFeed(BOB, 20, null);
const collabInFeed = bobFeed.find(
  (r) => r.kind === "post" && r.id === collabPost.post_id,
);
const mentionInFeed = bobFeed.find(
  (r) => r.kind === "post" && r.id === mentionPost.post_id,
);
assert.equal(
  collabInFeed?.is_fresh,
  true,
  "posted_live claim marks the post fresh for other viewers",
);
assert.equal(
  mentionInFeed?.is_fresh,
  false,
  "no claim + no linked workout stays unfresh",
);

// --- Collab permissions -------------------------------------------------
// A collab post reaches BOTH authors' circles, so every rule has to hold from
// two sides. CARL is Bob's friend only (reach comes purely from the coauthor);
// DANA is Alice's friend only (reach comes purely from the author).
const collabInFeedOf = async (uid) =>
  (await getUnifiedFeed(uid, 30, null)).find(
    (r) => r.kind === "post" && r.id === collabPost.post_id,
  );

let carlSees = await collabInFeedOf(CARL);
assert.ok(
  carlSees,
  "collab reaches the COAUTHOR's friend who isn't the author's",
);
assert.equal(carlSees.coauthor_user_id, BOB, "…carrying the collab tag");
assert.ok(
  await visiblePostAuthors(CARL, collabPost.post_id),
  "coauthor's friend may act on the post (comments + hypes authorize on this)",
);
assert.equal(
  (await visiblePostAuthors(CARL, collabPost.post_id)).coauthor_user_id,
  BOB,
  "…and the coauthor comes back so the hype can notify them",
);

// Coauthor goes 'private' ("Only me"): the collab TAG and the reach it carries
// both stop, but the post is still Alice's and stays with Alice's circle.
await updateNotificationPreferences(BOB, { workout_visibility: "private" });
assert.equal(
  await collabInFeedOf(CARL),
  undefined,
  "private coauthor no longer pulls the post into their own friends' feeds",
);
assert.equal(
  await visiblePostAuthors(CARL, collabPost.post_id),
  null,
  "…and direct access through the private coauthor closes too",
);
const danaSeesPrivateCollab = await collabInFeedOf(DANA);
assert.ok(
  danaSeesPrivateCollab,
  "the author's own circle keeps the post — privacy withholds the tag, not the post",
);
assert.equal(
  danaSeesPrivateCollab.coauthor_user_id,
  null,
  "private coauthor's name/avatar is withheld from third parties",
);
assert.equal(
  danaSeesPrivateCollab.coauthor_username,
  null,
  "…including the username",
);
assert.equal(
  (await collabInFeedOf(BOB))?.coauthor_user_id,
  BOB,
  "both authors still see the collab on their own post",
);
await updateNotificationPreferences(BOB, { workout_visibility: "friends" });

// Author goes 'private': the post leaves everyone's feed EXCEPT the two
// authors' — "nobody but you" has to still include you (and your coauthor).
await updateNotificationPreferences(ALICE, { workout_visibility: "private" });
assert.equal(
  await collabInFeedOf(DANA),
  undefined,
  "private author's post leaves their friends' feeds",
);
assert.equal(
  await collabInFeedOf(CARL),
  undefined,
  "…and doesn't survive via the coauthor's circle either",
);
assert.ok(
  await collabInFeedOf(ALICE),
  "a private author still sees their own post",
);
assert.ok(
  await collabInFeedOf(BOB),
  "the coauthor still sees a collab they're an author on",
);
assert.ok(
  await visiblePostAuthors(BOB, collabPost.post_id),
  "…and can still act on it",
);
await updateNotificationPreferences(ALICE, { workout_visibility: "friends" });

// Hype authorization: the post's audience, not friendship with its author.
const collabAuthors = await visiblePostAuthors(CARL, collabPost.post_id);
assert.equal(
  collabAuthors?.author_id,
  ALICE,
  "hypes on a collab are always filed against the PRIMARY author",
);
assert.equal(
  (await visiblePostAuthors(ALICE, mentionPost.post_id)) !== null,
  true,
  "an author can always see their own post",
);
assert.equal(
  await visiblePostAuthors(CARL, mentionPost.post_id),
  null,
  "a non-collab post stays inside its author's circle",
);

// …and end-to-end through the real controller, because the shipped bug was
// exactly this: the card rendered, the hype animation played, and the request
// came back 403 because the sender wasn't friends with the PRIMARY author.
function fakeRes() {
  const out = { code: null, body: null };
  const res = {
    status(c) {
      out.code = c;
      return res;
    },
    json(b) {
      out.body = b;
      return res;
    },
  };
  return { res, out };
}
const postHypeCtx = (target) => ({
  target_user_id: target,
  context_type: "post",
  context_id: collabPost.post_id,
  context_label: "collab",
});
const callSendHype = async (userId, body) => {
  const { res, out } = fakeRes();
  await sendHype({ userId, body }, res);
  return out;
};
const callHypers = async (userId) => {
  const { res, out } = fakeRes();
  await getContextHypersController(
    {
      userId,
      query: {
        context_type: "post",
        context_id: collabPost.post_id,
        target_user_id: ALICE,
      },
    },
    res,
  );
  return out;
};

let hypeRes = await callSendHype(CARL, postHypeCtx(ALICE));
assert.equal(
  hypeRes.code,
  200,
  `the coauthor's friend can hype the collab (got ${JSON.stringify(hypeRes.body)})`,
);
assert.deepEqual(
  await db.query(
    `SELECT target_id, context_type FROM hype_log WHERE sender_id = $1`,
    [CARL],
  ),
  [{ target_id: ALICE, context_type: "post" }],
  "a collab hype is filed against the PRIMARY author (the tally reads that row)",
);
assert.equal(
  (await callSendHype(CARL, postHypeCtx(ALICE))).code,
  409,
  "…and still dedupes",
);
hypeRes = await callSendHype(BOB, postHypeCtx(ALICE));
assert.equal(hypeRes.code, 400, "an author can't hype their own collab");
assert.match(hypeRes.body.error, /your own post/);
assert.equal(
  (await callSendHype(DANA, postHypeCtx(ALICE))).code,
  200,
  "the author's friend can hype it too",
);
assert.equal(
  (await callHypers(CARL)).code,
  200,
  "the coauthor's friend can open the hypers list",
);
assert.equal(
  (await callHypers(BOB)).code,
  200,
  "an author can read their own post's hypers even though they can't hype it",
);
assert.equal(
  (await callSendHype("ci-stranger", postHypeCtx(ALICE))).code,
  400,
  "someone in neither circle can't hype the post",
);

// A block BETWEEN the two authors ends the collab — the tagged tab already
// dropped the row, so the feed must not keep showing "alice & bob". The post
// reverts to a solo post rather than disappearing: the media and the run are
// the author's.
await db.query(
  `INSERT INTO user_blocks (blocker_id, blocked_id) VALUES ($1, $2)
	 ON CONFLICT DO NOTHING`,
  [BOB, ALICE],
);
assert.equal(
  await collabInFeedOf(CARL),
  undefined,
  "a severed collab stops reaching the ex-coauthor's circle",
);
const afterBlock = await collabInFeedOf(DANA);
assert.ok(afterBlock, "…but the author keeps their own post");
assert.equal(afterBlock.coauthor_user_id, null, "…with the tag severed");
assert.ok(
  await collabInFeedOf(ALICE),
  "the author still sees their post after being blocked by the coauthor",
);
assert.ok(
  !(await getUserTaggedPosts(ALICE, BOB, 20, null)).some(
    (p) => p.post_id === collabPost.post_id,
  ),
  "…and it leaves the ex-coauthor's tagged tab",
);
assert.equal(
  await acceptedCoauthor(collabPost.post_id),
  null,
  "…so comment/hype pushes stop reaching them too",
);
await db.query(`DELETE FROM user_blocks WHERE blocker_id = $1`, [BOB]);

// Removing yourself is the ONLY control a tagged coauthor has now that tags
// apply immediately, so it has to work from the accepted state (the old
// decline path only ever ran against a pending row).
const collabRemove = await respondToCoauthorInvite(
  BOB,
  collabPost.post_id,
  false,
);
assert.equal(
  collabRemove?.author_id,
  ALICE,
  "an accepted coauthor can remove themselves",
);
assert.equal(
  await acceptedCoauthor(collabPost.post_id),
  null,
  "…which severs the tag",
);
assert.ok(
  !(await getUserPosts(BOB, BOB, 24)).some(
    (p) => p.post_id === collabPost.post_id,
  ),
  "…and takes the post off their profile grid",
);
assert.ok(
  await collabInFeedOf(ALICE),
  "…while the post itself stays the author's",
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

// ── feed_role: tiny/partial workouts must not spam the feed ─────────────────
// The rule has four moving parts (a floor, a per-day rollup, an anchor, and the
// invariant that none of it changes what COUNTS), and they're only correct
// together — so they're asserted together, against the real upload path.
{
  const CARL = "ci-carl";
  const roleDay = "2026-03-04";
  await db.query(`DELETE FROM workouts WHERE user_id = $1`, [CARL]);
  await db.query(
    `INSERT INTO users (user_id, email, apple_sub, username, first_name)
		 VALUES ($1,$2,$3,$4,$5) ON CONFLICT (user_id) DO NOTHING`,
    [CARL, "carl@ci.local", "ci-sub-carl", "ci_carl", "carl"],
  );
  await db.query(
    `INSERT INTO notification_settings (user_id) VALUES ($1) ON CONFLICT DO NOTHING`,
    [CARL],
  );
  for (const [a, b] of [
    [CARL, BOB],
    [BOB, CARL],
  ]) {
    await db.query(
      `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1,$2,'accepted')
			 ON CONFLICT (user_id, friend_id) DO NOTHING`,
      [a, b],
    );
  }

  const at = (id, distance, duration, hour) => ({
    workoutId: id,
    distance,
    localDate: roleDay,
    date: roleDay,
    timezoneOffset: 0,
    workoutType: "walking",
    deviceEndDate: `${roleDay}T${String(hour).padStart(2, "0")}:00:00Z`,
    calories: 40,
    totalDuration: duration,
    source: "healthkit",
    splits: [],
  });
  const rolesOf = async () =>
    Object.fromEntries(
      (
        await db.query(
          `SELECT workout_id, feed_role FROM workouts WHERE user_id = $1 ORDER BY device_end_date`,
          [CARL],
        )
      ).map((r) => [r.workout_id, r.feed_role]),
    );
  const carlEntries = async () =>
    (await getUnifiedFeed(BOB, 50, null)).filter((e) => e.user_id === CARL);

  // Fresh syncs are HELD off friends' feeds for the photo window (asserted
  // up top). Carl's device_end_dates sit months in the past, but the hold
  // anchors on GREATEST(device_end_date, created_at) — so age created_at
  // after each upload for these assertions to read the settled card state.
  const ageCarlPastPostWindow = () =>
    db.query(
      `UPDATE workouts SET created_at = created_at - INTERVAL '11 minutes'
			 WHERE user_id = $1 AND created_at > NOW() - INTERVAL '10 minutes'`,
      [CARL],
    );

  // A 0.00-mile 3-second accident, then a mile built from three short walks.
  await uploadWorkouts(CARL, [
    at("ci-role-junk", 0.0, 3, 6),
    at("ci-role-a", 0.33, 400, 8),
    at("ci-role-b", 0.33, 400, 9),
    at("ci-role-c", 0.4, 500, 10),
  ]);
  await ageCarlPastPostWindow();
  assert.deepEqual(
    await rolesOf(),
    {
      "ci-role-junk": "hidden",
      "ci-role-a": "rolled_up",
      "ci-role-b": "rolled_up",
      "ci-role-c": "daily_mile",
    },
    "a mile made of three walks rolls up behind the workout that completed it",
  );

  let entries = await carlEntries();
  assert.equal(
    entries.length,
    1,
    "three walks produce ONE feed card, not three",
  );
  assert.equal(
    entries[0].workout_id,
    "ci-role-c",
    "card anchors on the crossing workout",
  );
  assert.equal(entries[0].segment_count, 3, "card reports its three segments");
  assert.equal(
    Number(entries[0].distance.toFixed(2)),
    1.06,
    "card shows the combined mile (this is what old clients render, unchanged)",
  );
  assert.equal(
    entries[0].route,
    null,
    "no route on a stitched mile — the anchor's trace is only its last leg",
  );

  // The floor is a FEED rule. It must never change what counts.
  const counted = await db.query(
    `SELECT COALESCE(SUM(distance),0)::float AS t FROM workouts
		 WHERE user_id = $1 AND local_date = $2::date
			 AND deleted_at IS NULL AND exclusion_reason IS NULL`,
    [CARL, roleDay],
  );
  assert.equal(
    Number(counted[0].t.toFixed(2)),
    1.06,
    "hidden junk still counts toward the day's miles and the streak",
  );

  // Anything after the mile stands on its own, with its OWN distance.
  await uploadWorkouts(CARL, [at("ci-role-extra", 2.0, 1800, 14)]);
  await ageCarlPastPostWindow();
  entries = await carlEntries();
  assert.equal(entries.length, 2, "a run after the mile gets its own card");
  const extra = entries.find((e) => e.workout_id === "ci-role-extra");
  assert.equal(
    extra.distance,
    2.0,
    "the extra run reports itself, not the day",
  );
  assert.equal(extra.segment_count, null, "an extra run carries no rollup");

  // A day that never reaches the mile shows nothing at all.
  const shortDay = "2026-03-05";
  await uploadWorkouts(CARL, [
    {
      ...at("ci-role-short", 0.4, 600, 8),
      localDate: shortDay,
      date: shortDay,
    },
  ]);
  assert.equal(
    (await carlEntries()).some((e) => e.workout_id === "ci-role-short"),
    false,
    "a sub-goal day produces no feed card",
  );

  // A post attached to the anchor must read the same on the profile grid as it
  // does in the feed — POST_COLUMNS restates it via a subquery that returns no
  // row for an unlinked post, so this also guards against nulling stats out.
  await createPost({
    userId: CARL,
    mediaUrl: "/uploads/posts/ci-carl-photo.jpg",
    caption: "three walks",
    workoutId: "ci-role-c",
    localDate: roleDay,
    shareToFeed: true,
    shareToStory: false,
    statsSnapshot: { distance: 0.4, duration: 500, pace: 1250 },
    isAuto: false,
    includeRoute: false,
  });
  const carlGrid = await getUserPosts(CARL, CARL, 20);
  const anchorPost = carlGrid.find((p) => p.workout_id === "ci-role-c");
  assert.equal(
    Number(anchorPost.stats_snapshot.distance.toFixed(2)),
    1.06,
    "profile grid restates an anchor post to the day's combined mile",
  );
  const unlinked = await createPost({
    userId: CARL,
    mediaUrl: "/uploads/posts/ci-carl-unlinked.jpg",
    caption: "no workout",
    workoutId: null,
    localDate: roleDay,
    shareToFeed: false,
    shareToStory: true,
    statsSnapshot: { distance: 3.3 },
    isAuto: false,
    includeRoute: false,
  });
  const unlinkedRow = (await getUserPosts(CARL, CARL, 20, null, true)).find(
    (p) => p.post_id === unlinked.post_id,
  );
  assert.equal(
    unlinkedRow.stats_snapshot.distance,
    3.3,
    "a post with no linked workout keeps its stats (not nulled by the rollup join)",
  );

  // ─── Friend ghosts ────────────────────────────────────────────────────────
  //
  // The ghost picker offers a friend's fastest mile as a target. Every rule that
  // keeps that honest is a WHERE clause, so each one gets an assertion: this is
  // the query that decides whose time a stranger can chase.
  {
    const ghostWorkout = async (userId, id, type, splitDistance, splitPace) => {
      await db.query(
        `INSERT INTO workouts (user_id, workout_id, distance, local_date, date,
                             timezone_offset, workout_type, device_end_date,
                             calories, total_duration)
       VALUES ($1, $2, 1.0, $3, $4, 0, $5, $6, 50, 600)
       ON CONFLICT (workout_id) DO NOTHING`,
        // `date` and `local_date` are DATE columns; `device_end_date` is
        // timestamptz. Reusing one param for a date and a timestamptz is a
        // param-type conflict, not a coercion.
        [userId, id, localDate, localDate, type, nowIso],
      );
      await db.query(
        `INSERT INTO workout_splits (workout_id, split_number, split_duration,
                                   split_distance, split_pace)
       VALUES ($1, 1, $2, $3, $2)
       ON CONFLICT (workout_id, split_number) DO UPDATE
         SET split_distance = EXCLUDED.split_distance,
             split_pace = EXCLUDED.split_pace`,
        [id, splitPace, splitDistance],
      );
    };

    await ghostWorkout(BOB, "ci-ghost-bob-run", "running", 1.0, 540);
    await ghostWorkout(DANA, "ci-ghost-dana-run", "running", 1.0, 500);

    let ghosts = await getFriendGhosts(ALICE, "running");
    let ids = ghosts.map((g) => g.user_id);
    assert.ok(ids.includes(BOB), "a friend's mile is offered as a ghost");
    assert.equal(
      ghosts.find((g) => g.user_id === BOB).mile_seconds,
      540,
      "the ghost time is the friend's fastest mile split, in seconds",
    );

    // DANA is Alice's friend too, and faster — the list is a leaderboard.
    assert.deepEqual(
      ghosts.map((g) => g.mile_seconds),
      [...ghosts.map((g) => g.mile_seconds)].sort((a, b) => a - b),
      "ghosts come back fastest-first",
    );

    // A non-friend is never offered. CARL is Bob's friend, not Alice's.
    await ghostWorkout(CARL, "ci-ghost-carl-run", "running", 1.0, 400);
    ghosts = await getFriendGhosts(ALICE, "running");
    assert.ok(
      !ghosts.some((g) => g.user_id === CARL),
      "a non-friend's mile is never offered, however fast",
    );

    // Activity type: a RUN split must never become a WALK ghost.
    const walkGhosts = await getFriendGhosts(ALICE, "walking");
    assert.ok(
      !walkGhosts.some((g) => g.user_id === BOB),
      "a friend's run mile is not offered as a walk ghost",
    );

    // The 0.999 floor: a 0.96-mile split is an extrapolated partial, not a mile.
    await ghostWorkout(DANA, "ci-ghost-dana-partial", "walking", 0.96, 300);
    assert.ok(
      !(await getFriendGhosts(ALICE, "walking")).some(
        (g) => g.user_id === DANA,
      ),
      "a sub-0.999 split is excluded (extrapolated partial, unbeatable)",
    );

    // Blocks hide the mile in BOTH directions.
    await db.query(
      `INSERT INTO user_blocks (blocker_id, blocked_id) VALUES ($1, $2)
     ON CONFLICT DO NOTHING`,
      [BOB, ALICE],
    );
    assert.ok(
      !(await getFriendGhosts(ALICE, "running")).some((g) => g.user_id === BOB),
      "a block hides the blocker's mile from the blocked user",
    );
    assert.ok(
      !(await getFriendGhosts(BOB, "running")).some((g) => g.user_id === ALICE),
      "a block hides the mile in the other direction too",
    );
    await db.query(`DELETE FROM user_blocks WHERE blocker_id = $1`, [BOB]);

    // workout_visibility = 'private' removes you from being raceable. This is
    // the privacy control the feature reuses instead of minting a new toggle.
    await updateNotificationPreferences(BOB, { workout_visibility: "private" });
    assert.ok(
      !(await getFriendGhosts(ALICE, "running")).some((g) => g.user_id === BOB),
      "a 'private' user is not offered as a ghost",
    );
    await updateNotificationPreferences(BOB, { workout_visibility: "friends" });

    // A soft-deleted workout stops supplying the number.
    await db.query(
      `UPDATE workouts SET deleted_at = NOW() WHERE workout_id = 'ci-ghost-bob-run'`,
    );
    assert.ok(
      !(await getFriendGhosts(ALICE, "running")).some((g) => g.user_id === BOB),
      "a soft-deleted workout stops supplying a ghost time",
    );
    await db.query(
      `UPDATE workouts SET deleted_at = NULL WHERE workout_id = 'ci-ghost-bob-run'`,
    );

    // A sub-4:01 mile is a car, not a person. It must not become anyone's
    // ghost, PR, leaderboard entry or badge — the floor is shared, so this
    // asserts the one surface and documents the rule for the rest.
    await ghostWorkout(BOB, "ci-ghost-bob-car", "running", 1.0, 140);
    const carGhosts = await getFriendGhosts(ALICE, "running");
    assert.equal(
      carGhosts.find((g) => g.user_id === BOB)?.mile_seconds,
      540,
      "a 2:20 mile is ignored; the real 9:00 stays the ghost",
    );
    await db.query(
      `DELETE FROM workout_splits WHERE workout_id = 'ci-ghost-bob-run'`,
    );
    assert.ok(
      !(await getFriendGhosts(ALICE, "running")).some((g) => g.user_id === BOB),
      "with only the sub-4:01 split left, they drop out entirely",
    );

    await db.query(
      `DELETE FROM workout_splits WHERE workout_id LIKE 'ci-ghost-%'`,
    );
    await db.query(`DELETE FROM workouts WHERE workout_id LIKE 'ci-ghost-%'`);
  }

  await db.query(`DELETE FROM posts WHERE user_id = $1`, [CARL]);
  await db.query(`DELETE FROM workouts WHERE user_id = $1`, [CARL]);
  await db.query(
    `DELETE FROM friendships WHERE user_id = $1 OR friend_id = $1`,
    [CARL],
  );
  await db.query(`DELETE FROM notification_settings WHERE user_id = $1`, [
    CARL,
  ]);
  await db.query(`DELETE FROM users WHERE user_id = $1`, [CARL]);
}

// --- Weekly challenge ---------------------------------------------------
// Three of these fail SILENTLY if they regress: a target that isn't frozen
// just drifts, a gaps-and-islands walk paired the wrong way returns 1 forever,
// and a metric arm missing countedWorkoutSql quietly counts a workout that is
// excluded from the user's own miles. None of them throw, so they have to be
// asserted against seeded numbers rather than read.
//
// Runs against its OWN user: Alice and Bob already carry workouts from the feed
// assertions above, which would make every expected total a moving target.
{
  const WENDY = "ci-wendy";

  await db.query(
    `INSERT INTO users (user_id, email, apple_sub, username, first_name)
     VALUES ($1, 'wendy@ci.local', 'ci-sub-wendy', 'ci_wendy', 'wendy')
     ON CONFLICT (user_id) DO NOTHING`,
    [WENDY],
  );
  // Pin to UTC so the seeded local_dates land in the week the service computes.
  await db.query(
    `INSERT INTO notification_settings (user_id, timezone_offset_minutes)
     VALUES ($1, 0)
     ON CONFLICT (user_id) DO UPDATE SET timezone_offset_minutes = 0`,
    [WENDY],
  );
  await db.query(
    `UPDATE notification_settings SET timezone_offset_minutes = 0 WHERE user_id = $1`,
    [ALICE],
  );
  for (const [a, b] of [
    [ALICE, WENDY],
    [WENDY, ALICE],
  ]) {
    await db.query(
      `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, 'accepted')
       ON CONFLICT (user_id, friend_id) DO NOTHING`,
      [a, b],
    );
  }

  await seedWeeklyChallenges();

  // Retiring a challenge and giving its rotation slot to the replacement is a
  // unique-key handover, so the seeder has to vacate the slot before claiming
  // it. If that ordering regresses the INSERT throws, the seeder swallows it
  // (deliberately — a stale catalog beats a crash loop) and the new challenge
  // just never appears.
  const catalog = await getCatalog();
  assert.equal(catalog.length, 12, "twelve active weekly challenges");
  const bigDay = catalog.find((c) => c.challenge_key === "big_day");
  assert.ok(bigDay, "Big Day is in the active rotation");
  assert.equal(
    bigDay.rotation_index,
    7,
    "and holds the slot Weekend Warrior vacated, so no other week's challenge moved",
  );
  assert.ok(
    !catalog.some((c) => c.challenge_key === "weekend_warrior"),
    "Weekend Warrior is retired (it named specific weekdays, which Sunday-start weeks broke)",
  );

  const win = await weekWindowForUser(WENDY);
  const day = (offset) => {
    const d = new Date(`${win.weekStart}T00:00:00Z`);
    d.setUTCDate(d.getUTCDate() + offset);
    return d.toISOString().slice(0, 10);
  };
  const addWorkout = async (userId, id, date, distance, exclusion = null) => {
    await db.query(
      `INSERT INTO workouts (workout_id, user_id, distance, local_date, date,
         timezone_offset, workout_type, device_end_date, calories,
         total_duration, exclusion_reason)
       VALUES ($1,$2,$3,$4::date,$4::date,0,'running',($4 || 'T12:00:00Z')::timestamptz,100,1800,$5)
       ON CONFLICT (workout_id) DO NOTHING`,
      [id, userId, distance, date, exclusion],
    );
  };
  const round2 = (n) => Math.round(n * 100) / 100;

  // Weeks run SUNDAY→SATURDAY. Postgres's date_trunc('week') is ISO
  // Monday-start, so the boundary is built by hand — and a wrong idiom fails
  // silently (every read still returns SOME window, just shifted a day, which
  // strands the week's stamped row). Assert the shape directly.
  assert.equal(
    new Date(`${win.weekStart}T00:00:00Z`).getUTCDay(),
    0,
    "the week starts on a Sunday",
  );
  assert.equal(
    win.weekEnd,
    day(6),
    "and ends on the following Saturday, six days later",
  );

  // Sun/Mon/Tue — three CONSECUTIVE days, 6.0 miles total.
  await addWorkout(WENDY, "ci-wk-1", day(0), 2.0);
  await addWorkout(WENDY, "ci-wk-2", day(1), 2.0);
  await addWorkout(WENDY, "ci-wk-3", day(2), 2.0);

  assert.equal(
    round2(await measure(WENDY, "total_distance", win.weekStart, win.weekEnd)),
    6,
    "total_distance sums the week's counted workouts",
  );
  assert.equal(
    await measure(WENDY, "consecutive_active_days", win.weekStart, win.weekEnd),
    3,
    "consecutive_active_days finds the 3-day run (the island key must move opposite to the row numbering, or this silently returns 1)",
  );

  // A duplicate-source copy must be invisible — it doesn't count toward miles,
  // so it must not win a challenge either.
  await addWorkout(WENDY, "ci-wk-dupe", day(3), 5.0, "duplicate_source");
  assert.equal(
    round2(await measure(WENDY, "total_distance", win.weekStart, win.weekEnd)),
    6,
    "an excluded workout is invisible to the weekly metric (countedWorkoutSql)",
  );

  // best_day_distance is the best DAY, not the best workout and not the week.
  // A second walk on day 0 makes that day 3.5 while the week totals 7.5 and the
  // excluded duplicate alone is 5.0 — so this one number fails three separate
  // ways: a missing GROUP BY (would read 7.5), a MAX over workouts rather than
  // days (2.0), and a missing countedWorkoutSql (5.0).
  await addWorkout(WENDY, "ci-wk-best", day(0), 1.5);
  assert.equal(
    round2(
      await measure(WENDY, "best_day_distance", win.weekStart, win.weekEnd),
    ),
    3.5,
    "best_day_distance takes the biggest single DAY, summed across that day's counted workouts",
  );
  // measure() feeds the user's own card and measureBatch() feeds the friends
  // leaderboard. If the two arms drift, a user's row on the board disagrees
  // with the number on their own screen.
  assert.equal(
    round2(
      (
        await measureBatch(
          [WENDY],
          "best_day_distance",
          win.weekStart,
          win.weekEnd,
        )
      ).get(WENDY) ?? 0,
    ),
    3.5,
    "measureBatch agrees with measure on best_day_distance",
  );

  // mile_days uses the 0.95 tolerance, so a 0.96 day against a 1.0 goal counts
  // here exactly as it does everywhere else in the app.
  await db.query(`UPDATE users SET goal_miles = 1.0 WHERE user_id = $1`, [
    WENDY,
  ]);
  assert.equal(
    await measure(WENDY, "mile_days", win.weekStart, win.weekEnd),
    3,
    "the three 2-mile days are mile days",
  );
  await addWorkout(WENDY, "ci-wk-tol", day(5), 0.96);
  assert.equal(
    await measure(WENDY, "mile_days", win.weekStart, win.weekEnd),
    4,
    "a 0.96 day counts against a 1.0 goal (DAILY_GOAL_TOLERANCE, not a raw >=)",
  );

  // The target is frozen on first serve: serving again must not move it, even
  // though more miles have been run in between.
  const first = await serveWeek(WENDY, win.weekStart);
  assert.ok(first, "a week is served");
  await addWorkout(WENDY, "ci-wk-4", day(4), 8.0);
  const second = await serveWeek(WENDY, win.weekStart);
  assert.equal(
    second.target,
    first.target,
    "the target is frozen at first serve",
  );
  assert.equal(
    second.challenge.challenge_key,
    first.challenge.challenge_key,
    "and so is the challenge",
  );

  // Clamps: no history falls back to the catalog base, and an absurd baseline
  // can't produce an unreachable target.
  const row = first.challenge;
  assert.equal(
    resolveTarget(row, null).target,
    Math.round(row.base_target / row.target_step) * row.target_step,
    "no history => the base target",
  );
  assert.ok(
    resolveTarget(row, row.base_target * 1000).target <= row.target_ceiling,
    "an absurd baseline is capped at the ceiling",
  );

  // Completion is once-only.
  //
  // The stamped row is rewritten to a known challenge rather than relying on
  // whichever one this calendar week serves: half the catalog (steps, early/
  // late runs, fast splits) measures zero against these seeded workouts, so the
  // assertion would pass or fail depending on the date. Rewriting it also
  // proves the evaluator reads the STAMPED challenge rather than re-picking.
  await serveWeek(ALICE, win.weekStart);
  await db.query(
    `UPDATE user_weekly_challenges
       SET challenge_key = 'week_of_miles', target = 0.01
     WHERE user_id = ANY($1::text[]) AND week_start = $2::date`,
    [[WENDY, ALICE], win.weekStart],
  );
  assert.ok(
    await evaluateWeeklyChallengeForUser(WENDY),
    "meeting the target awards the week",
  );
  assert.equal(
    await evaluateWeeklyChallengeForUser(WENDY),
    null,
    "a second evaluation awards nothing (only the winning INSERT returns)",
  );
  const completions = await db.query(
    `SELECT COUNT(*)::int AS n FROM user_weekly_challenge_completions WHERE user_id = $1`,
    [WENDY],
  );
  assert.equal(completions[0].n, 1, "exactly one completion row");

  // Leaderboard: served friends only, on the challenge stamped above.
  const board = await getWeeklyLeaderboard(
    ALICE,
    win.weekStart,
    win.weekEnd,
    "week_of_miles",
    "total_distance",
  );
  const ids = board.map((e) => e.user_id);
  assert.ok(ids.includes(ALICE), "the viewer is on their own board");
  assert.ok(ids.includes(WENDY), "an accepted friend is on the board");
  assert.ok(
    !ids.includes(DANA),
    "a friend who was never served has no frozen target, so no row",
  );
  assert.ok(
    board.every((e) => typeof e.target === "number" && e.target > 0),
    "every entry carries its OWN target — the board ranks on percent of it",
  );

  await db.query(
    `INSERT INTO user_blocks (blocker_id, blocked_id) VALUES ($1, $2)
     ON CONFLICT DO NOTHING`,
    [ALICE, WENDY],
  );
  assert.ok(
    !(
      await getWeeklyLeaderboard(
        ALICE,
        win.weekStart,
        win.weekEnd,
        "week_of_miles",
        "total_distance",
      )
    )
      .map((e) => e.user_id)
      .includes(WENDY),
    "a blocked friend is off the board",
  );
  await db.query(`DELETE FROM user_blocks WHERE blocker_id LIKE 'ci-%'`);

  await db.query(
    `DELETE FROM user_weekly_challenge_completions WHERE user_id LIKE 'ci-%'`,
  );
  await db.query(
    `DELETE FROM user_weekly_challenges WHERE user_id LIKE 'ci-%'`,
  );
  await db.query(`DELETE FROM workouts WHERE workout_id LIKE 'ci-wk-%'`);
  await db.query(
    `DELETE FROM friendships WHERE user_id = $1 OR friend_id = $1`,
    [WENDY],
  );
  await db.query(`DELETE FROM notification_settings WHERE user_id = $1`, [
    WENDY,
  ]);
  await db.query(`DELETE FROM users WHERE user_id = $1`, [WENDY]);
}

console.log("ci-smoke: all assertions passed");
process.exit(0);
