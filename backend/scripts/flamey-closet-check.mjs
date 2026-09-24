/**
 * Flamey's Closet check — the saved mascot look.
 *
 *   1. the catalog: every unlocking badge id exists in the seeded badge
 *      catalog (badges-seed.sql + seedExtraBadges, holidays included), item
 *      ids are unique, every slot has items;
 *   2. `PUT /users/:id/flamey-look`: save + normalise (catalog slot order,
 *      explicit null kept as "bare", {} ⇒ null), reset with `look: null`,
 *      400 `invalid_flamey_look` with a `<slot>:<item>` detail for an unknown
 *      slot, an unknown item, a wrong-slot item and an UNOWNED item, and 403
 *      for someone else's row;
 *   3. `GET /users/:id/flamey-closet` (self): look + owned_item_ids +
 *      catalog_version, 403 for anyone else;
 *   4. a revoked medal (the real `revokeUnearnedBadges` path) drops its item
 *      at READ while the stored row keeps it — earn it back and it returns;
 *   5. the `flamey` block on `GET /users/:id` carries `look` + `owned_item_ids` to a friend and
 *      to self, never to a stranger, and the raw `flamey_look` column never
 *      rides the top-level user row.
 *
 * Every failure here is silent in production (a look that reverts, a friend
 * who sees a bare Flamey), so assertions are on this script's own users.
 *
 * Usage (same env as ci-smoke):  DATABASE_URL=... node scripts/flamey-closet-check.mjs
 */
import express from "express";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { PostgresService } from "../dist/services/DbService.js";
import { authenticateToken } from "../dist/middleware/auth.js";
import userRoutes from "../dist/routes/usersRoutes.js";
import { generateAccessToken } from "../dist/services/tokenService.js";
import { revokeUnearnedBadges, seedExtraBadges } from "../dist/services/badgeService.js";
import {
  FLAMEY_CATALOG,
  FLAMEY_SLOTS,
  flameyBadgeIds,
} from "../dist/services/flameyCatalog.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const db = PostgresService.getInstance();

const OWNER = "fc-owner"; // Fun, dresses Flamey
const FRIEND = "fc-friend"; // friend of OWNER
const STRANGER = "fc-stranger"; // nobody's friend
const ALL = [OWNER, FRIEND, STRANGER];

let failures = 0;
function check(label, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  const ok = a === e;
  if (!ok) failures++;
  console.log(`${ok ? "ok  " : "FAIL"}  ${label} → ${a}${ok ? "" : ` (expected ${e})`}`);
}

async function cleanup() {
  const fkTables = await db.query(
    `SELECT DISTINCT tc.table_name
       FROM information_schema.table_constraints tc
       JOIN information_schema.constraint_column_usage ccu
         ON ccu.constraint_name = tc.constraint_name
      WHERE tc.constraint_type = 'FOREIGN KEY' AND ccu.table_name = 'users'
        AND ccu.column_name = 'user_id'`,
  );
  for (const { table_name } of fkTables) {
    const cols = await db.query(
      `SELECT column_name FROM information_schema.columns
        WHERE table_name = $1 AND column_name IN ('user_id','sender_id','target_id','friend_id')`,
      [table_name],
    );
    for (const { column_name } of cols) {
      await db.query(`DELETE FROM ${table_name} WHERE ${column_name} = ANY($1)`, [ALL]).catch(() => {});
    }
  }
  await db.query(`DELETE FROM friendships WHERE user_id = ANY($1) OR friend_id = ANY($1)`, [ALL]).catch(() => {});
  await db.query(`DELETE FROM users WHERE user_id = ANY($1)`, [ALL]);
}

const app = express();
app.use(express.json({ limit: "2mb" }));
app.use(authenticateToken);
app.use("/users", userRoutes);
const server = await new Promise((resolve) => {
  const s = app.listen(0, "127.0.0.1", () => resolve(s));
});
const base = `http://127.0.0.1:${server.address().port}`;

