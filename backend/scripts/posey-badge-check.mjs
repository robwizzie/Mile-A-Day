/**
 * Posey badge check — the secret "Good Girl" medal and the Posey companion.
 *
 *   1. A COMPLETED buddy walk that both you and Posey FINISHED earns
 *      buddy_posey (via recalibrate, i.e. evaluateForUser's whole-history
 *      judgement — the same evaluation every upload runs);
 *   2. it is NOT earned for: a completed walk without Posey, a walk Posey
 *      left, a cancelled walk with Posey — nor by Posey herself;
 *   3. the medal is secret: the public catalog (GET /badges/catalog's
 *      getVisibleCatalog) leaves it out, while the full catalog keeps it and
 *      the seeded row is is_hidden = TRUE;
 *   4. holding the medal owns the `posey` companion (a skin-file item, not a
 *      ROWS item), and not holding it doesn't.
 *
 * Assertions are on this script's own users, never global counts.
 *
 * Usage (same env as ci-smoke):  DATABASE_URL=... node scripts/posey-badge-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import {
  POSEY_BADGE_ID,
  POSEY_USER_ID,
  getCatalog,
  getVisibleCatalog,
  recalibrateBadges,
  seedExtraBadges,
} from "../dist/services/badgeService.js";
import { FLAMEY_CATALOG, FLAMEY_ROW_ITEMS, ownedFlameyItemIds } from "../dist/services/flameyCatalog.js";

const db = PostgresService.getInstance();

const WALKER = "pbc-walker"; // finished a completed walk with Posey → earns
const OTHER = "pbc-other"; // completed walk, but with a friend, not Posey
const FRIEND = "pbc-friend"; // OTHER's walking partner
const LEFT = "pbc-left"; // Posey left the walk before finishing
const CANCEL = "pbc-cancel"; // the walk with Posey was cancelled
const PEOPLE = [WALKER, OTHER, FRIEND, LEFT, CANCEL];
const ALL = [...PEOPLE, POSEY_USER_ID];

let failures = 0;
function check(label, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  const ok = a === e;
  if (!ok) failures++;
  console.log(`${ok ? "ok  " : "FAIL"}  ${label} → ${a}${ok ? "" : ` (expected ${e})`}`);
}

async function cleanup() {
  await db.query(`DELETE FROM user_badges WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM notifications WHERE user_id = ANY($1::text[])`, [ALL]).catch(() => {});
  await db.query(`DELETE FROM buddy_session_participants WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM buddy_sessions WHERE host_user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1::text[])`, [ALL]);
}

/** One walk hosted by `host`; `walkers` = [[userId, participantStatus], ...]. */
async function walk(code, host, sessionStatus, walkers) {
  const rows = await db.query(
    `INSERT INTO buddy_sessions
       (join_code, host_user_id, mode, activity_type, status, origin,
        local_date, started_at, ended_at)
     VALUES ($1, $2, 'together', 'walking', $3, 'invite',
             CURRENT_DATE, NOW() - INTERVAL '1 hour', NOW() - INTERVAL '20 minutes')
     RETURNING id`,
    [code, host, sessionStatus],
  );
  for (const [userId, status] of walkers) {
    await db.query(
      `INSERT INTO buddy_session_participants
         (session_id, user_id, status, final_distance_miles, duration_seconds)
       VALUES ($1, $2, $3, 1.2, 2400)`,
      [rows[0].id, userId, status],
    );
  }
}

async function holds(userId) {
  const rows = await db.query(
    `SELECT 1 FROM user_badges WHERE user_id = $1 AND badge_id = $2`,
    [userId, POSEY_BADGE_ID],
  );
  return rows.length > 0;
}

async function main() {
  await cleanup();
  await seedExtraBadges();
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, apple_sub, email, username, first_name, last_name)
       VALUES ($1, $2, $3, $4, $4, 'Check')
       ON CONFLICT (user_id) DO NOTHING`,
      [id, `sub-${id}`, `${id}@example.com`, id === POSEY_USER_ID ? "pbc-posey" : id],
    );
  }

  await walk("PBC001", WALKER, "completed", [[WALKER, "finished"], [POSEY_USER_ID, "finished"]]);
  await walk("PBC002", OTHER, "completed", [[OTHER, "finished"], [FRIEND, "finished"]]);
  await walk("PBC003", LEFT, "completed", [[LEFT, "finished"], [POSEY_USER_ID, "left"]]);
  await walk("PBC004", CANCEL, "cancelled", [[CANCEL, "finished"], [POSEY_USER_ID, "finished"]]);

  for (const id of [...PEOPLE, POSEY_USER_ID]) await recalibrateBadges(id);

  // 1 + 2. Who earns it
  check("walked with Posey → earns Good Girl", await holds(WALKER), true);
  check("walked with someone else → no", await holds(OTHER), false);
  check("Posey left the walk → no", await holds(LEFT), false);
  check("cancelled walk with Posey → no", await holds(CANCEL), false);
  check("Posey never earns her own medal", await holds(POSEY_USER_ID), false);
  await recalibrateBadges(WALKER);
  const n = await db.query(
    `SELECT COUNT(*)::int AS n FROM user_badges WHERE user_id = $1 AND badge_id = $2`,
    [WALKER, POSEY_BADGE_ID],
  );
  check("a second evaluation doesn't award it twice", n[0].n, 1);

  // 3. Secret
  const visible = await getVisibleCatalog();
  const full = await getCatalog();
  check("public catalog leaves it out", visible.some((b) => b.badgeId === POSEY_BADGE_ID), false);
  const row = full.find((b) => b.badgeId === POSEY_BADGE_ID);
  check("full catalog keeps it", Boolean(row), true);
  check("…seeded hidden", row?.isHidden, true);
  check("…named Good Girl", row?.name, "Good Girl");
  check("public catalog keeps every other medal", visible.length, full.length - 1);

  // 4. Companion
  check("posey is a skin-file companion", FLAMEY_CATALOG.get("posey")?.slot, "companion");
  check("…unlocked by the medal", FLAMEY_CATALOG.get("posey")?.unlock, { kind: "badge", id: POSEY_BADGE_ID });
  check("…not a ROWS item", FLAMEY_ROW_ITEMS.has("posey"), false);
  check("medal holder owns the companion", ownedFlameyItemIds([POSEY_BADGE_ID]).has("posey"), true);
  check("no medal, no companion", ownedFlameyItemIds(["buddy_done_1"]).has("posey"), false);

  await cleanup();
  console.log(failures ? `\nposey-badge-check: ${failures} failure(s)` : "\nposey-badge-check: all passed");
  process.exit(failures ? 1 : 0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
