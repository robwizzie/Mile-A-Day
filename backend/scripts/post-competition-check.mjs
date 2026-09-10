/**
 * The competition a post CARRIES, and who may open it.
 *
 * `CompetitionFlairRow` was removed because it drew from the plain
 * `competitions` list, so every card announced a closed group's user-typed
 * name to the poster's whole circle on a walk that had nothing to do with it.
 * `posts.competition_id` is the opt-in replacement: it records the one
 * competition the poster STICKERED, and the client draws a tappable chip only
 * when that id resolves to an entry the viewer is also in.
 *
 * Every way this breaks is silent — a chip that resolves to nothing, a chip
 * offered to a stranger, or a stickered competition quietly cut by the
 * `competitions` LIMIT 3 — so it is asserted rather than read:
 *
 *   1. a member's claim is stored; a NON-member's claim stores NULL (the
 *      INSERT validates membership in SQL — the client is not trusted)
 *   2. it rides every post-shaped read: the create response, the profile
 *      grid, the single-post read and the unified feed
 *   3. `viewer_in` on the matching entry is TRUE for a fellow member and
 *      FALSE for a friend who isn't in it — that flag IS the gate
 *   4. the stickered competition is never the one the LIMIT 3 cuts, even when
 *      the author is in more competitions than the array holds and the
 *      stickered one ends last
 *   5. re-posting with the sticker OFF clears the chip (the upsert takes
 *      EXCLUDED wholesale rather than COALESCE, so removing it removes it)
 *   6. a workout entry in the feed carries no competition_id at all
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/post-competition-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import {
  createPost,
  getUserPosts,
  getFeedEntryForPost,
  getUnifiedFeed,
} from "../dist/services/postService.js";
import { uploadWorkouts } from "../dist/services/workoutService.js";

const db = PostgresService.getInstance();

const AUTHOR = "pcomp-author";
const MATE = "pcomp-mate"; // friend AND fellow competitor — gets the chip
const PAL = "pcomp-pal"; // friend, NOT in the competition — no chip
const ALL = [AUTHOR, MATE, PAL];

// Five competitions so the array's LIMIT 3 actually bites. `LAST` ends after
// all of them, so it can only appear if the pin ordering works.
const COMPS = ["pcomp-c1", "pcomp-c2", "pcomp-c3", "pcomp-c4", "pcomp-c-last"];
const LAST = "pcomp-c-last";
const OUTSIDER_COMP = "pcomp-c-outsider"; // AUTHOR is NOT in this one

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

async function cleanup() {
  await db.query(
    `DELETE FROM in_app_notifications WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM post_coauthors WHERE user_id = ANY($1::text[])`, [
    ALL,
  ]);
  await db.query(`DELETE FROM posts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(
    `DELETE FROM competition_users WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM competitions WHERE id = ANY($1::text[])`, [
    [...COMPS, OUTSIDER_COMP],
  ]);
  await db.query(
    `DELETE FROM friendships WHERE user_id = ANY($1::text[])
       OR friend_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(
    `DELETE FROM notification_settings WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
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
  // Both witnesses are friends with the author, so the only thing separating
  // them is competition membership — which is the rule under test.
  for (const [a, b] of [
    [AUTHOR, MATE],
    [MATE, AUTHOR],
    [AUTHOR, PAL],
    [PAL, AUTHOR],
  ]) {
    await db.query(
      `INSERT INTO friendships (user_id, friend_id, status)
       VALUES ($1, $2, 'accepted') ON CONFLICT (user_id, friend_id) DO NOTHING`,
      [a, b],
    );
  }

  // The four short ones end today; LAST ends a month out, so end_date ordering
  // alone would push it out of the LIMIT 3.
  const endFor = (id) => (id === LAST ? "NOW() + INTERVAL '30 days'" : "NOW()");
  for (const id of [...COMPS, OUTSIDER_COMP]) {
    await db.query(
      `INSERT INTO competitions
         (id, competition_name, start_date, end_date, workouts, type, options, owner)
       VALUES ($1, $2, NOW() - INTERVAL '5 days', ${endFor(id)},
               '[]'::jsonb, 'clash', '{}'::jsonb, $3)`,
      [id, `Comp ${id}`, AUTHOR],
    );
  }
  for (const id of COMPS) {
    await db.query(
      `INSERT INTO competition_users (competition_id, user_id, invite_status)
       VALUES ($1, $2, 'accepted')`,
      [id, AUTHOR],
    );
  }
  // MATE shares only the one the author will sticker. PAL shares none.
  await db.query(
    `INSERT INTO competition_users (competition_id, user_id, invite_status)
     VALUES ($1, $2, 'accepted')`,
    [LAST, MATE],
  );
  // AUTHOR is a mere INVITEE here — an unanswered invite is not membership.
  await db.query(
    `INSERT INTO competition_users (competition_id, user_id, invite_status)
     VALUES ($1, $2, 'pending')`,
    [OUTSIDER_COMP, AUTHOR],
  );

  await uploadWorkouts(AUTHOR, [
    {
      workoutId: "pcomp-w1",
      distance: 1.4,
      localDate,
      date: nowIso,
      timezoneOffset: 0,
      workoutType: "walking",
      deviceEndDate: nowIso,
      calories: 90,
      totalDuration: 900,
      source: "healthkit",
      splits: [],
    },
  ]);
  // Past the 10-minute camera hold, or the workout arm suppresses the card and
  // the feed assertions pass vacuously.
  await db.query(
    `UPDATE workouts SET created_at = created_at - INTERVAL '2 hours'
     WHERE user_id = $1`,
    [AUTHOR],
  );
}

const post = (over = {}) => ({
  userId: AUTHOR,
  mediaUrl: "/uploads/posts/pcomp-author-1.jpg",
  caption: null,
  workoutId: "pcomp-w1",
  localDate,
  shareToFeed: true,
  shareToStory: false,
  statsSnapshot: null,
  isAuto: false,
  ...over,
});

const entryFor = (rows, id) =>
  rows.find((r) => r.kind === "post" && r.id === id) ?? null;

async function main() {
  await seed();

  // ── 1. A member's claim is kept ───────────────────────────────────────
  const created = await createPost(post({ competitionId: LAST }));
  check(
    "create stores the stickered competition",
    created.competition_id,
    LAST,
  );

  // ── 2. It rides every post-shaped read ────────────────────────────────
  const [grid] = await getUserPosts(AUTHOR, AUTHOR, 10, null, true);
  check("profile grid carries it", grid?.competition_id, LAST);

  const single = await getFeedEntryForPost(MATE, created.post_id);
  check("single-post read carries it", single?.competition_id, LAST);

  const mateFeed = await getUnifiedFeed(MATE, 30, null);
  const mateEntry = entryFor(mateFeed, created.post_id);
  check("unified feed carries it", mateEntry?.competition_id, LAST);

  // ── 3. viewer_in IS the gate ──────────────────────────────────────────
  const mateRef = (mateEntry?.competitions ?? []).find((c) => c.id === LAST);
  check("a fellow member's entry resolves", mateRef?.id, LAST);
  check("...and says they are in it", mateRef?.viewer_in, true);

  const palFeed = await getUnifiedFeed(PAL, 30, null);
  const palEntry = entryFor(palFeed, created.post_id);
  const palRef = (palEntry?.competitions ?? []).find((c) => c.id === LAST);
  check("a non-member still sees the post", palEntry?.id, created.post_id);
  check("...and the id it stickered", palEntry?.competition_id, LAST);
  check("...but is told they are NOT in it", palRef?.viewer_in, false);

  // ── 4. The stickered comp survives the LIMIT 3 ────────────────────────
  // The author is in five; LAST ends a month after the other four, so without
  // the pin it is the first thing end_date ordering drops.
  check("the array is still capped", mateEntry?.competitions?.length, 3);
  check(
    "...and the stickered one is in it anyway",
    (mateEntry?.competitions ?? []).some((c) => c.id === LAST),
    true,
  );
  // Nothing pinned ⇒ the old ordering, i.e. LAST is cut.
  const plain = await createPost(
    post({ workoutId: null, mediaUrl: "/uploads/posts/pcomp-author-2.jpg" }),
  );
  const plainEntry = entryFor(
    await getUnifiedFeed(MATE, 30, null),
    plain.post_id,
  );
  check(
    "without a sticker the ordering is untouched",
    plainEntry?.competition_id,
    null,
  );
  check(
    "...so the last-ending comp is cut as before",
    (plainEntry?.competitions ?? []).some((c) => c.id === LAST),
    false,
  );

  // ── 5. A claim to a competition the author is not in stores NULL ──────
  const foreign = await createPost(
    post({
      workoutId: null,
      mediaUrl: "/uploads/posts/pcomp-author-3.jpg",
      competitionId: OUTSIDER_COMP,
    }),
  );
  check("an unanswered invite is not membership", foreign.competition_id, null);
  const bogus = await createPost(
    post({
      workoutId: null,
      mediaUrl: "/uploads/posts/pcomp-author-4.jpg",
      competitionId: "pcomp-does-not-exist",
    }),
  );
  check("an id that doesn't exist stores nothing", bogus.competition_id, null);

  // ── 6. Turning the sticker off removes the chip ───────────────────────
  // The auto card is the replaceable slot, so this is the upsert path: an
  // auto post carrying one, replaced by a user post that carries none.
  await db.query(`DELETE FROM posts WHERE post_id = $1`, [created.post_id]);
  const auto = await createPost(
    post({
      isAuto: true,
      mediaUrl: "/uploads/posts/pcomp-author-auto.jpg",
      competitionId: LAST,
    }),
  );
  check("the auto card carries it", auto.competition_id, LAST);
  const replaced = await createPost(
    post({ mediaUrl: "/uploads/posts/pcomp-author-5.jpg" }),
  );
  check(
    "the replacement wrote over the same post",
    replaced.post_id,
    auto.post_id,
  );
  check(
    "...and the chip is gone with the sticker",
    replaced.competition_id,
    null,
  );

  // ── 7. A raw workout entry has none ───────────────────────────────────
  const workoutEntry = (await getUnifiedFeed(MATE, 30, null)).find(
    (r) => r.kind === "workout" && r.id === "pcomp-w1",
  );
  if (workoutEntry) {
    check(
      "a workout entry carries no sticker",
      workoutEntry.competition_id,
      null,
    );
  } else {
    console.log("ok    (no standalone workout entry — its post suppresses it)");
  }

  await cleanup();
  await db.close?.();
  if (failures > 0) {
    console.error(`post-competition-check: ${failures} assertion(s) FAILED`);
    process.exit(1);
  }
  console.log("post-competition-check: all assertions passed");
  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
