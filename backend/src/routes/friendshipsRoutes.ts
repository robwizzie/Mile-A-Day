import { Router } from 'express';
import {
	getFriends,
	getFriendRequests,
	sendRequest,
	getFriendshipHandler,
	getSentRequests,
	getFriendsActivityToday,
	getSuggestions,
	getMutualFriends,
	getFriendsFeed
} from '../controllers/friendshipsController.js';
import { nudgeFriend, checkNudgeStatus, checkNudgeStatusBatch } from '../controllers/friendNudgeController.js';
import { requireSelfAccess } from '../middleware/auth.js';

const router = Router();

router.get('/activity/today/:userId', requireSelfAccess('userId'), getFriendsActivityToday);
router.get('/suggestions/:userId', requireSelfAccess('userId'), getSuggestions);
// Public friends list — any authenticated user can view another user's friends
// (Instagram-style followers/following). No requireSelfAccess; two path
// segments so it never collides with the self-only '/:userId' below.
router.get('/list/:userId', getFriends);
// Mutual friend count between the authenticated viewer and :userId.
router.get('/mutual/:userId', getMutualFriends);
// Rolling-48h workout activity feed for the authenticated viewer + friends.
router.get('/feed', getFriendsFeed);
router.get('/:userId', requireSelfAccess('userId'), getFriends);
router.get('/requests/:userId', requireSelfAccess('userId'), getFriendRequests);
router.get('/sent-requests/:userId', requireSelfAccess('userId'), getSentRequests);
router.post('/request', requireSelfAccess('fromUser'), sendRequest);
router.patch('/accept', requireSelfAccess('toUser'), getFriendshipHandler('accepted'));
router.patch('/ignore', requireSelfAccess('toUser'), getFriendshipHandler('ignored'));
router.delete('/decline', requireSelfAccess('toUser'), getFriendshipHandler('rejected'));
router.delete('/cancel', requireSelfAccess('fromUser'), getFriendshipHandler('rejected'));
router.delete('/remove', requireSelfAccess('fromUser'), getFriendshipHandler('removed'));

// Nudge routes
router.post('/:friendId/nudge', nudgeFriend);
router.get('/:friendId/nudge-status', checkNudgeStatus);
router.post('/nudge-status/batch', checkNudgeStatusBatch);

export default router;
