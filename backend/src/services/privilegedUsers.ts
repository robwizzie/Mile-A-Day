/**
 * User IDs that bypass daily-action rate limits (hype / nudge / flex).
 * Used to give specific users (e.g. internal/admin accounts) effectively
 * unlimited daily actions without exposing a separate admin flow.
 */
const UNLIMITED_ACTION_USER_IDS: ReadonlySet<string> = new Set([
	// dave (David Simmerman)
	'be5dd0ffcd874f39ae8824d462d32300'
]);

export function hasUnlimitedActions(userId: string): boolean {
	return UNLIMITED_ACTION_USER_IDS.has(userId);
}
