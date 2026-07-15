import { User } from '../types/user.js';
import { PostgresService, db as orm, schema } from './DbService.js';
import { count, eq, sql } from 'drizzle-orm';
import crypto from 'crypto';

const db = PostgresService.getInstance();

export async function getUser({
	userId = undefined,
	email = undefined
}: {
	userId?: string | undefined;
	email?: string | undefined;
}) {
	let results;
	if (userId) {
		results = await db.query('SELECT * FROM users WHERE user_id = $1', [userId]);
	} else if (email) {
		results = await db.query('SELECT * FROM users WHERE email = $1', [email]);
	} else {
		// TODO handle better
		return undefined;
	}

	if (!results.length) {
		// TODO handle better
		return undefined;
	}

	return results[0];
}

export async function getUsers(userIds: string[]): Promise<User[]> {
	return await db.query(
		`SELECT * FROM users WHERE user_id IN (${userIds.map((_, i: number) => `$${i + 1}`).join(', ')})`,
		userIds
	);
}

export async function createUser({ email, apple_sub }: { email: string; apple_sub: string }) {
	const existingAppleId = await db.query('SELECT user_id FROM users WHERE email = $1', [email]);

	if (existingAppleId.length) {
		// TODO: handle existing user
		return {};
		// return res.status(400).json({
		// 	error: 'Bad Request',
		// 	message: `User already exists with Apple ID ${email}`
		// });
	}

	const user_id = crypto.randomUUID().replaceAll('-', '');

	await db.query('INSERT INTO users (user_id,  email,  apple_sub) VALUES ($1, $2, $3)', [user_id, email, apple_sub]);

	return {
		user_id,
		email
	};
}

export async function updateUsername({ userId, username }: { userId: string; username: string }) {
	const existingUser = await db.query('SELECT user_id FROM users WHERE username = $1 AND user_id != $2', [username, userId]);

	if (existingUser.length > 0) {
		throw new Error('Username already taken');
	}

	await db.query('UPDATE users SET username = $1 WHERE user_id = $2', [username, userId]);

	return { success: true };
}

export async function updateBio({ userId, bio }: { userId: string; bio: string }) {
	await db.query('UPDATE users SET bio = $1 WHERE user_id = $2', [bio, userId]);

	return { success: true };
}

export async function updateProfileImage({ userId, profileImageUrl }: { userId: string; profileImageUrl: string }) {
	await db.query('UPDATE users SET profile_image_url = $1 WHERE user_id = $2', [profileImageUrl, userId]);

	return { success: true };
}

/**
 * Persist the optional onboarding personalization fields captured on the
 * signup "about you" step. Only the keys provided (non-undefined) are written,
 * so a partial submit (or a later re-submit) doesn't clobber existing values
 * with nulls. `onboarding_completed_at` is always stamped so the client knows
 * the step is done and we can measure completion. All fields are additive and
 * nullable — passing nothing but stamping the timestamp records a "skipped".
 */
export async function updateOnboardingInfo({
	userId,
	referralSource,
	referralDetail,
	signupGoal,
	experienceLevel
}: {
	userId: string;
	referralSource?: string | null;
	referralDetail?: string | null;
	signupGoal?: string | null;
	experienceLevel?: string | null;
}) {
	const updates: string[] = [];
	const values: any[] = [];

	const setField = (column: string, value: string | null | undefined) => {
		if (value === undefined) return;
		values.push(value);
		updates.push(`${column} = $${values.length}`);
	};

	setField('referral_source', referralSource);
	setField('referral_detail', referralDetail);
	setField('signup_goal', signupGoal);
	setField('experience_level', experienceLevel);

	// Always mark the step complete, even on a pure skip (no fields provided).
	updates.push('onboarding_completed_at = NOW()');

	values.push(userId);
	await db.query(`UPDATE users SET ${updates.join(', ')} WHERE user_id = $${values.length}`, values);

	return { success: true };
}

export async function checkUsernameAvailability(username: string): Promise<boolean> {
	// Drizzle ORM equivalent of `SELECT user_id FROM users WHERE username = $1`.
	const existingUser = await orm.select({ userId: schema.users.userId }).from(schema.users).where(eq(schema.users.username, username));
	return existingUser.length === 0;
}

/**
 * Usernames whose streak is exposed on the public, unauthenticated API.
 * Users must opt in (e.g. for embedding on a personal site) — never expose
 * everyone's streak publicly.
 */
const PUBLIC_STREAK_USERNAMES = new Set(['dave']);

export async function getPublicStreak(username: string): Promise<{ username: string; current_streak: number } | null> {
	const normalized = username.toLowerCase();
	if (!PUBLIC_STREAK_USERNAMES.has(normalized)) return null;

	// Return shape is preserved exactly: { username, current_streak } (snake_case),
	// since the public API contract depends on it.
	const [row] = await orm
		.select({ username: schema.users.username, current_streak: schema.users.currentStreak })
		.from(schema.users)
		.where(sql`lower(${schema.users.username}) = ${normalized}`);
	if (!row || row.username === null) return null;
	return { username: row.username, current_streak: row.current_streak };
}

export async function getUserCount(): Promise<number> {
	const [row] = await orm.select({ count: count() }).from(schema.users);
	return row.count;
}
