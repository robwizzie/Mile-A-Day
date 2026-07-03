import { PostgresService } from "./DbService.js";

const db = PostgresService.getInstance();

// Categories are free-form text in the DB; this union just keeps call sites
// honest. Add a value here when a new failure surface needs its own bucket.
export type ErrorCategory =
  | "push" // APNs / notification send failures
  | "auth" // sign-in / token verification failures
  | "cron" // scheduled job failures
  | "api" // unhandled request errors (Express error handler)
  | "db" // database errors worth surfacing
  | "other";

interface LogErrorOptions {
  userId?: string | null;
  context?: Record<string, unknown> | null;
}

/**
 * Persist an operational error for the admin dashboard.
 *
 * Fire-and-forget: this NEVER throws and callers must NOT await it. A logging
 * failure must never break the operation that produced the error (e.g. a push
 * send). Keep calling console.error alongside this for live stdout.
 */
export function logError(
  category: ErrorCategory,
  message: string,
  opts: LogErrorOptions = {},
): void {
  // node-postgres serializes a plain object param into the jsonb column.
  db.query(
    `INSERT INTO error_log (category, user_id, message, context)
     VALUES ($1, $2, $3, $4)`,
    [
      category,
      opts.userId ?? null,
      String(message).slice(0, 4000), // ponytail: cap runaway messages
      opts.context ?? null,
    ],
  ).catch((err: any) => {
    // Last resort — if even the error log can't write, don't recurse into it.
    console.error("[errorLog] failed to persist error:", err?.message);
  });
}
