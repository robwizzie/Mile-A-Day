/**
 * User profile fields check — `GET /users/:id` by viewer.
 *
 *   - the owner gets every `users` column (the two raw Flamey columns stay
 *     off the row, as they always have)
 *   - any other viewer, friend or not, gets EXACTLY the allowlist: the check
 *     compares the whole key set, so a new `users` column fails here until
 *     someone decides who may read it
 *   - `email` stays present as a String ('' for other viewers): older App
 *     Store builds decode it as non-optional, and an absent key fails the
 *     whole BackendUser
 *   - the friends-only `flamey` block still reaches friends
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/user-profile-fields-check.mjs
 */
import express from "express";
import { PostgresService } from "../dist/services/DbService.js";
import { authenticateToken } from "../dist/middleware/auth.js";
import userRoutes from "../dist/routes/usersRoutes.js";
import { generateAccessToken } from "../dist/services/tokenService.js";

const db = PostgresService.getInstance();

const OWNER = "upf-owner";
const FRIEND = "upf-friend";
const STRANGER = "upf-stranger";
const ALL = [OWNER, FRIEND, STRANGER];

const OWNER_EMAIL = "upf-owner@example.test";
const OWNER_APPLE_SUB = "upf-apple-sub-owner";
const OWNER_REFERRAL = "upf-referral-answer";

const OTHER_VIEWER_KEYS = [
  "bio",
  "dashboard_style",
  "email",
  "first_name",
  "flamey",
  "last_name",
  "profile_banner_style",
  "profile_banner_url",
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
  await db.query(`DELETE FROM friendships WHERE user_id = ANY($1) OR friend_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1)`, [ALL]);
}

const app = express();
app.use(express.json());
app.use(authenticateToken);
app.use("/users", userRoutes);
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
                        profile_image_url, profile_banner_url, profile_banner_style,
                        referral_source, referral_detail, signup_goal, experience_level,
                        dashboard_style, role)
     VALUES ($1, $2, $3, 'upf_owner', 'Una', 'Field', 'hello', '/uploads/a.jpg', '/uploads/b.jpg',
             'sunrise', 'other', $4, 'streak', 'beginner', 'fun', 'admin')`,
    [OWNER, OWNER_EMAIL, OWNER_APPLE_SUB, OWNER_REFERRAL],
  );
  for (const u of [FRIEND, STRANGER]) {
    await db.query(`INSERT INTO users (user_id, email, apple_sub, username) VALUES ($1, $2, $3, $4)`, [
      u,
      `${u}@example.test`,
      `${u}-sub`,
      u.replaceAll("-", "_"),
    ]);
  }
  await db.query(
    `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, 'accepted'), ($2, $1, 'accepted')`,
    [OWNER, FRIEND],
  );

  // ── 1. The owner: the whole record.
  const columns = (
    await db.query(`SELECT column_name FROM information_schema.columns WHERE table_name = 'users'`)
  ).map((c) => c.column_name);
  let r = await get(`/users/${OWNER}`, OWNER);
  check("owner → 200", r.status, 200);
  const expectedOwnerKeys = columns.filter((c) => c !== "flamey_look" && c !== "flamey_name").concat("flamey").sort();
  check("owner gets every column", Object.keys(r.json ?? {}).sort(), expectedOwnerKeys);
  check("owner reads their own email", r.json?.email, OWNER_EMAIL);
  check("owner reads created_at (the Flamey anniversary)", typeof r.json?.created_at, "string");
  check("owner reads their referral answer", r.json?.referral_detail, OWNER_REFERRAL);

  // ── 2. Anyone else: the allowlist, whole key set.
  for (const [who, viewer] of [["friend", FRIEND], ["stranger", STRANGER]]) {
    r = await get(`/users/${OWNER}`, viewer);
    check(`${who} → 200`, r.status, 200);
    check(`${who} gets exactly the allowlist`, Object.keys(r.json ?? {}).sort(), OTHER_VIEWER_KEYS);
    check(`${who}: email present and empty for the shipped decoder`, r.json?.email, "");
    check(
      `${who}: owner-only values appear nowhere in the body`,
      [OWNER_EMAIL, OWNER_APPLE_SUB, OWNER_REFERRAL].filter((v) => r.text.includes(v)),
      [],
    );
    check(
      `${who}: what the app draws`,
      [r.json?.user_id, r.json?.username, r.json?.first_name, r.json?.last_name, r.json?.bio,
       r.json?.profile_image_url, r.json?.profile_banner_url, r.json?.profile_banner_style, r.json?.dashboard_style],
      [OWNER, "upf_owner", "Una", "Field", "hello", "/uploads/a.jpg", "/uploads/b.jpg", "sunrise", "fun"],
    );
  }

  // ── 3. The friends-only block is unchanged.
  r = await get(`/users/${OWNER}`, FRIEND);
  check("friend still gets the flamey block", r.json?.flamey?.enabled, true);
  r = await get(`/users/${OWNER}`, STRANGER);
  check("stranger's flamey block stays disabled", r.json?.flamey, { enabled: false });

  // ── 4. Missing user.
  r = await get(`/users/upf-nobody`, FRIEND);
  check("unknown user → 404", [r.status, r.json?.error], [404, "User not found"]);
} catch (err) {
  failures++;
  console.error("FAIL  threw:", err);
} finally {
  await cleanup().catch((e) => console.error("cleanup failed:", e.message));
  server.close();
  await db.close?.();
}

if (failures) {
  console.error(`\nuser-profile-fields-check: ${failures} failure(s)`);
  process.exit(1);
}
console.log("\nuser-profile-fields-check: all passed");
process.exit(0);
