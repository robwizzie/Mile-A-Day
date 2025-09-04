import { User } from '../types/user.js';
import { PostgresService } from './DbService.js';
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