async function call(method, p, userId, body) {
  const token = await generateAccessToken(userId);
  const res = await fetch(base + p, {
    method,
    headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let json = null;
  try {
    json = await res.json();
  } catch {}
  return { status: res.status, json };
}

const grant = (userId, ...badgeIds) =>
  db.query(
    `INSERT INTO user_badges (user_id, badge_id) SELECT $1, unnest($2::text[]) ON CONFLICT DO NOTHING`,
    [userId, badgeIds],
  );
// jsonb keeps its own key order, so stored-row comparisons sort keys first.
const sorted = (o) => (o ? Object.fromEntries(Object.entries(o).sort(([a], [b]) => a.localeCompare(b))) : o);
const storedLook = async (userId) =>
  (await db.query(`SELECT flamey_look FROM users WHERE user_id = $1`, [userId]))[0]?.flamey_look ?? null;

try {
  await cleanup();
  // The full canonical catalog + the v2 social/holiday rows (both idempotent).
  await db.query(fs.readFileSync(path.join(here, "badges-seed.sql"), "utf8"));
  await seedExtraBadges();
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, username, apple_sub, email, first_name) VALUES ($1::text, $1::text, $1::text, $1::text || '@example.com', 'T')`,
      [id],
    );
  }
  await db.query(`UPDATE users SET dashboard_style = 'fun' WHERE user_id = ANY($1)`, [ALL]);
  await db.query(
    `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, 'accepted'), ($2, $1, 'accepted')`,
    [OWNER, FRIEND],
  );

  // ── 1. Catalog.
  const needed = flameyBadgeIds();
  const present = new Set(
    (await db.query(`SELECT badge_id FROM badges WHERE badge_id = ANY($1)`, [needed])).map((r) => r.badge_id),
  );
  check("every unlocking badge id exists", needed.filter((id) => !present.has(id)), []);
  check("113 items", FLAMEY_CATALOG.size, 113);
  check(
    "every slot has items",
    FLAMEY_SLOTS.filter((s) => ![...FLAMEY_CATALOG.values()].some((i) => i.slot === s)),
    [],
  );
  check(
    "always-owned items",
    [...FLAMEY_CATALOG.values()].filter((i) => i.unlock.kind === "always").map((i) => i.id),
    ["classic", "classic_bubble"],
  );

  // ── 2. PUT validation + save.
  await grant(OWNER, "streak_7", "miles_25", "pace_10min", "holiday_halloween");
  let r = await call("GET", `/users/${OWNER}/flamey-closet`, OWNER);
  check("closet before save", [r.status, r.json?.look, r.json?.catalog_version], [200, null, "1"]);
  check(
    "owned_item_ids (catalog order)",
    r.json?.owned_item_ids,
    ["classic", "ruby", "ball_cap", "racing_flats", "pumpkin_suit", "classic_bubble"],
  );

  r = await call("PUT", `/users/${OWNER}/flamey-look`, OWNER, { look: { hat: "ball_cap" } });
  check("unknown slot → 400", [r.status, r.json], [400, { error: "invalid_flamey_look", detail: "hat:ball_cap" }]);
  r = await call("PUT", `/users/${OWNER}/flamey-look`, OWNER, { look: { head: "top_hat" } });
  check("unknown item → 400", [r.status, r.json?.detail], [400, "head:top_hat"]);
  r = await call("PUT", `/users/${OWNER}/flamey-look`, OWNER, { look: { feet: "ball_cap" } });
  check("wrong slot → 400", [r.status, r.json?.detail], [400, "feet:ball_cap"]);
  r = await call("PUT", `/users/${OWNER}/flamey-look`, OWNER, { look: { head: "crown" } });
  check("unowned (miles_1000) → 400", [r.status, r.json?.detail], [400, "head:crown"]);
  r = await call("PUT", `/users/${OWNER}/flamey-look`, OWNER, { look: { head: 7 } });
  check("non-string item → 400", [r.status, r.json?.detail], [400, "head:7"]);
  r = await call("PUT", `/users/${OWNER}/flamey-look`, OWNER, { look: ["ruby"] });
  check("array look → 400", r.status, 400);
  r = await call("PUT", `/users/${OWNER}/flamey-look`, OWNER, {});
  check("missing look → 400", [r.status, r.json?.detail], [400, "look:missing"]);
  check("rejections wrote nothing", await storedLook(OWNER), null);
  r = await call("PUT", `/users/${FRIEND}/flamey-look`, OWNER, { look: null });
  check("someone else's row → 403", r.status, 403);

  const LOOK = { bubble: "classic_bubble", head: "ball_cap", eyes: null, color: "ruby", feet: "racing_flats" };
  const CANON = { color: "ruby", head: "ball_cap", eyes: null, feet: "racing_flats", bubble: "classic_bubble" };
  r = await call("PUT", `/users/${OWNER}/flamey-look`, OWNER, { look: LOOK });
  check("save → 200 canonical", [r.status, r.json?.look, r.json?.catalog_version], [200, CANON, "1"]);
  check("stored canonical (null kept = bare)", sorted(await storedLook(OWNER)), sorted(CANON));
  r = await call("GET", `/users/${OWNER}/flamey-closet`, OWNER);
  check("closet serves it", r.json?.look, CANON);
  r = await call("GET", `/users/${OWNER}/flamey-closet`, FRIEND);
  check("closet is self-only → 403", r.status, 403);

  // Style never gates a save: a Modern user keeps their look.
  await db.query(`UPDATE users SET dashboard_style = 'modern' WHERE user_id = $1`, [OWNER]);
  r = await call("PUT", `/users/${OWNER}/flamey-look`, OWNER, { look: LOOK });
  check("save on Modern → 200", r.status, 200);
  await db.query(`UPDATE users SET dashboard_style = 'fun' WHERE user_id = $1`, [OWNER]);

  r = await call("PUT", `/users/${OWNER}/flamey-look`, OWNER, { look: {} });
  check("{} → auto (null)", [r.status, r.json?.look, await storedLook(OWNER)], [200, null, null]);
  r = await call("PUT", `/users/${OWNER}/flamey-look`, OWNER, { look: LOOK });
  r = await call("PUT", `/users/${OWNER}/flamey-look`, OWNER, { look: null });
  check("look:null resets to auto", [r.status, r.json?.look, await storedLook(OWNER)], [200, null, null]);

  // ── 5. The flamey block: friend + self see it, stranger doesn't, raw column never.
  r = await call("PUT", `/users/${OWNER}/flamey-look`, OWNER, { look: LOOK });
  r = await call("GET", `/users/${OWNER}`, FRIEND);
  check("friend sees look in flamey block", [r.json?.flamey?.enabled, r.json?.flamey?.look], [true, CANON]);
  check("…and holiday_keys still ride", r.json?.flamey?.holiday_keys, ["halloween"]);
  check(
    "friend's block carries owned_item_ids (catalog order)",
    r.json?.flamey?.owned_item_ids,
    ["classic", "ruby", "ball_cap", "racing_flats", "pumpkin_suit", "classic_bubble"],
  );
  check("raw flamey_look not on the row (friend)", "flamey_look" in (r.json ?? {}), false);
  r = await call("GET", `/users/${OWNER}`, OWNER);
  check("self sees look", r.json?.flamey?.look, CANON);
  check("self sees owned_item_ids", r.json?.flamey?.owned_item_ids?.length, 6);
  check("raw flamey_look not on the row (self)", "flamey_look" in (r.json ?? {}), false);
  r = await call("GET", `/users/${OWNER}`, STRANGER);
  check("stranger: block disabled, no look", r.json?.flamey, { enabled: false });
  check("raw flamey_look not on the row (stranger)", "flamey_look" in (r.json ?? {}), false);

  // ── 4. Revocation drops the item at READ, never rewrites the row.
  // No workouts back streak_7 / miles_25 / pace_10min / the Halloween medal,
  // so the real revoke path takes all four.
  const revoked = await revokeUnearnedBadges(OWNER);
  check("revoke took the medals", ["streak_7", "miles_25", "pace_10min"].every((b) => revoked.includes(b)), true);
  const DROPPED = { eyes: null, bubble: "classic_bubble" };
  r = await call("GET", `/users/${OWNER}/flamey-closet`, OWNER);
  check("closet drops revoked items", r.json?.look, DROPPED);
  check("owned shrinks to the always items", r.json?.owned_item_ids, ["classic", "classic_bubble"]);
  r = await call("GET", `/users/${OWNER}`, FRIEND);
  check("friend's block drops them too", r.json?.flamey?.look, DROPPED);
  check("…and its owned_item_ids shrink with them", r.json?.flamey?.owned_item_ids, ["classic", "classic_bubble"]);
  check("stored row untouched", sorted(await storedLook(OWNER)), sorted(CANON));
  r = await call("PUT", `/users/${OWNER}/flamey-look`, OWNER, { look: { color: "ruby" } });
  check("re-saving a revoked item → 400", [r.status, r.json?.detail], [400, "color:ruby"]);
  await grant(OWNER, "streak_7");
  r = await call("GET", `/users/${OWNER}/flamey-closet`, OWNER);
  check("earn it back → it returns", r.json?.look, { color: "ruby", eyes: null, bubble: "classic_bubble" });

  // A retired/garbage stored id is dropped, not served.
  await db.query(`UPDATE users SET flamey_look = '{"color":"retired_hue","head":"ruby","bubble":"classic_bubble"}' WHERE user_id = $1`, [OWNER]);
  r = await call("GET", `/users/${OWNER}/flamey-closet`, OWNER);
  check("unknown/wrong-slot stored ids dropped", r.json?.look, { bubble: "classic_bubble" });
} catch (err) {
  failures++;
  console.error("FAIL  threw:", err);
} finally {
  await cleanup().catch((e) => console.error("cleanup failed:", e.message));
  server.close();
  await db.close?.();
}

if (failures) {
  console.error(`\nflamey-closet-check: ${failures} failure(s)`);
  process.exit(1);
}
console.log("\nflamey-closet-check: all passed");
process.exit(0);
