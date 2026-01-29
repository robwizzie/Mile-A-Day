import { Router } from 'express';
import {
	getFriends,
	getFriendRequests,
	sendRequest,
	getFriendshipHandler,
	getSentRequests
} from '../controllers/friendshipsController.js';
import { requireSelfAccess } from '../middleware/auth.js';

const router = Router();

router.get('/:userId', requireSelfAccess('userId'), getFriends);
router.get('/requests/:userId', requireSelfAccess('userId'), getFriendRequests);
router.get('/sent-requests/:userId', requireSelfAccess('userId'), getSentRequests);
router.post('/request', requireSelfAccess('fromUser'), sendRequest);
router.patch('/accept', requireSelfAccess('toUser'), getFriendshipHandler('accepted'));
router.patch('/ignore', requireSelfAccess('toUser'), getFriendshipHandler('ignored'));
router.delete('/decline', requireSelfAccess('toUser'), getFriendshipHandler('rejected'));
router.delete('/cancel', requireSelfAccess('fromUser'), getFriendshipHandler('rejected'));
router.delete('/remove', requireSelfAccess('fromUser'), getFriendshipHandler('removed'));

export default router;
