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
import { sendPush } from '../services/pushNotificationService.js';

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

	// Send push notification to the recipient
	const sender = users.find(u => u.user_id === fromUser);
	const senderName = sender?.username || 'Someone';
	sendPush(toUser, {
		title: 'New friend request',
		body: `${senderName} wants to be friends`,
		type: 'friend_request',
		data: { user_id: fromUser }
	}).catch(err => console.error('[Push] Error sending friend request notification:', err.message));

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

		// Notify the original sender that their request was accepted
		if (status === 'accepted') {
			const accepter = users.find(u => u.user_id === toUser);
			const accepterName = accepter?.username || 'Someone';
			sendPush(fromUser, {
				title: 'Friend request accepted',
				body: `${accepterName} accepted your friend request`,
				type: 'friend_request_accepted',
				data: { user_id: toUser }
			}).catch(err => console.error('[Push] Error sending friend accepted notification:', err.message));
		}

		res.send(friendResult);
	};
}
