/**
 * Where a buddy walk's post reaches its OWN participants.
 *
 * A buddy walk is ONE post for N people. For everyone except whoever pressed
 * Post it therefore arrives as somebody else's card with their name on it —
 * structurally identical to a "tag" — and every rule written for tags was
 * applied to it. That is wrong in a way no error surfaces: a tag is something
 * another person did that mentions you, while this is the walk YOU took, and
 * the one-post-per-walk rule deliberately stops you having a card of your own.
 *
 * Three separate gaps, all of which reported as "my walk isn't there":
 *
 *  1. FEED. The two post arms of the unified feed both run through the
 *     viewer's circle: the author, or the LEGACY SCALAR coauthor. A walk
 *     reaches friends-of-members, so the poster needn't be your friend, and
 *     the scalar holds exactly ONE person — so on a crew of five, four of us
 *     could be credited on the card and never see it in our own feed.
 *  2. GRID. `userGridWhere`, `getUserTaggedPosts` and the "Add to grid" write
 *     all asked the same scalar. For a crew member the write matched no row
 *     (404) and the read never looked at them, so the walk could not be put on
 *     their profile by any means — and was not even in their Tagged tab.
 *  3. AUTO CARDS. The grid's photo-first gate read the AUTHOR's
 *     `auto_posts_on_profile` when building a COAUTHOR's grid, and sat outside
 *     the per-post override — so whether your walk could appear on your
 *     profile depended on a switch in someone else's settings, and tapping
 *     "Add to grid" on that post did nothing at all.
 *
 * None of this throws. Every failure is a card that is quietly somewhere else,
 * which is why it is asserted against a real database rather than read.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/buddy-walk-reach-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import {
  getUnifiedFeed,
  getUserPosts,
  getUserTaggedPosts,
  setCoauthorProfileVisibility,
} from "../dist/services/postService.js";

const db = PostgresService.getInstance();

const AUTHOR = "bwr-author"; // posted the walk
const FIRST = "bwr-first"; // credited, AND the legacy scalar coauthor
const CREW = "bwr-crew"; // credited in post_coauthors only
const ALL = [AUTHOR, FIRST, CREW];

let failures = 0;
function check(label, actual, expected) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${actual} (expected ${expected})`,
  );
}

const holds = (rows, postId) =>
  rows.some((r) => String(r.post_id ?? r.id) === String(postId));

async function cleanup() {
  await db.query(
    `DELETE FROM in_app_notifications WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM post_coauthors WHERE user_id = ANY($1::text[])`, [
    ALL,
  ]);
  await db.query(`DELETE FROM posts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(
    `DELETE FROM buddy_session_participants WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM buddy_sessions WHERE host_user_id = ANY($1::text[])`, [
    ALL,
  ]);
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(
    `DELETE FROM notification_settings WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(
    `DELETE FROM friendships WHERE user_id = ANY($1::text[]) OR friend_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM users WHERE user_id = ANY($1::text[])`, [ALL]);
}

/**
 * One walk, three people, and NO friendships at all.
 *
 * That is the point of the seed rather than a shortcut: it isolates the walk
 * itself as the only reason the post could reach anyone. Friend-of-a-member
 * joins are supported, so being on a walk with someone you have not added is
 * an ordinary case, not a contrived one.
 *
 * `isAuto` seeds the first finisher's route card — the walk's card when
 * nobody took a photo, and by far the most common shape.
 */
