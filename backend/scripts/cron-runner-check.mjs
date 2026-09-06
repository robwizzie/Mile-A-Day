/**
 * Scheduled-job runner check.
 *
 * Every cron job runs through cronRunner.runJob, which is the ONE place a
 * scheduled failure becomes visible: an error_log row (category "cron") for
 * the admin Errors tab and a push to admin accounts. Both used to be a
 * console.error on a box with no shell. What can go wrong here is the
 * runner itself going quiet — swallowing the row, alerting nobody, or the
 * opposite, ringing the admin every minute for a job that fails every
 * minute — so the check pins each of those against a real database.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/cron-runner-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import {
  runJob,
  getCronStatus,
  resetCronRunnerForTests,
  ALERT_COOLDOWN_MS,
} from "../dist/cron/cronRunner.js";

const db = PostgresService.getInstance();
const ADMIN = "cr-admin";
const CIVILIAN = "cr-civilian";
const JOB = "cr.check.failing";
const OK_JOB = "cr.check.passing";

let failures = 0;
function check(label, actual, expected) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${JSON.stringify(actual)}${ok ? "" : ` (expected ${JSON.stringify(expected)})`}`,
  );
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function cleanup() {
  await db.query(`DELETE FROM in_app_notifications WHERE user_id = ANY($1)`, [
    [ADMIN, CIVILIAN],
  ]);
  await db.query(`DELETE FROM notification_log WHERE user_id = ANY($1)`, [
    [ADMIN, CIVILIAN],
  ]);
  await db.query(`DELETE FROM error_log WHERE context->>'job' LIKE 'cr.check.%'`);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1)`, [[ADMIN, CIVILIAN]]);
}

async function errorRows() {
  const [{ n }] = await db.query(
    `SELECT COUNT(*)::int AS n FROM error_log WHERE category = 'cron' AND context->>'job' = $1`,
    [JOB],
  );
  return n;
}
async function alerts(userId) {
  const [{ n }] = await db.query(
    `SELECT COUNT(*)::int AS n FROM in_app_notifications WHERE user_id = $1 AND type = 'ops_alert'`,
    [userId],
  );
  return n;
}

try {
  await cleanup();
  for (const [id, role] of [
    [ADMIN, "admin"],
    [CIVILIAN, "user"],
  ]) {
    await db.query(
      `INSERT INTO users (user_id, username, apple_sub, email, role, created_at)
       VALUES ($1, $2, $3, $4, $5, NOW())`,
      [id, id, id, `${id}@example.com`, role],
    );
  }
  delete process.env.CRON_ALERTS_DISABLED;
  resetCronRunnerForTests();

  const first = await runJob(JOB, async () => {
    throw new Error("boom: the recap query lost a column");
  });
  await sleep(300); // logError is fire-and-forget
  check("a throwing job returns false instead of throwing", first, false);
  check("…and writes one error_log row under 'cron'", await errorRows(), 1);
  check("…and alerts the admin account once", await alerts(ADMIN), 1);
  check("…and never a civilian", await alerts(CIVILIAN), 0);

  const [row] = await db.query(
    `SELECT message, context FROM error_log WHERE context->>'job' = $1`,
    [JOB],
  );
  check("the row carries the message", row.message, "boom: the recap query lost a column");
  check("the row names the job", row.context.job, JOB);

  const second = await runJob(JOB, async () => {
    throw new Error("boom again");
  });
  await sleep(300);
  check("a second failure is recorded", await errorRows(), 2);
  check("…but does not ring the admin again inside the cooldown", await alerts(ADMIN), 1);
  check("cooldown is six hours", ALERT_COOLDOWN_MS, 6 * 60 * 60 * 1000);
  check("second call also returns false", second, false);

  const passed = await runJob(OK_JOB, async () => {});
  check("a passing job returns true", passed, true);

  const status = getCronStatus();
  const failing = status.jobs.find((j) => j.job === JOB);
  const passing = status.jobs.find((j) => j.job === OK_JOB);
  check("status lists the failing job as failed", failing?.ok, false);
  check("status counts both failures", failing?.failures, 2);
  check("status keeps the latest error", failing?.error, "boom again");
  check("status lists the passing job as ok", passing?.ok, true);
  check("status carries a boot timestamp", typeof status.booted_at, "string");

  // A job that failed and then recovers reads as ok with its failure count.
  const recovered = await runJob(JOB, async () => {});
  check("recovery returns true", recovered, true);
  const after = getCronStatus().jobs.find((j) => j.job === JOB);
  check("…and the status flips to ok", after?.ok, true);
  check("…keeping the failure history", after?.failures, 2);

  // Kill switch: rows still land, nobody is rung.
  process.env.CRON_ALERTS_DISABLED = "true";
  resetCronRunnerForTests();
  await runJob(JOB, async () => {
    throw new Error("silent");
  });
  await sleep(300);
  check("with CRON_ALERTS_DISABLED the row still lands", await errorRows(), 3);
  check("…and the admin is not rung", await alerts(ADMIN), 1);
} finally {
  delete process.env.CRON_ALERTS_DISABLED;
  await cleanup();
  await db.close();
}

if (failures) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log("\ncron runner check passed");
process.exit(0);
