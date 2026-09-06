import { PostgresService } from "../services/DbService.js";
import { logError } from "../services/errorLogService.js";
import { sendPush } from "../services/pushNotificationService.js";

const db = PostgresService.getInstance();

/**
 * One door for every scheduled job.
 *
 * Every cron file used to wrap its work in its own try/catch that wrote to
 * console.error and nothing else. On a box with no shell that is a sink with
 * no reader: the weekly recap could die every Sunday for a month and the
 * only symptom would be users not getting recaps. `runJob` keeps the
 * isolation those try/catches gave (one job failing never costs the next
 * its turn) and adds the two things they lacked — a row in `error_log`
 * under the `cron` category the admin Errors tab already lists, and a push
 * to every admin account, throttled per job so a job that fails every
 * minute rings once per `ALERT_COOLDOWN_MS`.
 *
 * It also remembers each job's last run in memory, which is what the admin
 * "Scheduled jobs" panel reads. In-memory is deliberate: the question that
 * panel answers is "is this process running its jobs", and a table would
 * survive the one event that resets the answer.
 */
export interface JobRun {
  job: string;
  ok: boolean;
  /** ISO timestamp of the run's end. */
  at: string;
  ms: number;
  error?: string;
  /** Failures since boot (or since the last reset). */
  failures: number;
}

/** Ring once per job per six hours, however often it keeps failing. */
export const ALERT_COOLDOWN_MS = 6 * 60 * 60 * 1000;

const lastRuns = new Map<string, JobRun>();
const failureCounts = new Map<string, number>();
const lastAlertAt = new Map<string, number>();
const bootedAt = new Date().toISOString();

export function cronAlertsEnabled(): boolean {
  return process.env.CRON_ALERTS_DISABLED !== "true";
}

/**
 * Runs `fn` as the job named `job`. Never throws: a failing job is recorded,
 * reported and returns false so callers can sequence dependent work
 * (`if (await runJob(...)) await runJob(...)`) without their own try/catch.
 */
export async function runJob(
  job: string,
  fn: () => Promise<unknown>,
): Promise<boolean> {
  const started = Date.now();
  try {
    await fn();
    lastRuns.set(job, {
      job,
      ok: true,
      at: new Date().toISOString(),
      ms: Date.now() - started,
      failures: failureCounts.get(job) ?? 0,
    });
    return true;
  } catch (err: any) {
    const message = String(err?.message ?? err);
    const failures = (failureCounts.get(job) ?? 0) + 1;
    failureCounts.set(job, failures);
    lastRuns.set(job, {
      job,
      ok: false,
      at: new Date().toISOString(),
      ms: Date.now() - started,
      error: message,
      failures,
    });
    console.error(`[CRON] ${job} failed:`, message);
    logError("cron", message, {
      context: {
        job,
        stack: String(err?.stack ?? "").slice(0, 2000),
      },
    });
    await alertAdmins(job, message).catch((alertErr: any) => {
      // The alert path must never turn a job failure into a crash.
      console.error(
        `[CRON] admin alert for ${job} failed:`,
        alertErr?.message ?? alertErr,
      );
    });
    return false;
  }
}

/**
 * Pushes the failure to every `role = 'admin'` account. `ops_alert` is in
 * HIGH_PRIORITY_TYPES (no quiet hours, no daily cap): an admin asked to be
 * told, and the per-job cooldown is what keeps it from being spam.
 * Shipped builds decode the inbox `type` as a plain string, so an unknown
 * type is a row with no destination, not a decode failure.
 */
async function alertAdmins(job: string, message: string): Promise<void> {
  if (!cronAlertsEnabled()) return;
  const now = Date.now();
  const last = lastAlertAt.get(job) ?? 0;
  if (now - last < ALERT_COOLDOWN_MS) return;
  lastAlertAt.set(job, now);

  const admins = await db.query<{ user_id: string }>(
    `SELECT user_id FROM users WHERE role = 'admin'`,
  );
  await Promise.all(
    admins.map((a) =>
      sendPush(
        a.user_id,
        {
          title: `Scheduled job failed: ${job}`,
          body: message.slice(0, 200),
          type: "ops_alert",
          data: { kind: "cron_failure", job },
        },
        { bypassDailyCap: true },
      ),
    ),
  );
}

/** Every job that has run since boot, most recently run first. */
export function getCronStatus(): { booted_at: string; jobs: JobRun[] } {
  return {
    booted_at: bootedAt,
    jobs: [...lastRuns.values()].sort((a, b) => (a.at < b.at ? 1 : -1)),
  };
}

/** Test seam: forget every run and every alert cooldown. */
export function resetCronRunnerForTests(): void {
  lastRuns.clear();
  failureCounts.clear();
  lastAlertAt.clear();
}