async function seed({ isAuto, authorHidesAutos, taggedOnGrid }) {
  for (const id of ALL)
    await db.query(
      `INSERT INTO users (user_id, apple_sub, email, username, first_name, last_name)
       VALUES ($1, $2, $3, $4, $5, 'Walker')
       ON CONFLICT (user_id) DO NOTHING`,
      [id, `sub-${id}`, `${id}@example.com`, id, id],
    );
  await db.query(
    `INSERT INTO notification_settings (user_id, auto_posts_on_profile)
     VALUES ($1, $2)
     ON CONFLICT (user_id) DO UPDATE SET auto_posts_on_profile = $2`,
    [AUTHOR, !authorHidesAutos],
  );
  for (const id of [FIRST, CREW])
    await db.query(
      `INSERT INTO notification_settings (user_id, tagged_posts_on_profile)
       VALUES ($1, $2)
       ON CONFLICT (user_id) DO UPDATE SET tagged_posts_on_profile = $2`,
      [id, taggedOnGrid],
    );

  const sessionId = (
    await db.query(
      `INSERT INTO buddy_sessions
         (join_code, host_user_id, mode, activity_type, status, origin,
          local_date, started_at, ended_at)
       VALUES ('bwrwlk', $1, 'together', 'walking', 'completed', 'invite',
               CURRENT_DATE, NOW() - INTERVAL '1 hour', NOW() - INTERVAL '20 minutes')
       RETURNING id`,
      [AUTHOR],
    )
  )[0].id;

  for (const id of ALL) {
    const workoutId = `bwr-w-${id}`;
    await db.query(
      `INSERT INTO workouts
         (workout_id, user_id, workout_type, distance, total_duration,
          device_end_date, date, local_date, timezone_offset, calories, steps,
          feed_role)
       VALUES ($1, $2, 'walking', 1.4, 2400, NOW() - INTERVAL '20 minutes',
               CURRENT_DATE, CURRENT_DATE, 0, 120, 3000, 'daily_mile')
       ON CONFLICT (workout_id) DO NOTHING`,
      [workoutId, id],
    );
    // Past the 10-minute camera hold, or the walk's own legs are suppressed
    // for a reason that has nothing to do with what is being tested here.
    await db.query(
      `UPDATE workouts SET created_at = NOW() - INTERVAL '2 hours'
        WHERE workout_id = $1`,
      [workoutId],
    );
    await db.query(
      `INSERT INTO buddy_session_participants
         (session_id, user_id, status, workout_id, final_distance_miles, duration_seconds)
       VALUES ($1, $2, 'finished', $3, 1.4, 2400)`,
      [sessionId, id, workoutId],
    );
  }

  // Both representations, exactly as the recap wizard writes them: a crew row
  // per participant AND the legacy scalars pointing at the first one.
  const postId = (
    await db.query(
      `INSERT INTO posts (user_id, media_url, caption, workout_id, local_date,
                          share_to_feed, is_auto, include_route,
                          buddy_session_id, coauthor_user_id, coauthor_status)
       VALUES ($1, '/uploads/posts/bwr-author-1.jpg', 'us, out there',
               'bwr-w-${AUTHOR}', CURRENT_DATE, TRUE, $2, TRUE, $3, $4, 'accepted')
       RETURNING post_id`,
      [AUTHOR, isAuto, sessionId, FIRST],
    )
  )[0].post_id;
  for (const id of [FIRST, CREW])
    await db.query(
      `INSERT INTO post_coauthors (post_id, user_id, status, buddy_session_id)
       VALUES ($1, $2, 'accepted', $3)`,
      [postId, id, sessionId],
    );
  return postId;
}

