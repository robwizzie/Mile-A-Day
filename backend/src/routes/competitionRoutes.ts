import { Router } from 'express';
import {
	createComp,
	startComp,
	getComp,
	getAllComps,
	inviteUsersToComp,
	getCompInvites,
	getCompInviteHandler
} from '../controllers/competitionController.js';

const router = Router();

router.post('/', createComp);
router.get('/', getAllComps);
router.get('/invites', getCompInvites);
router.get('/:competitionId', getComp);
router.post('/:competitionId/start', startComp);
router.post('/:competitionId/invite', inviteUsersToComp);
router.post('/:competitionId/accept', getCompInviteHandler('accepted'));
router.post('/:competitionId/decline', getCompInviteHandler('declined'));

export default router;
