import { PostgresService } from './DbService.js';

const db = PostgresService.getInstance();

/**
 * Role-based rate-limit bypasses:
 * - 'admin'   → unlimited everything (hype / nudge / flex, including per-target dedupe)
 * - 'founder' → unlimited hypes only (nudge/flex per-friend limits still apply)
 * Role lookups are cached in-memory for a few minutes so the bypass check
 * doesn't add a DB round-trip to every action.
 */
const CACHE_TTL_MS = 5 * 60 * 1000;

const roleCache = new Map<string, { role: string | null; expiresAt: number }>();

async function getRole(userId: string): Promise<string | null> {
	const cached = roleCache.get(userId);
	if (cached && cached.expiresAt > Date.now()) return cached.role;

	const rows = await db.query<{ role: string | null }>(`SELECT role FROM users WHERE user_id = $1`, [userId]);
	const role = rows[0]?.role ?? null;
	roleCache.set(userId, { role, expiresAt: Date.now() + CACHE_TTL_MS });
	return role;
}

/** Admins bypass ALL daily-action rate limits (hype / nudge / flex). */
export async function hasUnlimitedActions(userId: string): Promise<boolean> {
	return (await getRole(userId)) === 'admin';
}

/** Admins and founders bypass the daily hype cap. */
export async function hasUnlimitedHypes(userId: string): Promise<boolean> {
	const role = await getRole(userId);
	return role === 'admin' || role === 'founder';
}
