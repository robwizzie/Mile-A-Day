import { PostgresService } from './DbService.js';
import { areFriends } from './friendshipService.js';
import { User } from '../types/user.js';

const db = PostgresService.getInstance();

type ErrorReturn = { error: string };
type MessageReturn = { message: string };

export async function getCloseFriends(userId: string): Promise<User[]> {
	const rows = await db.query<User>(
		`SELECT u.*
		FROM close_friends cf
		JOIN users u ON u.user_id = cf.close_friend_id
		JOIN friendships f ON (
			(f.user_id = cf.user_id AND f.friend_id = cf.close_friend_id)
			OR (f.user_id = cf.close_friend_id AND f.friend_id = cf.user_id)
		) AND f.status = 'accepted'
		WHERE cf.user_id = $1`,
		[userId]
	);
	return rows;
}

export async function addCloseFriend(userId: string, friendId: string): Promise<MessageReturn | ErrorReturn> {
	try {
		const accepted = await areFriends(userId, friendId);
		if (!accepted) {
			return { error: 'You can only add accepted friends to your close friends list' };
		}

		await db.query(
			`INSERT INTO close_friends (user_id, close_friend_id)
			VALUES ($1, $2)
			ON CONFLICT DO NOTHING`,
			[userId, friendId]
		);

		return { message: 'Successfully added to close friends' };
	} catch (err: any) {
		return { error: err.message };
	}
}

export async function removeCloseFriend(userId: string, friendId: string): Promise<MessageReturn | ErrorReturn> {
	try {
		await db.query(`DELETE FROM close_friends WHERE user_id = $1 AND close_friend_id = $2`, [userId, friendId]);
		return { message: 'Successfully removed from close friends' };
	} catch (err: any) {
		return { error: err.message };
	}
}

export async function getCloseFriendIds(userId: string): Promise<string[]> {
	const rows = await db.query<{ close_friend_id: string }>(
		`SELECT cf.close_friend_id
		FROM close_friends cf
		JOIN friendships f ON (
			(f.user_id = cf.user_id AND f.friend_id = cf.close_friend_id)
			OR (f.user_id = cf.close_friend_id AND f.friend_id = cf.user_id)
		) AND f.status = 'accepted'
		WHERE cf.user_id = $1`,
		[userId]
	);
	return rows.map(r => r.close_friend_id);
}

export async function isCloseFriendOf(ownerId: string, candidateId: string): Promise<boolean> {
	const rows = await db.query<{ close_friend_id: string }>(
		`SELECT 1 FROM close_friends WHERE user_id = $1 AND close_friend_id = $2 LIMIT 1`,
		[ownerId, candidateId]
	);
	return rows.length > 0;
}
