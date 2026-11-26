/**
 * Coach MCP audit trail (`coach_mcp_audit_log`): every tool call (who, which
 * tool, the arguments, outcome) and every sign-in, refusal and token alarm.
 * RLS on, no policies: the DB connector's roles read it as empty.
 */
import { PostgresService } from "../services/DbService.js";

const db = PostgresService.getInstance();

const MAX_ARGS_CHARS = 8_000;

function clipArgs(args: unknown): string | null {
  if (args === undefined) return null;
  const s = JSON.stringify(args ?? null);
  return s.length <= MAX_ARGS_CHARS ? s : JSON.stringify({ truncated: s.slice(0, MAX_ARGS_CHARS) });
}

/** Sign-ins, refusals, token alarms. Never throws. */
export async function recordCoachEvent(
  event: string,
  userId: string | null,
  grantId: string | null,
  detail: string,
): Promise<void> {
  await db
    .query(
      `INSERT INTO coach_mcp_audit_log (user_id, grant_id, tool, outcome, detail) VALUES ($1, $2, $3, 'event', $4)`,
      [userId, grantId, event, detail.slice(0, 1000)],
    )
    .catch((err) => console.error("[coach-mcp] event not recorded", err));
}

/** One tool call. Never throws. */
export async function recordToolCall(entry: {
  userId: string;
  grantId: string;
  tool: string;
  args: unknown;
  outcome: "ok" | "error";
  detail: string | null;
  durationMs: number;
}): Promise<void> {
  await db
    .query(
      `INSERT INTO coach_mcp_audit_log (user_id, grant_id, tool, args, outcome, detail, duration_ms)
       VALUES ($1, $2, $3, $4::jsonb, $5, $6, $7)`,
      [entry.userId, entry.grantId, entry.tool, clipArgs(entry.args), entry.outcome,
        entry.detail?.slice(0, 1000) ?? null, Math.round(entry.durationMs)],
    )
    .catch((err) => console.error("[coach-mcp] tool call not recorded", err));
}
