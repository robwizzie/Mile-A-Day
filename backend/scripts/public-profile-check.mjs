/**
 * Public profile check — `/public/users/:username` and the post-link preview.
 *
 * Both are world-readable (mileaday.run/u/<name>, /p/<id> and their unfurl
 * cards), so the two things that go wrong here go wrong in public and
 * silently: a stale streak (the raw `users.current_streak` stays non-zero
 * until the hourly decay sweep, so a dead streak was advertised for up to an
 * hour), and a 'private' account's numbers leaking onto the open web. Pinned:
 *   - current_streak reads through effectiveStreakSql on both reads
 *   - total_miles counts only counted workouts (the miles_* medal figure)
 *   - friend_count counts the user's own accepted rows only
 *   - medals: pinned first, then rarest, capped, catalog columns only
 *   - 'private' ⇒ total_miles / friend_count / medals null; identity, bio,
 *     streak and banner stay
 *   - no sensitive column (email, apple_sub) and every legacy field present
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/public-profile-check.mjs
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { PostgresService } from "../dist/services/DbService.js";
import {
  getPublicProfile,
  PUBLIC_PROFILE_MEDAL_LIMIT,
} from "../dist/services/publicProfileService.js";
import { getPublicPostPreview } from "../dist/services/postService.js";
import { seedExtraBadges } from "../dist/services/badgeService.js";

const db = PostgresService.getInstance();
const here = path.dirname(fileURLToPath(import.meta.url));

const ANN = "pp-ann"; // default visibility; streak stored 6 but expired
const PAT = "pp-pat"; // 'private'; live streak
const BOB = "pp-bob";
const CY = "pp-cy";
const DEE = "pp-dee";
const ALL = [ANN, PAT, BOB, CY, DEE];

let failures = 0;
function check(label, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  const ok = a === e;
  if (!ok) failures++;
  console.log(`${ok ? "ok  " : "FAIL"}  ${label} → ${a}${ok ? "" : ` (expected ${e})`}`);
}

async function cleanup() {
  await db.query(`DELETE FROM posts WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM user_badges WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1)`, [ALL]);
  await db.query(
    `DELETE FROM friendships WHERE user_id = ANY($1) OR friend_id = ANY($1)`,
    [ALL],
  );
  await db.query(`DELETE FROM notification_settings WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1)`, [ALL]);
}

let w = 0;
async function workout(userId, distance, extra = {}) {
  await db.query(
    `INSERT INTO workouts (workout_id, user_id, distance, local_date, date, timezone_offset,
                           workout_type, device_end_date, calories, total_duration, created_at,
                           deleted_at, exclusion_reason, source)
     VALUES ($1, $2, $3, CURRENT_DATE - 3, CURRENT_DATE - 3, 0, 'walking',
             (CURRENT_DATE - 3) + INTERVAL '18 hours', 100, 900, NOW(), $4, $5, 'ci')`,
    [
      `pp-w-${++w}`,
      userId,
      distance,
      extra.deleted ? new Date() : null,
      extra.exclusion ?? null,
    ],
  );
}

async function seed() {
  await db.query(fs.readFileSync(path.join(here, "badges-seed.sql"), "utf8"));
  await seedExtraBadges();

  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, username, apple_sub, email, first_name, last_name, bio)
       VALUES ($1::text, $1::text, $1::text, $1::text || '@example.com', 'First', 'Last', 'bio of ' || $1::text)`,
      [id],
    );
  }
  // Ann: the stored row still says 6, but its valid-through day has passed —
  // exactly the window before the hourly sweep zeroes the column.
  await db.query(
    `UPDATE users SET current_streak = 6, streak_valid_through = CURRENT_DATE - 2,
            streak_computed_at = NOW(), profile_banner_style = 'sky',
            profile_banner_url = '/uploads/profile-banners/pp-ann.jpg'
     WHERE user_id = $1`,
    [ANN],
  );
  // Pat: a live streak, private account, no banner.
  await db.query(
    `UPDATE users SET current_streak = 12, streak_valid_through = CURRENT_DATE + 1,
            streak_computed_at = NOW()
     WHERE user_id = $1`,
    [PAT],
  );
  await db.query(
    `INSERT INTO notification_settings (user_id, workout_visibility) VALUES ($1, 'private')`,
    [PAT],
  );

  await workout(ANN, 1.25);
  await workout(ANN, 2.5);
  await workout(ANN, 9, { exclusion: "duplicate_source" }); // never counted
  await workout(ANN, 9, { deleted: true }); // never counted
  await workout(PAT, 3);

  // Ann's own accepted rows: Bob + Cy. Dee is pending; a reverse-only row
  // (Dee → Ann accepted) must not count either.
  for (const [a, b, status] of [
    [ANN, BOB, "accepted"],
    [BOB, ANN, "accepted"],
    [ANN, CY, "accepted"],
    [CY, ANN, "accepted"],
    [ANN, DEE, "pending"],
    [DEE, PAT, "accepted"],
    [PAT, DEE, "accepted"],
  ]) {
    await db.query(
      `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, $3)`,
      [a, b, status],
    );
  }

  // Ann: 7 medals. streak_7 (common) is PINNED → first despite rarity;
  // then legendary, rares, then commons newest-first.
  const medals = [
    ["consistency_3", null, "10 days"],
    ["consistency_5", null, "9 days"],
    ["streak_7", 1, "8 days"],
    ["streak_50", null, "7 days"],
    ["streak_100", null, "2 days"],
    ["streak_365", null, "6 days"],
    ["miles_25", null, "1 day"],
  ];
  for (const [badge, pin, ago] of medals) {
    await db.query(
      `INSERT INTO user_badges (user_id, badge_id, earned_at, pin_slot)
       VALUES ($1, $2, NOW() - $3::interval, $4)`,
      [ANN, badge, ago, pin],
    );
  }
  await db.query(
    `INSERT INTO user_badges (user_id, badge_id) VALUES ($1, 'streak_7')`,
    [PAT],
  );
}

try {
  await cleanup();
  await seed();

  // ── Ann: default ('friends', no settings row) ──────────────────────────
  const ann = await getPublicProfile("PP-Ann"); // case-insensitive lookup
  check("lookup is case-insensitive", ann?.user_id, ANN);
  check(
    "legacy fields all present",
    ["user_id", "username", "first_name", "last_name", "bio", "profile_image_url", "current_streak"].every(
      (k) => k in ann,
    ),
    true,
  );
  check("no email / apple_sub", "email" in ann || "apple_sub" in ann, false);
  check("no visibility leak", "workout_visibility" in ann, false);
  check("expired stored streak reads 0", ann.current_streak, 0);
  check("banner style", ann.profile_banner_style, "sky");
  check("banner url", ann.profile_banner_url, "/uploads/profile-banners/pp-ann.jpg");
  check("total_miles counts counted workouts only", ann.total_miles, 3.75);
  check("friend_count = own accepted rows", ann.friend_count, 2);
  check("medal cap", ann.medals.length, PUBLIC_PROFILE_MEDAL_LIMIT);
  check(
    "medal order: pinned, rarest, newest",
    ann.medals.map((m) => m.badge_id),
    ["streak_7", "streak_365", "streak_100", "streak_50", "miles_25"],
  );
  check(
    "medal shape = catalog columns",
    Object.keys(ann.medals[0]).sort(),
    ["badge_id", "category", "icon", "name", "rarity"],
  );

  // ── Pat: private ───────────────────────────────────────────────────────
  const pat = await getPublicProfile(PAT);
  check("private: live streak still public", pat.current_streak, 12);
  check("private: bio still public", pat.bio, "bio of pp-pat");
  check("private: total_miles withheld", pat.total_miles, null);
  check("private: friend_count withheld", pat.friend_count, null);
  check("private: medals withheld", pat.medals, null);
  check("private: no banner ⇒ nulls", [pat.profile_banner_style, pat.profile_banner_url], [null, null]);

  // Flip Ann to 'public' and Pat back to 'friends': only private withholds.
  await db.query(
    `INSERT INTO notification_settings (user_id, workout_visibility) VALUES ($1, 'public')`,
    [ANN],
  );
  await db.query(
    `UPDATE notification_settings SET workout_visibility = 'friends' WHERE user_id = $1`,
    [PAT],
  );
  check("public: stats shared", (await getPublicProfile(ANN)).friend_count, 2);
  const patFriends = await getPublicProfile(PAT);
  check("friends: stats shared", [patFriends.total_miles, patFriends.friend_count, patFriends.medals.length], [3, 1, 1]);

  check("unknown username ⇒ null", await getPublicProfile("pp-nobody"), null);

  // ── Post-link preview reads the same effective streak ─────────────────
  const [{ post_id }] = await db.query(
    `INSERT INTO posts (user_id, media_url, local_date, share_to_feed)
     VALUES ($1, '', CURRENT_DATE, TRUE) RETURNING post_id::text`,
    [ANN],
  );
  const preview = await getPublicPostPreview(post_id);
  check("post preview: expired streak reads 0", preview?.current_streak, 0);
} finally {
  await cleanup();
  await db.close?.();
}

if (failures > 0) {
  console.error(`\n${failures} public-profile check(s) failed`);
  process.exit(1);
}
console.log("\npublic-profile-check: all good");
process.exit(0);
