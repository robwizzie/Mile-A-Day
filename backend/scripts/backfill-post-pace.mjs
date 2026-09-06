// Rewrite the display pace BAKED into old posts, where it was computed from a
// moving clock that only witnessed part of the walk.
//
// A post's `stats_snapshot` is frozen at create time. The read path restates
// it only for a daily_mile anchor made of SEVERAL workouts — every ordinary
// single-workout post keeps whatever it was given, forever. So the tracker fix
// (creditMovingTime) and the server gate (displayMovingSecondsSql) both stop
// at the posts already in the feed: a 34:18 walk of 1.03 mi still reads
// "8:25 /mi" directly above splits that say "33:05".
//
// READ-ONLY by default. It prints how many posts are affected, the worst
// offenders, and what each would become. Pass --apply to write, which is the
// only mode that touches a row.
//
//   node scripts/backfill-post-pace.mjs                    # count + sample, writes nothing
//   node scripts/backfill-post-pace.mjs --apply            # perform the rewrite
//   node scripts/backfill-post-pace.mjs --rollback <file>  # put every one back
//
// `--apply` writes the pre-change value of every row it is about to touch to a
// JSON file FIRST and prints the path. That file is the undo: these are user
// records of their own walks, and a rewrite with no way back is not a rewrite
// anyone should run against production.
//
// The predicate is deliberately narrow, because a stats_snapshot is a user's
// own record of their walk and a wrong "fix" is worse than the bug:
//
//   1. The workout carries a moving clock that covered under half its elapsed
//      time — the same 50% line `DisplayPace` and `displayMovingSecondsSql`
//      draw. Anything above it was never mis-divided.
//   2. The stored pace MATCHES `moving_seconds / distance` to within 1%. That
//      is the proof it came from the broken clock rather than from anywhere
//      else; a pace that doesn't match is left exactly as it is.
//   3. The snapshot's distance matches the workout's own. A multi-workout
//      anchor is restated from the rollup on every read, so it is already
//      fixed and must not be written over.
//
// The replacement is elapsed ÷ the same distance — the figure the workout's
// own splits already show. When that lands outside the plausible band the pace
// key is REMOVED rather than replaced: no claim beats a wrong one.

const { PostgresService } = await import("../dist/services/DbService.js");
const db = PostgresService.getInstance();

const APPLY = process.argv.includes("--apply");
const ROLLBACK_AT = process.argv.indexOf("--rollback");
const ROLLBACK_FILE = ROLLBACK_AT === -1 ? null : process.argv[ROLLBACK_AT + 1];

if (ROLLBACK_FILE) {
  const { readFileSync } = await import("node:fs");
  const saved = JSON.parse(readFileSync(ROLLBACK_FILE, "utf8"));
  for (const row of saved) {
    // Restores the exact prior snapshot, including one that had no pace key.
    await db.query(
      `UPDATE posts SET stats_snapshot = $2::jsonb WHERE post_id = $1::uuid`,
      [row.postId, JSON.stringify(row.snapshot)],
    );
  }
  console.log(`rolled back ${saved.length} post(s) from ${ROLLBACK_FILE}`);
  process.exit(0);
}

// Mirrors DisplayPace.fastest/slowestPlausibleSecondsPerMile (iOS).
const FASTEST = 120;
const SLOWEST = 3600;
// Mirrors MIN_MOVING_COVERAGE (postService) and DisplayPace (iOS).
const MIN_COVERAGE = 0.5;

const CANDIDATES = `
  SELECT
    p.post_id::text,
    p.created_at::text                                 AS created_at,
    p.user_id,
    (p.stats_snapshot->>'pace')::double precision      AS pace,
    (p.stats_snapshot->>'distance')::double precision  AS snap_distance,
    p.stats_snapshot                                   AS snapshot,
    w.total_duration,
    w.moving_seconds,
    w.distance                                         AS workout_distance
  FROM posts p
  JOIN workouts w ON w.workout_id = p.workout_id
  WHERE p.deleted_at IS NULL
    AND w.deleted_at IS NULL
    AND p.stats_snapshot ? 'pace'
    AND jsonb_typeof(p.stats_snapshot->'pace') = 'number'
    AND jsonb_typeof(p.stats_snapshot->'distance') = 'number'
    AND w.moving_seconds IS NOT NULL
    AND w.moving_seconds > 0
    AND w.total_duration > 0
    AND w.moving_seconds < w.total_duration * ${MIN_COVERAGE}
`;

