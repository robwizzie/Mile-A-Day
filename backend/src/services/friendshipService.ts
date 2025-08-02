import { Friendship, User } from '../types/user.js';
import { PostgresService } from './DbService.js';

const db = PostgresService.getInstance();

type ErrorReturn = {
	error: string;
};

type MessageReturn = {
	message: string;
};

export async function getFriendship(user1: string, user2: string): Promise<Friendship | ErrorReturn | null> {
	try {
		const existingFriendship = await db.query(
			'SELECT * FROM friendships WHERE (user_id = $1 AND friend_id = $2) OR (user_id = $2 AND friend_id = $1)',
			[user1, user2]
		);

		return existingFriendship.find(friendship => friendship.user_id === user1) ?? existingFriendship[0];
	} catch (err: any) {
		return { error: err.message };
	}
}

export async function getFriends(user: string): Promise<User[]> {
	const friends = await db.query(
		`
		SELECT u.* FROM friendships f
		JOIN users u ON u.user_id = f.friend_id
		WHERE f.user_id = $1
			AND f.status = 'accepted'
		`,
		[user]
	);

	return friends;
}

export async function getSentRequests(user: string): Promise<User[]> {
	const sentRequests = await db.query(
		`
		SELECT u.* FROM friendships f
		JOIN users u ON u.user_id = f.friend_id
		WHERE f.user_id = $1
			AND f.status in ( 'pending', 'ignored' ) 
		`,
		[user]
	);

	return sentRequests;
}

type FriendRequestsReturn = {
	requests: User[];
	ignored_requests: User[];
};

export async function getFriendRequests(user: string): Promise<FriendRequestsReturn> {
	const friendRequests = await db.query(
		`
		SELECT u.*, f.status FROM friendships f
		JOIN users u ON u.user_id = f.user_id
		WHERE f.friend_id = $1
			AND f.status in ( 'pending', 'ignored' ) 
		`,
		[user]
	);

	const requests: User[] = [];
	const ignored_requests: User[] = [];

	friendRequests.forEach(request => {
		const { status, ...user }: { status: 'pending' | 'ignored' } & User = request;
		if (status === 'pending') {
			requests.push(user);
		} else if (status === 'ignored') {
			ignored_requests.push(user);
		}
	});

	return { requests, ignored_requests };
}

export async function sendFriendRequest(user1: string, user2: string): Promise<MessageReturn | ErrorReturn> {
	try {
		await db.query(
			`
			INSERT INTO friendships (user_id, friend_id, status)
			VALUES ($1, $2, 'pending')
			ON CONFLICT (user_id, friend_id) DO NOTHING
			`,
			[user1, user2]
		);

		return { message: 'Successfully sent friend request' };
	} catch (err: any) {
		return { error: err.message };
	}
}

export async function updateFriendship(
	user1: string,
	user2: string,
	status: 'accepted' | 'rejected' | 'ignored' | 'removed'
): Promise<MessageReturn | ErrorReturn> {
	try {
		const existingFriendship = await getFriendship(user1, user2);

		if (!existingFriendship) {
			throw new Error(`No friendship found between ${user1} and ${user2}`);
		}

		if ('error' in existingFriendship) {
			throw new Error(existingFriendship.error);
		}

		if (existingFriendship.status === status) {
			throw new Error(`Friendship already has status ${status}`);
		} else if (
			(status === 'removed' && existingFriendship.status === 'accepted') ||
			(status === 'rejected' && (existingFriendship.status === 'pending' || existingFriendship.status === 'ignored'))
		) {
			await db.query(
				`
				DELETE FROM friendships
				WHERE (user_id = $1 AND friend_id = $2)
					OR (user_id = $2 AND friend_id = $1)
				`,
				[user1, user2]
			);

			return {
				message: status === 'rejected' ? 'Successfully rejected friend request' : 'Successfully deleted friendship'
			};
		} else if (existingFriendship.user_id === user1) {
			throw new Error(`User can't update a request they sent`);
		} else if (
			status === 'accepted' &&
			(existingFriendship.status === 'pending' || existingFriendship.status === 'ignored')
		) {
			await db.transaction([
				{
					query: `
					UPDATE friendships
					SET status = 'accepted'
					WHERE user_id = $1 AND friend_id = $2
					`,
					params: [user2, user1]
				},
				{
					query: `
					INSERT INTO friendships (user_id, friend_id, status)
  					VALUES ($1, $2, 'accepted')
  					ON CONFLICT (user_id, friend_id) DO NOTHING
					`,
					params: [user1, user2]
				}
			]);

			return { message: 'Friend request successfully accepted' };
		} else if (status === 'ignored') {
			await db.query(
				`
				UPDATE friendships
				SET status = 'ignored'
				WHERE user_id = $1 AND friend_id = $2
				`,
				[user2, user1]
			);

			return { message: 'Friend request successfully ignored' };
		} else {
			throw new Error('Invalid status.');
		}
	} catch (err: any) {
		return { error: err.message };
	}
}
