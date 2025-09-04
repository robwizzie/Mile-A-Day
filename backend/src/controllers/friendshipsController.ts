import { Request, Response } from 'express';
import {
	sendFriendRequest,
	getFriends as getUserFriends,
	getFriendRequests as getUserFriendRequests,
	getSentRequests as getUserSentRequests,
	updateFriendship
} from '../services/friendshipService.js';
import hasRequiredKeys from '../utils/hasRequiredKeys.js';
import { getUser, getUsers } from '../services/userService.js';

const BAD_REQUEST_ERRORS = [
	'No friendship found',
	'Friendship already has status',
	`User can't update a request they sent`,
	'Invalid status'
];

export async function getFriends(req: Request, res: Response) {
	if (!hasRequiredKeys(['userId'], req, res)) return;

	const { userId } = req.params;

	const user = await getUser({ userId });
	if (!user) {
		return res.status(400).send({ error: `No user found with ID ${userId}` });
	}

	const friends = await getUserFriends(userId);

	res.send(friends);
}

export async function getSentRequests(req: Request, res: Response) {
	if (!hasRequiredKeys(['userId'], req, res)) return;

	const { userId } = req.params;

	const user = await getUser({ userId });
	if (!user) {
		return res.status(400).send({ error: `No user found with ID ${userId}` });
	}

	const friendRequests = await getUserSentRequests(userId);

	res.send(friendRequests);
}

export async function getFriendRequests(req: Request, res: Response) {
	if (!hasRequiredKeys(['userId'], req, res)) return;

	const { userId } = req.params;

	const user = await getUser({ userId });
	if (!user) {
		return res.status(400).send({ error: `No user found with ID ${userId}` });
	}

	const friendRequests = await getUserFriendRequests(userId);

	res.send(friendRequests);
}

export async function sendRequest(req: Request, res: Response) {
	if (!hasRequiredKeys(['fromUser', 'toUser'], req, res)) return;

	const { fromUser, toUser } = req.body;

	const users = await getUsers([fromUser, toUser]);
	if (users.length !== 2) {
		const missingUser = [fromUser, toUser].find(uId => !users.find(u => u.user_id === uId));
		return res.status(400).send({ error: `No user found with ID ${missingUser}` });
	}

	const friendResult = await sendFriendRequest(fromUser, toUser);

	if ('error' in friendResult) {
		throw new Error(friendResult.error);
	}

	res.send(friendResult);
}

export function getFriendshipHandler(status: 'accepted' | 'rejected' | 'ignored' | 'removed') {
	return async function friendshipHandler(req: Request, res: Response) {
		if (!hasRequiredKeys(['fromUser', 'toUser'], req, res)) return;

		const { fromUser, toUser } = req.body;

		const users = await getUsers([fromUser, toUser]);
		if (users.length !== 2) {
			const missingUser = [fromUser, toUser].find(uId => !users.find(u => u.user_id === uId));
			return res.status(400).send({ error: `No user found with ID ${missingUser}` });
		}

		const friendResult = await updateFriendship(toUser, fromUser, status);

		if ('error' in friendResult) {
			if (BAD_REQUEST_ERRORS.find(e => friendResult.error.startsWith(e))) {
				return res.status(400).send(friendResult);
			} else {
				throw new Error(friendResult.error);
			}
		}

		res.send(friendResult);
	};
}
