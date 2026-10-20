/**
 * The seam between Run Plans and the coach MCP connector (Claude).
 *
 * The plan response carries `claude: { connected, last_used_at }` and
 * `DELETE /run-plans/claude` revokes every coach token for the user. Both live
 * here so the coach MCP module (its `coach_mcp_*` tables, router and tokens)
 * can fill them in without touching the plan service. Until that module
 * lands there are no coach tokens: nobody is connected and revoking is a no-op.
 */

export interface CoachConnectionStatus {
  connected: boolean;
  last_used_at: string | null;
}

export async function coachConnectionStatus(
  _userId: string,
): Promise<CoachConnectionStatus> {
  return { connected: false, last_used_at: null };
}

/** Revoke every coach MCP token for the user. Returns how many were revoked. */
export async function revokeCoachTokens(_userId: string): Promise<number> {
  return 0;
}
