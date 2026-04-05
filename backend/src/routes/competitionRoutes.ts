import { Router } from 'express';
import {
	createComp,
	startComp,
	getComp,
	getAllComps,
	inviteUsersToComp,
	removeUserFromComp,
	getCompInvites,
	getCompInviteHandler,
	updateComp,
	deleteComp
} from '../controllers/competitionController.js';
import { nudgeUser } from '../controllers/nudgeController.js';
import { flexOnUser, getFlexPresets } from '../controllers/flexController.js';

const router = Router();

router.post('/', createComp);
router.get('/', getAllComps);
router.get('/invites', getCompInvites);
router.get('/flex/presets', getFlexPresets);
router.get('/:competitionId', getComp);
router.patch('/:competitionId', updateComp);
router.delete('/:competitionId', deleteComp);
router.post('/:competitionId/start', startComp);
router.post('/:competitionId/invite', inviteUsersToComp);
router.delete('/:competitionId/users/:userId', removeUserFromComp);
router.post('/:competitionId/accept', getCompInviteHandler('accepted'));
router.post('/:competitionId/decline', getCompInviteHandler('declined'));
router.post('/:competitionId/nudge', nudgeUser);
router.post('/:competitionId/flex', flexOnUser);

export default router;
