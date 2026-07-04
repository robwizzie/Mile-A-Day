// CI smoke test: seeds a throwaway Postgres (already migrated by
// dist/db/migrateCli.js) with two friends, workouts, a GPS route and a photo
// post, then runs the REAL feed/story/hype/signing code paths against it.
// Catches the class of outage where migrations, schema and queries drift
// apart — the exact failure mode of the v1.2 feed incident.
//
// Usage: DATABASE_URL=postgres://... node scripts/ci-smoke.mjs
import assert from "node:assert/strict";

const { PostgresService } = await import("../dist/services/DbService.js");
const { uploadWorkouts, getUserRoutes } =
  await import("../dist/services/workoutService.js");
const { createPost, getUnifiedFeed, getStoriesRail, getUserPosts } =
  await import("../dist/services/postService.js");
const { canonicalizeMileContext, logHypeIfUnderLimit, hasHypedMile } =
  await import("../dist/services/hypeService.js");
const { signMediaUrl, verifyPostsMediaAccess, stripMediaQuery } =
  await import("../dist/services/mediaSigningService.js");

const db = PostgresService.getInstance();

const ALICE = "ci-alice";
const BOB = "ci-bob";
const localDate = new Date().toISOString().slice(0, 10);
const nowIso = new Date().toISOString();

async function cleanup() {
  // CI always runs on a fresh database; this makes local re-runs work too.
  await db.query(`DELETE FROM hype_log WHERE sender_id LIKE 'ci-%'`);
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

// Mile hype: canonicalize a workout id to the composite key, send, dedupe.
const ctx = await canonicalizeMileContext(BOB, {
  contextType: "mile",
  contextId: "ci-workout-bob",
  contextLabel: "mile",
});
assert.equal(ctx.contextId, `${BOB}:${localDate}`, "mile key canonicalized");
const hype = await logHypeIfUnderLimit(ALICE, BOB, ctx);
assert.ok(hype?.id, "hype logged");
assert.equal(await hasHypedMile(ALICE, BOB, ctx.contextId), true);
const feedAfterHype = await getUnifiedFeed(ALICE, 20, null);
assert.ok(feedAfterHype.length >= 1, "feed still reads after hype");

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

console.log("ci-smoke: all assertions passed");
process.exit(0);
