/**
 * Profile-grid controls, collab switches and Story Highlights.
 *
 * Three things changed here that cannot be verified by reading the SQL, which
 * is the rule for anything touching the feed's reach fragments:
 *
 *  1. `collabReachSql` gained `coauthor_on_feed`. That fragment decides who a
 *     collab reaches, and it is asked from getFeed, the unified feed's
 *     coauthor arm and DIRECT_POST_ACCESS_SQL. Every failure mode is silent —
 *     too strict and the coauthor loses their own post, too loose and a
 *     "don't broadcast this" switch does nothing.
 *  2. The grid grew a sort, a filter and pins. The DEFAULT shape must stay
 *     byte-identical, because the entire installed base sends no parameters
 *     and a pin excluded from `items` would vanish from those clients' grids.
 *  3. Highlights publish story-only posts permanently. That is a NEW reach —
 *     the grid refuses those posts to everyone but their owner — so it needs
 *     the same privacy and block rules stated and tested, not inherited.
 *
 * Covers, against a real migrated database:
 *   1. a collab reaches the coauthor's friend by default; `on_feed = false`
 *      withdraws exactly that reach and nothing else (author's friend keeps
 *      it, the coauthor keeps their own, the tag stays, the grid stays)
 *   2. the same switch on the multi-person representation (post_coauthors)
 *   3. direct post access (comments/mentions/push taps) tracks the switch
 *   4. pins: cap of 3, re-pin is free, unpin frees a slot, and pins stay
 *      INLINE for a caller that doesn't ask to split them
 *   5. sort=oldest reverses the page; filter partitions the grid; defaults
 *      return exactly what they returned before any of this existed
 *   6. per-post crew route consent overrides the global share_route_maps in
 *      both directions, and the poster's include_route still wins above it
 *   7. highlights: owner-only membership, a story-only member IS visible to a
 *      friend, and is NOT visible to a blocked user or through a private
 *      owner; delete removes the grouping and keeps the posts
 *   8. an uploaded highlight cover outranks the member photo on the rail, a
 *      write that doesn't mention it leaves it alone, and "" puts the member
 *      photo back
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/grid-controls-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import {
  createPost,
  getFeed,
  getUnifiedFeed,
  getUserPosts,
  getUserPinnedPosts,
  setPostPinned,
  setCoauthorFeedVisibility,
  setCoauthorRoutePreference,
  setCoauthorProfileVisibility,
  visiblePostAuthors,
  listUserHighlights,
  getHighlight,
  createHighlight,
  updateHighlight,
  deleteHighlight,
  addCrewPhoto,
  POST_PIN_LIMIT,
} from "../dist/services/postService.js";
import { uploadWorkouts } from "../dist/services/workoutService.js";

const db = PostgresService.getInstance();

const AUTHOR = "grid-author";
const MATE = "grid-mate"; // credited coauthor
const MATEPAL = "grid-matepal"; // MATE's friend only — reach via the COAUTHOR
const AUTHPAL = "grid-authpal"; // AUTHOR's friend only — reach via the AUTHOR
const ALL = [AUTHOR, MATE, MATEPAL, AUTHPAL];

const localDate = new Date().toISOString().slice(0, 10);
const nowIso = new Date().toISOString();

let failures = 0;
function check(label, actual, expected) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${actual} (expected ${expected})`,
  );
}

const feedHas = async (viewer, postId) =>
  (await getUnifiedFeed(viewer, 30, null)).some(
    (r) => r.kind === "post" && r.id === postId,
  );

const gridIds = async (viewer, owner, opts) =>
  (await getUserPosts(viewer, owner, 30, null, viewer === owner, opts)).map(
    (p) => p.post_id,
  );

async function cleanup() {
  // Pushes write in-app rows even with no device, and those rows FK to users —
  // clearing them first keeps a re-run from failing on the FK instead of on
  // whatever it was actually testing.
  await db.query(
    `DELETE FROM in_app_notifications WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(
    `DELETE FROM post_highlight_items WHERE highlight_id IN (
       SELECT highlight_id FROM post_highlights WHERE user_id = ANY($1::text[]))`,
    [ALL],
  );
  await db.query(
    `DELETE FROM post_highlights WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM post_coauthors WHERE user_id = ANY($1::text[])`, [
    ALL,
  ]);
  await db.query(`DELETE FROM posts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM workout_routes WHERE workout_id LIKE 'grid-w-%'`);
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(
    `DELETE FROM user_blocks WHERE blocker_id = ANY($1::text[])
       OR blocked_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(
    `DELETE FROM notification_settings WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM friendships WHERE user_id = ANY($1::text[])`, [
    ALL,
  ]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1::text[])`, [ALL]);
}

async function seed() {
  await cleanup();
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, apple_sub, email, username, first_name)
       VALUES ($1, $2, $3, $4, $5) ON CONFLICT (user_id) DO NOTHING`,
      [id, `sub-${id}`, `${id}@example.com`, id, id],
    );
    await db.query(
      `INSERT INTO notification_settings (user_id) VALUES ($1)
       ON CONFLICT DO NOTHING`,
      [id],
    );
  }
  // Deliberately NOT a clique: each witness is friends with exactly one side
  // of the collab, so a reach rule that leaks or over-blocks shows up on one
  // of them and only one.
  for (const [a, b] of [
    [AUTHOR, MATE],
    [MATE, AUTHOR],
    [MATE, MATEPAL],
    [MATEPAL, MATE],
    [AUTHOR, AUTHPAL],
    [AUTHPAL, AUTHOR],
  ]) {
    await db.query(
      `INSERT INTO friendships (user_id, friend_id, status)
       VALUES ($1, $2, 'accepted') ON CONFLICT (user_id, friend_id) DO NOTHING`,
      [a, b],
    );
  }

  const workout = (id, user, distance, route) => ({
    workoutId: id,
    distance,
    localDate,
    date: nowIso,
    timezoneOffset: 0,
    workoutType: "walking",
    deviceEndDate: nowIso,
    calories: 90,
    totalDuration: 900,
    source: "healthkit",
    splits: [],
    ...(route ? { route } : {}),
  });

  const trace = [
    [40.0, -75.0],
    [40.001, -75.001],
  ];
  await uploadWorkouts(AUTHOR, [
    workout("grid-w-author", AUTHOR, 1.4, trace),
    workout("grid-w-author-2", AUTHOR, 1.1),
  ]);
  await uploadWorkouts(MATE, [workout("grid-w-mate", MATE, 1.2, trace)]);
  // The crew route resolves through post_coauthors.workout_id, so MATE's walk
  // has to be linked for the route assertions to mean anything.
  await db.query(
    `UPDATE workouts SET created_at = created_at - INTERVAL '2 hours'
     WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
}

async function main() {
  await seed();

  // ── The collab under test: AUTHOR's post crediting MATE ────────────────
  const collab = await createPost({
    userId: AUTHOR,
    mediaUrl: "/uploads/posts/grid-collab.jpg",
    caption: "we walked",
    workoutId: "grid-w-author",
    localDate,
    shareToFeed: true,
    shareToStory: false,
    statsSnapshot: null,
    isAuto: false,
    includeRoute: true,
    coauthorUserIds: [MATE],
  });
  await db.query(
    `UPDATE post_coauthors SET workout_id = 'grid-w-mate'
     WHERE post_id = $1 AND user_id = $2`,
    [collab.post_id, MATE],
  );

  // 1 — default reach: both circles, exactly as before this change.
  check(
    "collab reaches the author's friend",
    await feedHas(AUTHPAL, collab.post_id),
    true,
  );
  check(
    "collab reaches the coauthor's friend",
    await feedHas(MATEPAL, collab.post_id),
    true,
  );
  check(
    "the coauthor sees their own collab",
    await feedHas(MATE, collab.post_id),
    true,
  );

  // 1b — the coauthor withdraws reach. ONLY their circle loses it.
  await setCoauthorFeedVisibility(MATE, collab.post_id, false);
  check(
    "on_feed=false drops it from the coauthor's friend's feed",
    await feedHas(MATEPAL, collab.post_id),
    false,
  );
  check(
    "...but not from the author's friend's feed",
    await feedHas(AUTHPAL, collab.post_id),
    true,
  );
  check(
    "...and never from the coauthor's own feed",
    await feedHas(MATE, collab.post_id),
    true,
  );
  check(
    "...nor from the author's own feed",
    await feedHas(AUTHOR, collab.post_id),
    true,
  );
  // The photo-only feed asks the same fragment from a different query shape.
  check(
    "getFeed agrees with the unified feed",
    (await getFeed(MATEPAL, 30, null)).some(
      (p) => p.post_id === collab.post_id,
    ),
    false,
  );
  // 3 — direct access (a push tap, a comment, a shared link) must track it, or
  // the post is unreachable from the feed and wide open from a link.
  check(
    "direct access is withdrawn with the reach",
    (await visiblePostAuthors(MATEPAL, collab.post_id)) === null,
    true,
  );
  check(
    "direct access survives for the author's friend",
    (await visiblePostAuthors(AUTHPAL, collab.post_id)) !== null,
    true,
  );

  // 1c — the tag and the grid are untouched by the reach switch. This is the
  // whole reason it is a separate switch from coauthor_on_profile.
  const mateGrid = await getUserPosts(MATE, MATE, 30, null, true);
  check(
    "the collab is still on the coauthor's grid",
    mateGrid.some((p) => p.post_id === collab.post_id),
    true,
  );
  const authorRow = (await getUserPosts(AUTHPAL, AUTHOR, 30, null, false)).find(
    (p) => p.post_id === collab.post_id,
  );
  check(
    "the tag is still rendered to the author's circle",
    authorRow?.coauthor_user_id,
    MATE,
  );

  // 1d — and the two switches are genuinely independent.
  await setCoauthorProfileVisibility(MATE, collab.post_id, false);
  check(
    "hiding it from the grid does not restore reach",
    await feedHas(MATEPAL, collab.post_id),
    false,
  );
  check(
    "...and does remove it from the grid",
    (await gridIds(MATE, MATE)).includes(collab.post_id),
    false,
  );
  await setCoauthorProfileVisibility(MATE, collab.post_id, true);
  await setCoauthorFeedVisibility(MATE, collab.post_id, true);
  check(
    "turning reach back on restores it",
    await feedHas(MATEPAL, collab.post_id),
    true,
  );

  // 2 — the multi-person mirror. post_coauthors carries its own on_feed and
  // setCoauthorFeedVisibility writes both, so a buddy post can't disagree with
  // itself depending on which representation a query happens to read.
  const pcRow = await db.query(
    `SELECT on_feed FROM post_coauthors WHERE post_id = $1 AND user_id = $2`,
    [collab.post_id, MATE],
  );
  check("the switch wrote the multi-person row too", pcRow[0]?.on_feed, true);

  // ── 6 — per-post crew route consent ────────────────────────────────────
  await addCrewPhoto({
    postId: collab.post_id,
    userId: MATE,
    mediaUrl: "/uploads/posts/grid-mate-slide.jpg",
  }).catch(() => {});
  const crewRoute = async (viewer) => {
    const row = (await getUnifiedFeed(viewer, 30, null)).find(
      (r) => r.kind === "post" && r.id === collab.post_id,
    );
    return (
      (row?.coauthors ?? []).find((c) => c.user_id === MATE)?.route != null
    );
  };
  check(
    "the crew route is published by default",
    await crewRoute(AUTHPAL),
    true,
  );

  await setCoauthorRoutePreference(MATE, collab.post_id, false);
  check(
    "a per-post NO withholds it even with the global setting on",
    await crewRoute(AUTHPAL),
    false,
  );

  await db.query(
    `UPDATE notification_settings SET share_route_maps = FALSE WHERE user_id = $1`,
    [MATE],
  );
  await setCoauthorRoutePreference(MATE, collab.post_id, true);
  check(
    "a per-post YES publishes it even with the global setting off",
    await crewRoute(AUTHPAL),
    true,
  );
  await setCoauthorRoutePreference(MATE, collab.post_id, null);
  check(
    "clearing the override falls back to the global setting",
    await crewRoute(AUTHPAL),
    false,
  );
  await db.query(
    `UPDATE notification_settings SET share_route_maps = TRUE WHERE user_id = $1`,
    [MATE],
  );

  // The poster's own include_route still covers the whole card above all of it.
  await db.query(`UPDATE posts SET include_route = FALSE WHERE post_id = $1`, [
    collab.post_id,
  ]);
  check(
    "the poster's no-map choice still suppresses the crew's routes",
    await crewRoute(AUTHPAL),
    false,
  );
  await db.query(`UPDATE posts SET include_route = TRUE WHERE post_id = $1`, [
    collab.post_id,
  ]);

  // ── 4/5 — grid controls ────────────────────────────────────────────────
  // A second post so the grid has an order to reverse, and an auto card so the
  // filter has something to partition.
  const solo = await createPost({
    userId: AUTHOR,
    mediaUrl: "/uploads/posts/grid-solo.jpg",
    caption: "solo",
    workoutId: "grid-w-author-2",
    localDate,
    shareToFeed: true,
    shareToStory: false,
    statsSnapshot: null,
    isAuto: false,
    includeRoute: false,
  });
  const auto = await createPost({
    userId: AUTHOR,
    mediaUrl: "/uploads/posts/grid-auto.jpg",
    caption: null,
    workoutId: null,
    localDate,
    shareToFeed: true,
    shareToStory: false,
    statsSnapshot: { distance: 1.4 },
    isAuto: true,
    includeRoute: true,
  });

  const defaultGrid = await gridIds(AUTHOR, AUTHOR);
  check("the grid has all three posts", defaultGrid.length, 3);
  const oldest = await gridIds(AUTHOR, AUTHOR, { sort: "oldest" });
  check(
    "sort=oldest is the exact reverse of the default page",
    JSON.stringify(oldest),
    JSON.stringify([...defaultGrid].reverse()),
  );
  const photosOnly = await gridIds(AUTHOR, AUTHOR, { filter: "photos" });
  check(
    "filter=photos drops the auto card",
    photosOnly.includes(auto.post_id),
    false,
  );
  check("filter=photos keeps the real photos", photosOnly.length, 2);
  const autoOnly = await gridIds(AUTHOR, AUTHOR, { filter: "auto" });
  check(
    "filter=auto is the complement",
    JSON.stringify(autoOnly),
    JSON.stringify([auto.post_id]),
  );
  const collabsOnly = await gridIds(AUTHOR, AUTHOR, { filter: "collabs" });
  check(
    "filter=collabs is just the collab",
    JSON.stringify(collabsOnly),
    JSON.stringify([collab.post_id]),
  );

  // Pins. The cap is enforced in the UPDATE itself, so two taps can't race it.
  check("pin 1", await setPostPinned(AUTHOR, collab.post_id, true), "ok");
  check("pin 2", await setPostPinned(AUTHOR, solo.post_id, true), "ok");
  check("pin 3", await setPostPinned(AUTHOR, auto.post_id, true), "ok");
  check(
    "re-pinning an already-pinned post is free",
    await setPostPinned(AUTHOR, auto.post_id, true),
    "ok",
  );
  const fourth = await createPost({
    userId: AUTHOR,
    mediaUrl: "/uploads/posts/grid-fourth.jpg",
    caption: "fourth",
    workoutId: null,
    localDate,
    shareToFeed: true,
    shareToStory: false,
    statsSnapshot: null,
    isAuto: false,
    includeRoute: false,
  });
  check(
    `pin ${POST_PIN_LIMIT + 1} is refused`,
    await setPostPinned(AUTHOR, fourth.post_id, true),
    "limit",
  );
  check(
    "unpinning frees a slot",
    await setPostPinned(AUTHOR, auto.post_id, false),
    "ok",
  );
  check(
    "...and the next pin lands",
    await setPostPinned(AUTHOR, fourth.post_id, true),
    "ok",
  );
  check(
    "a pin on someone else's post is not found",
    await setPostPinned(MATE, solo.post_id, true),
    "not_found",
  );

  // THE backwards-compatibility assertion: a caller that says nothing about
  // pins still gets every post inline. A shipped client would otherwise lose
  // a pinned post from its grid entirely.
  const legacyGrid = await gridIds(AUTHOR, AUTHOR);
  check("pins stay inline for a caller that didn't ask", legacyGrid.length, 4);
  const split = await gridIds(AUTHOR, AUTHOR, { splitPins: true });
  check("splitPins removes them from the body", split.length, 1);
  const pins = await getUserPinnedPosts(AUTHOR, AUTHOR);
  check("...and returns them separately", pins.length, 3);
  check("pins come back newest-pinned first", pins[0].post_id, fourth.post_id);
  check(
    "a visitor sees the author's pins too",
    (await getUserPinnedPosts(AUTHPAL, AUTHOR)).length,
    3,
  );
  // A pin is the AUTHOR's curation of their OWN grid — it must not jump the
  // collab to the top of the coauthor's grid.
  check(
    "the coauthor's grid has no pins from the author",
    (await getUserPinnedPosts(MATE, MATE)).length,
    0,
  );

  // ── 7 — highlights ─────────────────────────────────────────────────────
  // A story-only post: invisible on the grid to everyone but its owner, which
  // is exactly what a highlight is for.
  const story = await createPost({
    userId: AUTHOR,
    mediaUrl: "/uploads/posts/grid-story.jpg",
    caption: null,
    workoutId: null,
    localDate,
    shareToFeed: false,
    shareToStory: true,
    statsSnapshot: null,
    isAuto: false,
    includeRoute: false,
  });
  check(
    "a story-only post is not on the grid for a friend",
    (await gridIds(AUTHPAL, AUTHOR)).includes(story.post_id),
    false,
  );

  const created = await createHighlight(AUTHOR, {
    title: "Morning walks",
    post_ids: [story.post_id, solo.post_id],
  });
  check("createHighlight succeeded", created.ok, true);
  const hid = created.highlight_id;

  const notMine = await createHighlight(MATE, {
    title: "Yours actually",
    post_ids: [solo.post_id],
  });
  check(
    "a highlight cannot hold someone else's post",
    notMine.ok === false && notMine.error === "no_posts",
    true,
  );
  check(
    "an empty title is refused",
    (await createHighlight(AUTHOR, { title: "  ", post_ids: [solo.post_id] }))
      .error,
    "invalid_title",
  );

  const asFriend = await getHighlight(AUTHPAL, hid);
  check("a friend can open the highlight", asFriend?.items.length, 2);
  check(
    "...including the story that would never reach the grid",
    asFriend?.items.some((p) => p.post_id === story.post_id),
    true,
  );
  const rail = await listUserHighlights(AUTHPAL, AUTHOR);
  check("the rail lists it", rail.length, 1);
  check("the rail counts its members", rail[0].item_count, 2);
  check("the rail resolves a cover", rail[0].cover_media_url != null, true);

  // Privacy and blocks are the highlight's rules too, not the grid's alone.
  await db.query(
    `UPDATE notification_settings SET workout_visibility = 'private' WHERE user_id = $1`,
    [AUTHOR],
  );
  check(
    "a private owner's highlight is empty to a friend",
    (await getHighlight(AUTHPAL, hid))?.items.length,
    0,
  );
  check(
    "...but never to the owner",
    (await getHighlight(AUTHOR, hid))?.items.length,
    2,
  );
  await db.query(
    `UPDATE notification_settings SET workout_visibility = 'friends' WHERE user_id = $1`,
    [AUTHOR],
  );
  await db.query(
    `INSERT INTO user_blocks (blocker_id, blocked_id) VALUES ($1, $2)
     ON CONFLICT DO NOTHING`,
    [AUTHPAL, AUTHOR],
  );
  check(
    "a block empties it in the blocking direction",
    (await getHighlight(AUTHPAL, hid))?.items.length,
    0,
  );
  await db.query(`DELETE FROM user_blocks WHERE blocker_id = $1`, [AUTHPAL]);

  // Reordering is the same call as adding: the client sends the list it wants.
  await updateHighlight(AUTHOR, hid, {
    title: "Sunday loops",
    post_ids: [solo.post_id, story.post_id],
    cover_post_id: story.post_id,
  });
  const reordered = await getHighlight(AUTHOR, hid);
  check("renamed", reordered?.title, "Sunday loops");
  check("re-ordered", reordered?.items[0].post_id, solo.post_id);
  check(
    "a cover outside the highlight is refused",
    (await updateHighlight(AUTHOR, hid, { cover_post_id: collab.post_id }))
      .ok === true &&
      (
        await db.query(
          `SELECT cover_post_id FROM post_highlights WHERE highlight_id = $1`,
          [hid],
        )
      )[0].cover_post_id === story.post_id,
    true,
  );
  // An uploaded cover: it must win over the member photo on the read every
  // profile does, and the empty string must put the member photo back. Both
  // are COALESCE precedence in a subquery — reading it proves nothing.
  await updateHighlight(AUTHOR, hid, {
    cover_image_url: "/uploads/posts/grid-cover.jpg",
  });
  const covered = (await listUserHighlights(AUTHOR, AUTHOR))[0];
  check(
    "an uploaded cover wins over the member photo",
    covered.cover_media_url,
    "/uploads/posts/grid-cover.jpg",
  );
  check("...and is reported separately", covered.cover_image_url, "/uploads/posts/grid-cover.jpg");
  await updateHighlight(AUTHOR, hid, { title: "Sunday loops" });
  check(
    "a write that doesn't mention the cover leaves it alone",
    (await listUserHighlights(AUTHOR, AUTHOR))[0].cover_image_url,
    "/uploads/posts/grid-cover.jpg",
  );
  await updateHighlight(AUTHOR, hid, { cover_image_url: "" });
  const uncovered = (await listUserHighlights(AUTHOR, AUTHOR))[0];
  check("clearing it restores the member photo", uncovered.cover_image_url, null);
  check(
    "...which is the chosen member's",
    uncovered.cover_media_url,
    "/uploads/posts/grid-story.jpg",
  );

  check(
    "emptying a highlight is refused (it would open onto nothing)",
    (await updateHighlight(AUTHOR, hid, { post_ids: [] })).error,
    "no_posts",
  );
  check(
    "someone else cannot edit it",
    (await updateHighlight(MATE, hid, { title: "mine now" })).error,
    "not_found",
  );

  check("delete removes it", await deleteHighlight(AUTHOR, hid), true);
  check(
    "...and leaves the posts alone",
    (await gridIds(AUTHOR, AUTHOR)).includes(solo.post_id),
    true,
  );

  if (!process.env.KEEP_SEED) await cleanup();

  console.log(
    failures === 0
      ? "grid-controls-check: all assertions passed"
      : `grid-controls-check: ${failures} FAILED`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch(async (err) => {
  console.error(err);
  await cleanup().catch(() => {});
  process.exit(1);
});
