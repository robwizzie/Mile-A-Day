import { Router } from 'express';
import { getFriends, getFriendRequests, sendRequest, getFriendshipHandler, getSentRequests } from '../controllers/friendshipsController.js';

const router = Router();

router.get('/:userId', getFriends);
router.get('/requests/:userId', getFriendRequests);
router.get('/sent-requests/:userId', getSentRequests);
router.post('/request', sendRequest);
router.patch('/accept', getFriendshipHandler('accepted'));
router.patch('/ignore', getFriendshipHandler('ignored'));
router.delete('/decline', getFriendshipHandler('rejected'));
router.delete('/remove', getFriendshipHandler('removed'));

export default router;
