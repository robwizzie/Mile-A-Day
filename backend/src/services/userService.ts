import { User } from '../types/user.js';
import { PostgresService } from './DbService.js';
import crypto from 'crypto';

const db = PostgresService.getInstance();

export async function getUser({ userId = undefined, email = undefined }: { userId?: string | undefined; email?: string | undefined }) {
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
	return await db.query(`SELECT * FROM users WHERE user_id IN (${userIds.map((_, i: number) => `$${i + 1}`).join(', ')})`, userIds);
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
	// Check if username is already taken
	const existingUser = await db.query('SELECT user_id FROM users WHERE username = $1 AND user_id != $2', [username, userId]);

	if (existingUser.length > 0) {
		throw new Error('Username already taken');
	}

	// Update the username
	await db.query('UPDATE users SET username = $1 WHERE user_id = $2', [username, userId]);

	return { success: true };
}

export async function updateBio({ userId, bio }: { userId: string; bio: string }) {
	// Update the bio
	await db.query('UPDATE users SET bio = $1 WHERE user_id = $2', [bio, userId]);

	return { success: true };
}

export async function updateProfileImage({ userId, profileImageUrl }: { userId: string; profileImageUrl: string }) {
	// Update the profile image URL
	await db.query('UPDATE users SET profile_image_url = $1 WHERE user_id = $2', [profileImageUrl, userId]);

	return { success: true };
}

export async function checkUsernameAvailability(username: string): Promise<boolean> {
	const existingUser = await db.query('SELECT user_id FROM users WHERE username = $1', [username]);
	return existingUser.length === 0;
}