const rows = await db.query(CANDIDATES);

const affected = [];
for (const r of rows) {
  const snapDistance = Number(r.snap_distance);
  const pace = Number(r.pace);
  const moving = Number(r.moving_seconds);
  const elapsed = Number(r.total_duration);
  const workoutDistance = Number(r.workout_distance);
  if (!(snapDistance > 0) || !(pace > 0)) continue;

  // (2) the stored pace is the broken clock's own arithmetic
  const brokenPace = moving / snapDistance;
  if (Math.abs(pace - brokenPace) > Math.max(1, 0.01 * pace)) continue;

  // (3) not a rollup restatement
  if (Math.abs(snapDistance - workoutDistance) > 0.01 * Math.max(snapDistance, 0.01)) {
    continue;
  }

  const honest = elapsed / snapDistance;
  affected.push({
    postId: r.post_id,
    createdAt: r.created_at,
    userId: r.user_id,
    distance: snapDistance,
    was: pace,
    becomes: honest >= FASTEST && honest <= SLOWEST ? honest : null,
    coverage: moving / elapsed,
    // The whole prior snapshot, so a rollback restores it byte for byte.
    snapshot: r.snapshot,
  });
}

const mmss = (s) =>
  s === null ? "—" : `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`;

console.log(`posts with a linked workout whose moving clock covered <${MIN_COVERAGE * 100}%: ${rows.length}`);
console.log(`…of those, posts whose baked pace provably came from it:      ${affected.length}`);
console.log(`   (rewritten to elapsed pace: ${affected.filter((a) => a.becomes !== null).length}, pace dropped as implausible: ${affected.filter((a) => a.becomes === null).length})`);

if (affected.length > 0) {
  const worst = [...affected].sort((a, b) => a.coverage - b.coverage).slice(0, 15);
  console.log(`\nworst ${worst.length} (least of the walk actually witnessed):`);
  for (const a of worst) {
    console.log(
      `  ${a.createdAt.slice(0, 10)}  ${a.distance.toFixed(2)} mi  ` +
        `${mmss(a.was)} /mi → ${mmss(a.becomes)} /mi  ` +
        `(clock saw ${(a.coverage * 100).toFixed(0)}% of it)  ${a.postId}`,
    );
  }
  const people = new Set(affected.map((a) => a.userId)).size;
  console.log(`\nacross ${people} ${people === 1 ? "person" : "people"}`);
}

if (!APPLY) {
  console.log(`\nDRY RUN — nothing was written. Re-run with --apply to perform the rewrite.`);
  process.exit(0);
}

if (affected.length === 0) {
  console.log(`\nnothing to do.`);
  process.exit(0);
}

// The undo file comes FIRST — before a single row is touched.
const { writeFileSync } = await import("node:fs");
const undoPath = `post-pace-backfill-${new Date().toISOString().replace(/[:.]/g, "-")}.json`;
writeFileSync(
  undoPath,
  JSON.stringify(
    affected.map((a) => ({ postId: a.postId, snapshot: a.snapshot })),
    null,
    1,
  ),
);
console.log(`\nundo file written: ${undoPath}`);
console.log(`   (node scripts/backfill-post-pace.mjs --rollback ${undoPath})`);

let rewritten = 0;
let dropped = 0;
for (const a of affected) {
  if (a.becomes === null) {
    // No claim beats a wrong one.
    await db.query(
      `UPDATE posts SET stats_snapshot = stats_snapshot - 'pace' WHERE post_id = $1::uuid`,
      [a.postId],
    );
    dropped++;
  } else {
    await db.query(
      `UPDATE posts
          SET stats_snapshot = jsonb_set(stats_snapshot, '{pace}', to_jsonb($2::double precision))
        WHERE post_id = $1::uuid`,
      [a.postId, a.becomes],
    );
    rewritten++;
  }
}

console.log(`\nAPPLIED — ${rewritten} pace(s) rewritten, ${dropped} dropped.`);
process.exit(0);
