/**
 * Close friends fields check — `GET /friends/close`.
 *
 *   - each row carries EXACTLY the friend-list columns: the check compares the
 *     whole key set, so a new column fails here until someone decides who may
 *     read it
 *   - `email` stays present as a String (''): older App Store builds decode it
 *     as non-optional, and an absent key fails the whole list
 *   - what the app draws (id, username, names, avatar) still arrives
 *   - only accepted friends are listed
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/close-friends-fields-check.mjs
 */
import express from "express";
import { PostgresService } from "../dist/services/DbService.js";
import { authenticateToken } from "../dist/middleware/auth.js";
import friendshipRoutes from "../dist/routes/friendshipsRoutes.js";
import { generateAccessToken } from "../dist/services/tokenService.js";

const db = PostgresService.getInstance();

const OWNER = "cff-owner";
const FRIEND = "cff-friend";
const PENDING = "cff-pending";
const ALL = [OWNER, FRIEND, PENDING];

const FRIEND_EMAIL = "cff-friend@example.test";
const FRIEND_APPLE_SUB = "cff-apple-sub-friend";
const FRIEND_REFERRAL = "cff-referral-answer";

const ROW_KEYS = [
  "bio",
  "current_streak",
  "dashboard_style",
  "email",
  "first_name",
  "last_name",
  "profile_image_url",
  "user_id",
  "username",
];

let failures = 0;
function check(label, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  const ok = a === e;
  if (!ok) failures++;
  console.log(`${ok ? "ok  " : "FAIL"}  ${label} → ${a}${ok ? "" : ` (expected ${e})`}`);
}

async function cleanup() {
  await db.query(`DELETE FROM close_friends WHERE user_id = ANY($1) OR close_friend_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM friendships WHERE user_id = ANY($1) OR friend_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1)`, [ALL]);
}

const app = express();
app.use(express.json());
app.use(authenticateToken);
app.use("/friends", friendshipRoutes);
const server = await new Promise((resolve) => {
  const s = app.listen(0, "127.0.0.1", () => resolve(s));
});
const base = `http://127.0.0.1:${server.address().port}`;

async function get(p, userId) {
  const token = await generateAccessToken(userId);
  const res = await fetch(base + p, { headers: { authorization: `Bearer ${token}` } });
  const text = await res.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {}
  return { status: res.status, json, text };
}

try {
  await cleanup();
  await db.query(
    `INSERT INTO users (user_id, email, apple_sub, username, first_name, last_name, bio,
                        profile_image_url, referral_source, referral_detail, signup_goal,
                        experience_level, dashboard_style, role)
     VALUES ($1, $2, $3, 'cff_friend', 'Fay', 'Field', 'hello', '/uploads/a.jpg', 'other', $4,
             'streak', 'beginner', 'fun', 'admin')`,
    [FRIEND, FRIEND_EMAIL, FRIEND_APPLE_SUB, FRIEND_REFERRAL],
  );
  for (const u of [OWNER, PENDING]) {
    await db.query(`INSERT INTO users (user_id, email, apple_sub, username) VALUES ($1, $2, $3, $4)`, [
      u,
      `${u}@example.test`,
      `${u}-sub`,
      u.replaceAll("-", "_"),
    ]);
  }
  await db.query(
    `INSERT INTO friendships (user_id, friend_id, status)
     VALUES ($1, $2, 'accepted'), ($2, $1, 'accepted'), ($1, $3, 'pending')`,
    [OWNER, FRIEND, PENDING],
  );
  await db.query(`INSERT INTO close_friends (user_id, close_friend_id) VALUES ($1, $2), ($1, $3)`, [
    OWNER,
    FRIEND,
    PENDING,
  ]);

  const r = await get(`/friends/close`, OWNER);
  check("list → 200", r.status, 200);
  check("only the accepted friend is listed", (r.json ?? []).map((u) => u.user_id), [FRIEND]);
  const row = r.json?.[0] ?? {};
  check("row has exactly the friend-list keys", Object.keys(row).sort(), ROW_KEYS);
  check("email present and empty for the shipped decoder", row.email, "");
  check(
    "what the app draws",
    [row.user_id, row.username, row.first_name, row.last_name, row.profile_image_url],
    [FRIEND, "cff_friend", "Fay", "Field", "/uploads/a.jpg"],
  );
  check(
    "friend-private values appear nowhere in the body",
    [FRIEND_EMAIL, FRIEND_APPLE_SUB, FRIEND_REFERRAL].filter((v) => r.text.includes(v)),
    [],
  );

  // The same list shape as the friends list, so the two can't drift apart.
  const friends = await get(`/friends/list/${OWNER}`, OWNER);
  check(
    "same keys as the friends list",
    Object.keys(friends.json?.[0] ?? {}).sort(),
    ROW_KEYS,
  );
} catch (err) {
  failures++;
  console.error("FAIL  threw:", err);
} finally {
  await cleanup().catch((e) => console.error("cleanup failed:", e.message));
  server.close();
  await db.close?.();
}

if (failures) {
  console.error(`\nclose-friends-fields-check: ${failures} failure(s)`);
  process.exit(1);
}
console.log("\nclose-friends-fields-check: all passed");
process.exit(0);
