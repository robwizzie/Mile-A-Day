import { User } from '../types/user.js';
import { PostgresService } from './DbService.js';

const db = PostgresService.getInstance();

export async function getUser(userId: string): Promise<User> {
	const userResults = await db.query('SELECT * FROM users WHERE user_id = $1', [userId]);
	return userResults[0];
}

export async function getUsers(userIds: string[]): Promise<User[]> {
	return await db.query(
		`SELECT * FROM users WHERE user_id IN (${userIds.map((_, i: number) => `$${i + 1}`).join(', ')})`,
		userIds
	);
}
