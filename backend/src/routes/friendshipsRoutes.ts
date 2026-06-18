import { Router } from 'express';
import {
	getFriends,
	getFriendRequests,
	sendRequest,
	getFriendshipHandler,
	getSentRequests,
	getFriendsActivityToday
} from '../controllers/friendshipsController.js';
import { nudgeFriend, checkNudgeStatus, checkNudgeStatusBatch } from '../controllers/friendNudgeController.js';
import { listCloseFriends, addCloseFriendHandler, removeCloseFriendHandler } from '../controllers/closeFriendsController.js';
import { requireSelfAccess } from '../middleware/auth.js';

const router = Router();

router.get('/activity/today/:userId', requireSelfAccess('userId'), getFriendsActivityToday);
router.get('/requests/:userId', requireSelfAccess('userId'), getFriendRequests);
router.get('/sent-requests/:userId', requireSelfAccess('userId'), getSentRequests);

// Close friends routes (must be before /:userId to avoid shadowing)
router.get('/close', listCloseFriends);
router.post('/close/:friendId', addCloseFriendHandler);
router.delete('/close/:friendId', removeCloseFriendHandler);

router.get('/:userId', requireSelfAccess('userId'), getFriends);
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
