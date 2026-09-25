/**
 * The AUTHOR's Flamey on their cards — `author_flamey` on every post-shaped
 * read and on the feed's raw-workout arm.
 *
 * The routeless/indoor card draws a Flamey cheerleader for Fun-dashboard
 * viewers; it should be the AUTHOR's own customised Flamey, so every surface
 * that can draw that card carries `{look, name}` for its author — but only
 * when the author themselves draws the Fun dashboard (NULL/'modern' ⇒ null).
 *
 * One fragment (`authorFlameySql`) rides POST_COLUMNS (→ POST_SELECT and
 * CREATED_POST_SELECT) and FEED_ENTRY_PROJECTION (→ both unified-feed arms and
 * getFeedEntryForPost). A surface that misses it draws the generic Flamey and
 * nobody reports it, so this pins, per surface:
 *   1. Fun author with a saved look + name → exactly that, on the feed's post
 *      arm, the feed's WORKOUT arm, the legacy feed, the single-post read, the
 *      profile grid (== feed), pinned, memories and the created-post shape.
 *   2. Fun author with nothing saved → {look:null, name:null} (auto, "Flamey").
 *   3. Modern author, and a NULL-style (pre-field build) author → null.
 *   4. Nothing else moves: the same entries read with the author on Fun vs
 *      Modern are identical once `author_flamey` is removed.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/flamey-author-look-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import {
  getUnifiedFeed,
  getFeed,
  getFeedEntryForPost,
  getUserPosts,
  getUserPinnedPosts,
  getOwnPostMemories,
} from "../dist/services/postService.js";
import { CREATED_POST_SELECT } from "../dist/services/posts/postSql.js";
import { FLAMEY_CATALOG } from "../dist/services/flameyCatalog.js";

const db = PostgresService.getInstance();

const VIEWER = "fal-viewer";
const FUN = "fal-fun"; // Fun, saved look + name
const BARE = "fal-bare"; // Fun, nothing saved
const MODERN = "fal-modern";
const LEGACY = "fal-legacy"; // dashboard_style NULL
const AUTHORS = [FUN, BARE, MODERN, LEGACY];
const ALL = [VIEWER, ...AUTHORS];

// A real catalog item in its real slot, so the stored look is one the write
// path could have accepted.
const [firstItem] = FLAMEY_CATALOG.values();
const LOOK = { [firstItem.slot]: firstItem.id };
const NAME = "Sparky";

let failures = 0;
function check(label, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  const ok = a === e;
  if (!ok) failures++;
  console.log(`${ok ? "ok  " : "FAIL"}  ${label} → ${a}${ok ? "" : ` (expected ${e})`}`);
}

async function cleanup() {
  await db.query(`DELETE FROM in_app_notifications WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM posts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM notification_settings WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(
    `DELETE FROM friendships WHERE user_id = ANY($1::text[]) OR friend_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM users WHERE user_id = ANY($1::text[])`, [ALL]);
}

const STYLE = { [FUN]: "fun", [BARE]: "fun", [MODERN]: "modern", [LEGACY]: null };

async function seed() {
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, apple_sub, email, username, first_name, last_name,
                          dashboard_style, flamey_look, flamey_name)
       VALUES ($1::varchar, $2, $3, $1::varchar, $1::varchar, 'Walker', $4, $5::jsonb, $6)`,
      [
        id,
        `sub-${id}`,
        `${id}@example.com`,
        STYLE[id] ?? null,
        id === FUN ? JSON.stringify(LOOK) : null,
        id === FUN ? NAME : null,
      ],
    );
  }
  const ids = {};
  for (const a of AUTHORS) {
    await db.query(
      `INSERT INTO friendships (user_id, friend_id, status)
       VALUES ($1, $2, 'accepted'), ($2, $1, 'accepted')`,
      [VIEWER, a],
    );
    // Two days: yesterday's walk carries a photo post (the post arm), today's
    // is a bare workout (the workout arm). Both aged past the 10-minute
    // camera hold, which otherwise withholds the raw card from friends.
    for (const [suffix, daysAgo] of [["post", 1], ["raw", 0]]) {
      await db.query(
        `INSERT INTO workouts
           (workout_id, user_id, workout_type, distance, total_duration,
            device_end_date, date, local_date, timezone_offset, calories, steps,
            feed_role, created_at)
         VALUES ($1, $2, 'walking', 1.1, 1500,
                 NOW() - ($3 || ' days')::interval - INTERVAL '2 hours',
                 (NOW() - ($3 || ' days')::interval)::date,
                 (NOW() - ($3 || ' days')::interval)::date, 0, 90, 2200,
                 'daily_mile', NOW() - ($3 || ' days')::interval - INTERVAL '2 hours')`,
        [`fal-w-${suffix}-${a}`, a, String(daysAgo)],
      );
    }
    const postId = (
      await db.query(
        `INSERT INTO posts (user_id, media_url, caption, workout_id, local_date,
                            share_to_feed, is_auto, include_route, created_at, pinned_at)
         VALUES ($1, '/uploads/posts/' || $1 || '-1.jpg', 'indoor mile', $2,
                 (NOW() - INTERVAL '1 day')::date, TRUE, FALSE, TRUE,
                 NOW() - INTERVAL '1 day' - INTERVAL '1 hour', NOW())
         RETURNING post_id`,
        [a, `fal-w-post-${a}`],
      )
    )[0].post_id;
    // Same calendar day a year ago, for "On this day" memories.
    await db.query(
      `INSERT INTO posts (user_id, media_url, caption, local_date, share_to_feed, is_auto,
                          include_route, created_at)
       VALUES ($1, '/uploads/posts/' || $1 || '-old.jpg', 'a year ago',
               (CURRENT_DATE - INTERVAL '1 year')::date, TRUE, FALSE, TRUE,
               NOW() - INTERVAL '1 year')`,
      [a],
    );
    ids[a] = postId;
  }
  return ids;
}

/** Every surface's `author_flamey` for one author, keyed by surface. */
async function surfaces(author, postId) {
  const feed = await getUnifiedFeed(VIEWER, 50, null);
  const postEntry = feed.find((r) => r.kind === "post" && r.id === String(postId));
  const workoutEntry = feed.find(
    (r) => r.kind === "workout" && r.workout_id === `fal-w-raw-${author}`,
  );
  const legacy = (await getFeed(VIEWER, 50, null)).find(
    (r) => String(r.post_id) === String(postId),
  );
  const single = await getFeedEntryForPost(VIEWER, String(postId));
  const grid = (await getUserPosts(VIEWER, author, 30, null)).find(
    (r) => String(r.post_id) === String(postId),
  );
  const pinned = (await getUserPinnedPosts(VIEWER, author)).find(
    (r) => String(r.post_id) === String(postId),
  );
  const today = (await db.query(`SELECT CURRENT_DATE::text AS d`))[0].d;
  const memories = await getOwnPostMemories(author, today);
  // createPost's own shape: CREATED_POST_SELECT over the upserted row, `$1` =
  // the author. Driven directly because the real door needs media on disk.
  const created = (
    await db.query(
      `WITH inserted AS (SELECT * FROM posts WHERE post_id = $2::uuid)
       ${CREATED_POST_SELECT}
       FROM inserted p JOIN users u ON u.user_id = p.user_id`,
      [author, postId],
    )
  )[0];
  return {
    rows: { postEntry, workoutEntry, legacy, single, grid, pinned, memory: memories[0], created },
    flamey: {
      "feed post arm": postEntry?.author_flamey,
      "feed WORKOUT arm": workoutEntry?.author_flamey,
      "legacy feed": legacy?.author_flamey,
      "single post (getFeedEntryForPost)": single?.author_flamey,
      "profile grid": grid?.author_flamey,
      "pinned": pinned?.author_flamey,
      "memories": memories[0]?.author_flamey,
      "created-post shape": created?.author_flamey,
    },
  };
}

