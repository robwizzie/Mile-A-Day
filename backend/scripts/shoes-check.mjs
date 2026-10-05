/**
 * Shoe tracker check.
 *
 * Every failure here is silent — a pair's mileage is a plausible number
 * nobody can audit — so the rules are pinned against a seeded world:
 *   1. the sync stamps the DEFAULT shoe only onto on-foot workouts that
 *      ended after it became the default; a full re-sync of history never
 *      sweeps old workouts onto it
 *   2. a pick made before the workout synced (the recap) and an explicit
 *      "no shoe" both survive the sync
 *   3. mileage counts only COUNTED workouts (no duplicates, no deletions)
 *      plus the pair's starting miles
 *   4. one default per user; retiring it stops the stamping; deleting a
 *      shoe leaves its workouts as "no shoe" rather than re-stampable
 *   5. assignments are per USER: someone else writing a row for your
 *      workout id can't block your stamp
 *   6. PRIVACY: nothing outside the shoe service (and account deletion)
 *      reads the shoe tables, so no feed/profile/friend surface can.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/shoes-check.mjs
 */
import fs from "node:fs";
import path from "node:path";
import { PostgresService } from "../dist/services/DbService.js";
import { uploadWorkouts } from "../dist/services/workoutService.js";
import {
  createShoe,
  deleteShoe,
  getWorkoutShoe,
  listShoes,
  listShoeWorkouts,
  setWorkoutShoe,
  updateShoe,
} from "../dist/services/shoeService.js";

const db = PostgresService.getInstance();
const ALICE = "shoe-alice";
const BOB = "shoe-bob";
const ALL = [ALICE, BOB];