async function main() {
  await cleanup();

  // ── 1. The feed ────────────────────────────────────────────────────────
  // Nobody here is anybody's friend. The walk is the only connection, and it
  // is enough: this is the card for a mile each of these people actually
  // walked, and it is the only one they get.
  let postId = await seed({
    isAuto: false,
    authorHidesAutos: false,
    taggedOnGrid: true,
  });
  check(
    "the poster's own walk is in their feed",
    holds(await getUnifiedFeed(AUTHOR, 30, null), postId),
    true,
  );
  check(
    "the first-credited walker's walk is in their feed",
    holds(await getUnifiedFeed(FIRST, 30, null), postId),
    true,
  );
  check(
    "a CREW member's walk is in their feed, with no friendship anywhere",
    holds(await getUnifiedFeed(CREW, 30, null), postId),
    true,
  );

  // The tagged-posts switch is about OTHER people's posts about you. It must
  // not be able to answer for a walk you took — which is the reported bug.
  await cleanup();
  postId = await seed({
    isAuto: false,
    authorHidesAutos: false,
    taggedOnGrid: false,
  });
  check(
    "quieting tagged posts does NOT remove my own walk from my feed",
    holds(await getUnifiedFeed(CREW, 30, null), postId),
    true,
  );

  // ...but the reach switch still governs OTHER people's feeds. A buddy walk
  // being exempt from the tag rules must not have widened anyone's audience.
  await db.query(
    `UPDATE post_coauthors SET on_feed = FALSE WHERE post_id = $1 AND user_id = $2`,
    [postId, CREW],
  );
  await db.query(
    `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, 'accepted'),
       ($2, $1, 'accepted') ON CONFLICT DO NOTHING`,
    [CREW, AUTHOR],
  );
  check(
    "...and I still see it after turning my own reach off",
    holds(await getUnifiedFeed(CREW, 30, null), postId),
    true,
  );

  // ── 2. The grid and the Tagged tab ─────────────────────────────────────
  await cleanup();
  postId = await seed({
    isAuto: false,
    authorHidesAutos: false,
    taggedOnGrid: true,
  });
  check(
    "a crew member IS tagged in the walk",
    holds(await getUserTaggedPosts(CREW, CREW, 30, null), postId),
    true,
  );
  check(
    "...and the walk is on their grid by default",
    holds(await getUserPosts(CREW, CREW, 30, null, false, {}), postId),
    true,
  );

  // Opting out must still work, in both representations — this is the whole
  // reason the switch exists and the easy thing to break while widening it.
  check(
    "a crew member can take the walk OFF their grid",
    (await setCoauthorProfileVisibility(CREW, postId, false)) !== null &&
      !holds(await getUserPosts(CREW, CREW, 30, null, false, {}), postId),
    true,
  );
  check(
    "...and it stays in their Tagged tab, which is not the grid",
    holds(await getUserTaggedPosts(CREW, CREW, 30, null), postId),
    true,
  );
  check(
    "...and it stays on the AUTHOR's grid, whose post it is",
    holds(await getUserPosts(AUTHOR, AUTHOR, 30, null, false, {}), postId),
    true,
  );

  // ── 3. "Add to grid" against a blanket preference ──────────────────────
  // The reported failure: tapped Add to grid, the write succeeded, nothing
  // appeared. The walk's card is the first finisher's ROUTE card, and the
  // gate was reading the AUTHOR's photo-first preference.
  await cleanup();
  postId = await seed({
    isAuto: true,
    authorHidesAutos: true,
    taggedOnGrid: false,
  });
  for (const id of [FIRST, CREW]) {
    check(
      `${id === FIRST ? "the first-credited walker" : "a crew member"} can add the walk to their grid`,
      (await setCoauthorProfileVisibility(id, postId, true)) !== null,
      true,
    );
    check(
      "...and it actually appears there",
      holds(await getUserPosts(id, id, 30, null, false, {}), postId),
      true,
    );
  }
  check(
    "the author's own photo-first setting still governs the AUTHOR's grid",
    holds(await getUserPosts(AUTHOR, AUTHOR, 30, null, false, {}), postId),
    false,
  );

  // ── 4. A crew member who added THEIR OWN photo posted the walk ─────────
  // One post per walk is why they have no card of their own, so their slide
  // makes it their post: on their Posts grid even with tagged posts quieted
  // and on the first finisher's route card under the author's photo-first
  // setting — and out of their Tagged tab, since it isn't a tag.
  await cleanup();
  postId = await seed({
    isAuto: true,
    authorHidesAutos: true,
    taggedOnGrid: false,
  });
  await db.query(
    `UPDATE post_coauthors SET media_url = '/uploads/posts/bwr-crew-1.jpg'
      WHERE post_id = $1 AND user_id = $2`,
    [postId, CREW],
  );
  check(
    "a crew member who added their photo has the walk on their grid",
    holds(await getUserPosts(CREW, CREW, 30, null, false, {}), postId),
    true,
  );
  await db.query(
    `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, 'accepted'),
       ($2, $1, 'accepted') ON CONFLICT DO NOTHING`,
    [CREW, FIRST],
  );
  check(
    "...and a friend reading their grid sees it there too",
    holds(await getUserPosts(FIRST, CREW, 30, null, false, {}), postId),
    true,
  );
  check(
    "...and it is NOT in their Tagged tab",
    holds(await getUserTaggedPosts(CREW, CREW, 30, null), postId),
    false,
  );
  check(
    "...while a crew member with no photo on it keeps the tag rules",
    holds(await getUserPosts(FIRST, FIRST, 30, null, false, {}), postId),
    false,
  );
  check(
    "a photo contributor can still take it OFF their grid",
    (await setCoauthorProfileVisibility(CREW, postId, false)) !== null &&
      !holds(await getUserPosts(CREW, CREW, 30, null, false, {}), postId),
    true,
  );
  check(
    "...and then it falls back to their Tagged tab rather than vanishing",
    holds(await getUserTaggedPosts(CREW, CREW, 30, null), postId),
    true,
  );

  await cleanup();
  console.log(
    failures === 0
      ? "buddy-walk-reach-check: all assertions passed"
      : `buddy-walk-reach-check: ${failures} FAILED`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch(async (err) => {
  console.error(err);
  await cleanup().catch(() => {});
  process.exit(1);
});