const withoutFlamey = (row) => {
  if (!row) return row;
  const { author_flamey: _drop, ...rest } = row;
  return rest;
};

async function main() {
  await cleanup();
  const posts = await seed();

  // ── 1–3. Per author, every surface ──────────────────────────────────────
  const expected = {
    [FUN]: { look: LOOK, name: NAME },
    [BARE]: { look: null, name: null },
    [MODERN]: null,
    [LEGACY]: null,
  };
  for (const a of AUTHORS) {
    const { rows, flamey } = await surfaces(a, posts[a]);
    for (const [name, row] of Object.entries(rows)) {
      check(`${a}: ${name} row found and carries the key`, !!row && "author_flamey" in row, true);
    }
    for (const [surface, value] of Object.entries(flamey)) {
      check(`${a}: ${surface}`, value, expected[a]);
    }
    check(
      `${a}: grid == feed`,
      JSON.stringify(flamey["profile grid"]) === JSON.stringify(flamey["feed post arm"]),
      true,
    );
  }

  // ── 4. Nothing else moves ─────────────────────────────────────────────────
  // The same author read on Fun and then on Modern: every other field of
  // every surface is identical.
  const onFun = (await surfaces(FUN, posts[FUN])).rows;
  await db.query(`UPDATE users SET dashboard_style = 'modern' WHERE user_id = $1`, [FUN]);
  const onModern = await surfaces(FUN, posts[FUN]);
  for (const name of Object.keys(onFun)) {
    check(
      `${name}: the rest of the entry is unchanged by the author's style`,
      JSON.stringify(withoutFlamey(onFun[name])) === JSON.stringify(withoutFlamey(onModern.rows[name])),
      true,
    );
  }
  check("switching to Modern withdraws it (feed)", onModern.flamey["feed post arm"], null);
  // The look is kept, not lost, when they switch back.
  await db.query(`UPDATE users SET dashboard_style = 'fun' WHERE user_id = $1`, [FUN]);
  check(
    "switching back to Fun restores the saved look",
    (await surfaces(FUN, posts[FUN])).flamey["feed WORKOUT arm"],
    { look: LOOK, name: NAME },
  );

  await cleanup();
  if (failures) {
    console.error(`\nflamey-author-look-check: ${failures} failure(s)`);
    process.exit(1);
  }
  console.log("\nflamey-author-look-check: all assertions passed");
  process.exit(0);
}

main().catch(async (err) => {
  console.error(err);
  await cleanup().catch(() => {});
  process.exit(1);
});