let failures = 0;
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${JSON.stringify(actual)}${ok ? "" : ` (expected ${JSON.stringify(expected)})`}`,
  );
}
const near = (a, b) => Math.abs(a - b) < 1e-9;

const HOUR = 3600 * 1000;
const ago = (h) => new Date(Date.now() - h * HOUR).toISOString();

function workout(id, endedHoursAgo, extra = {}) {
  const end = ago(endedHoursAgo);
  return {
    workoutId: id,
    distance: 1.5,
    localDate: end.slice(0, 10),
    date: end,
    timezoneOffset: 0,
    workoutType: "running",
    deviceEndDate: end,
    calories: 100,
    totalDuration: 900,
    splits: [],
    ...extra,
  };
}

async function shoeOf(user, workoutId) {
  const rows = await db.query(
    `SELECT shoe_id::text AS shoe_id, assigned_by FROM workout_shoes
     WHERE user_id = $1 AND workout_id = $2`,
    [user, workoutId],
  );
  return rows[0] ?? "none";
}

async function cleanup() {
  await db.query(`DELETE FROM workout_shoes WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM shoes WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1)`, [ALL]);
}

async function main() {
  await cleanup();
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, apple_sub, email, username, first_name, last_name)
       VALUES ($1, $2, $3, $4, 'Shoe', 'Check')`,
      [id, `sub-${id}`, `${id}@example.com`, id],
    );
  }

  // No shoes yet: syncing stamps nothing.
  await uploadWorkouts(ALICE, [workout("shoe-w-before", 5)]);
  check(
    "no shoes → nothing stamped",
    await shoeOf(ALICE, "shoe-w-before"),
    "none",
  );

  // A default pair, made the default three hours ago.
  const pegasus = await createShoe(ALICE, {
    name: "Pegasus 41",
    brand: "Nike",
    starting_miles: 20,
    is_default: true,
  });
  await db.query(
    `UPDATE shoes SET default_since = now() - interval '3 hours' WHERE shoe_id = $1`,
    [pegasus.shoe_id],
  );

  // Bob pre-claims one of Alice's workout ids in HIS namespace.
  await setWorkoutShoe(BOB, "shoe-w-new", null);

  // Recap pick before sync, and an explicit "no shoe" before sync.
  const ghost = await createShoe(ALICE, { name: "Ghost 16", brand: "Brooks" });
  check(
    "unsynced workout predicts the default",
    await getWorkoutShoe(ALICE, "shoe-w-picked"),
    { shoe_id: pegasus.shoe_id, source: "predicted" },
  );
  await setWorkoutShoe(ALICE, "shoe-w-picked", ghost.shoe_id);
  await setWorkoutShoe(ALICE, "shoe-w-none", null);

  await uploadWorkouts(ALICE, [
    workout("shoe-w-before", 5), // full re-sync of an old workout
    workout("shoe-w-old", 4), // ended before the default existed
    workout("shoe-w-new", 1), // after: stamped
    workout("shoe-w-walk", 1, { workoutType: "walking", distance: 2 }),
    workout("shoe-w-bike", 1, { workoutType: "cycling", distance: 10 }),
    workout("shoe-w-picked", 1, { distance: 3 }),
    workout("shoe-w-none", 1),
  ]);

  check(
    "re-synced history not swept onto the default",
    await shoeOf(ALICE, "shoe-w-before"),
    "none",
  );
  check(
    "workout before default_since not stamped",
    await shoeOf(ALICE, "shoe-w-old"),
    "none",
  );
  check("new run stamped with the default", await shoeOf(ALICE, "shoe-w-new"), {
    shoe_id: pegasus.shoe_id,
    assigned_by: "default",
  });
  check(
    "new walk stamped with the default",
    (await shoeOf(ALICE, "shoe-w-walk")).shoe_id,
    pegasus.shoe_id,
  );
  check("cycling never stamped", await shoeOf(ALICE, "shoe-w-bike"), "none");
  check(
    "pick made before sync survives",
    await shoeOf(ALICE, "shoe-w-picked"),
    {
      shoe_id: ghost.shoe_id,
      assigned_by: "user",
    },
  );
  check("explicit 'no shoe' survives", await shoeOf(ALICE, "shoe-w-none"), {
    shoe_id: null,
    assigned_by: "user",
  });
  check(
    "synced workout with no row reads as none (not predicted)",
    await getWorkoutShoe(ALICE, "shoe-w-old"),
    { shoe_id: null, source: null },
  );

  // Mileage: 20 starting + 1.5 run + 2 walk.
  let shoes = await listShoes(ALICE);
  let peg = shoes.find((s) => s.shoe_id === pegasus.shoe_id);
  check(
    "total = starting + counted workouts",
    near(peg.total_miles, 23.5),
    true,
  );
  check("tracked excludes starting miles", near(peg.tracked_miles, 3.5), true);
  check("workout count", peg.workout_count, 2);
  check("default listed first", shoes[0].shoe_id, pegasus.shoe_id);

  // A duplicate exclusion and a soft delete both leave the mileage.
  await db.query(
    `UPDATE workouts SET exclusion_reason = 'duplicate_source' WHERE workout_id = 'shoe-w-walk'`,
  );
  await db.query(
    `UPDATE workouts SET deleted_at = now() WHERE workout_id = 'shoe-w-new'`,
  );
  peg = (await listShoes(ALICE)).find((s) => s.shoe_id === pegasus.shoe_id);
  check(
    "duplicates and deleted workouts don't count",
    near(peg.total_miles, 20),
    true,
  );
  check(
    "shoe workout list matches",
    (await listShoeWorkouts(ALICE, pegasus.shoe_id)).length,
    0,
  );
  await db.query(
    `UPDATE workouts SET exclusion_reason = NULL, deleted_at = NULL
     WHERE workout_id IN ('shoe-w-walk', 'shoe-w-new')`,
  );

  // Changing a workout's pair moves its miles.
  await setWorkoutShoe(ALICE, "shoe-w-walk", ghost.shoe_id);
  shoes = await listShoes(ALICE);
  check(
    "re-pick moves the miles",
    [
      near(shoes.find((s) => s.shoe_id === pegasus.shoe_id).tracked_miles, 1.5),
      near(shoes.find((s) => s.shoe_id === ghost.shoe_id).tracked_miles, 5),
    ],
    [true, true],
  );

  // One default per user.
  await updateShoe(ALICE, ghost.shoe_id, { is_default: true });
  const defaults = (await listShoes(ALICE))
    .filter((s) => s.is_default)
    .map((s) => s.shoe_id);
  check("switching the default leaves exactly one", defaults, [ghost.shoe_id]);

  // Retiring the default stops the stamping.
  await updateShoe(ALICE, ghost.shoe_id, { retired: true });
  await uploadWorkouts(ALICE, [workout("shoe-w-after-retire", 0)]);
  check(
    "retired default stamps nothing",
    await shoeOf(ALICE, "shoe-w-after-retire"),
    "none",
  );
  const retired = (await listShoes(ALICE)).find(
    (s) => s.shoe_id === ghost.shoe_id,
  );
  check(
    "retiring clears default",
    [retired.is_default, retired.retired_at !== null],
    [false, true],
  );

  // Deleting a shoe leaves "no shoe", and a later default with an OLD
  // default_since still can't re-stamp those workouts.
  await deleteShoe(ALICE, pegasus.shoe_id);
  check(
    "deleted shoe leaves explicit none",
    await shoeOf(ALICE, "shoe-w-new"),
    {
      shoe_id: null,
      assigned_by: "default",
    },
  );
  const vomero = await createShoe(ALICE, { name: "Vomero", is_default: true });
  await db.query(
    `UPDATE shoes SET default_since = now() - interval '10 hours' WHERE shoe_id = $1`,
    [vomero.shoe_id],
  );
  await uploadWorkouts(ALICE, [workout("shoe-w-new", 1)]);
  check(
    "re-sync after delete doesn't re-stamp",
    (await shoeOf(ALICE, "shoe-w-new")).shoe_id,
    null,
  );

  // Per-user namespace: Bob's row never blocked Alice's stamp, and his
  // shoes/rows are invisible to her listing.
  check(
    "other user's row is in his own namespace",
    await shoeOf(BOB, "shoe-w-new"),
    {
      shoe_id: null,
      assigned_by: "user",
    },
  );
  await createShoe(BOB, { name: "Bob's pair" });
  check(
    "listing is the owner's alone",
    (await listShoes(ALICE)).every((s) => s.name !== "Bob's pair"),
    true,
  );

  // PRIVACY: the shoe tables are read by the shoe service and written by
  // account deletion — nothing else. A feed/profile/friend query that joined
  // them would be a leak this check exists to stop at review time.
  const dist = path.resolve(
    path.dirname(new URL(import.meta.url).pathname),
    "../dist",
  );
  const allowed = new Set([
    path.join("services", "shoeService.js"),
    path.join("controllers", "usersController.js"),
    path.join("db", "drizzle", "schema.js"),
    path.join("db", "drizzle", "relations.js"),
  ]);
  const offenders = [];
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.name.endsWith(".js")) {
        const rel = path.relative(dist, full);
        const src = fs.readFileSync(full, "utf8");
        if (
          !allowed.has(rel) &&
          /\b(workout_shoes|FROM\s+shoes|JOIN\s+shoes)\b/i.test(src)
        ) {
          offenders.push(rel);
        }
      }
    }
  };
  walk(dist);
  check("no other module reads the shoe tables", offenders, []);

  await cleanup();
}

main()
  .then(() => {
    console.log(
      failures ? `\n${failures} check(s) FAILED` : "\nAll shoe checks passed",
    );
    process.exit(failures ? 1 : 0);
  })
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
