/**
 * The seam between Run Plans and the coach MCP connector (Claude,
 * src/coachMcp).
 *
 * The plan response carries `claude: { connected, last_used_at }` and
 * `DELETE /run-plans/claude` revokes every coach sign-in for the user. Both
 * read the `coach_mcp_*` tables directly (they exist whether or not
 * COACH_MCP_ENABLED is set, so this works — and reads "not connected" —
 * with the connector off).
 */
import { PostgresService } from "../DbService.js";

const db = PostgresService.getInstance();

export interface CoachConnectionStatus {
  connected: boolean;
  last_used_at: string | null;
}

/**
 * connected = some sign-in still holds a live token (an unexpired access
 * token, or an unexpired refresh token not yet rotated) on an unrevoked,
 * unexpired grant. last_used_at = the last MCP request, over all sign-ins.
 */
export async function coachConnectionStatus(userId: string): Promise<CoachConnectionStatus> {
  const rows = await db.query<{ connected: boolean; last_used_at: string | null }>(
    `SELECT EXISTS (
              SELECT 1 FROM coach_mcp_oauth_grants g
                JOIN coach_mcp_oauth_tokens t USING (grant_id)
               WHERE g.user_id = $1 AND g.revoked_at IS NULL AND g.expires_at > now()
                 AND t.expires_at > now() AND (t.kind = 'access' OR t.used_at IS NULL)
            ) AS connected,
            (SELECT to_char(max(last_used_at) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
               FROM coach_mcp_oauth_grants WHERE user_id = $1) AS last_used_at`,
    [userId],
  );
  return { connected: rows[0]?.connected === true, last_used_at: rows[0]?.last_used_at ?? null };
}

/**
 * Revoke every coach sign-in for the user (all their tokens die on the next
 * request) and drop any authorization code still in flight, so a sign-in
 * finishing right now can't mint a fresh grant. Returns how many sign-ins
 * were revoked.
 */
export async function revokeCoachTokens(userId: string): Promise<number> {
  await db.query(`DELETE FROM coach_mcp_oauth_codes WHERE user_id = $1`, [userId]);
  const rows = await db.query<{ grant_id: string }>(
    `UPDATE coach_mcp_oauth_grants SET revoked_at = now()
      WHERE user_id = $1 AND revoked_at IS NULL RETURNING grant_id`,
    [userId],
  );
  if (rows.length) {
    await db
      .query(
        `INSERT INTO coach_mcp_audit_log (user_id, tool, outcome, detail) VALUES ($1, 'revoked', 'event', $2)`,
        [userId, `revoked ${rows.length} sign-in(s) from the app`],
      )
      .catch((err) => console.error("[coach-mcp] revoke not recorded", err));
  }
  return rows.length;
}
