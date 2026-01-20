import { AuthenticatedRequest } from '../middleware/auth.js';
import { Response } from 'express';
import hasRequiredKeys from '../utils/hasRequiredKeys.js';
import { BadRequestError } from '../errors/Errors.js';
import {
	createCompetition,
	getCompetition,
	getCompetitions,
	sendCompetitionInvite,
	updateCompetitionInvite,
	updateCompetition
} from '../services/competitionService.js';
import { getUser } from '../services/userService.js';

export async function createComp(req: AuthenticatedRequest, res: Response) {
	if (!hasRequiredKeys(['competition_name', 'type'], req, res)) return;

	const { competition_name, start_date, end_date, workouts, type, options } = req.body;

	try {
		const competitionId = await createCompetition({
			competition_name,
			start_date,
			end_date,
			workouts,
			type,
			options,
			owner: req.userId!
		});

		res.status(200).json({ competition_id: competitionId });
	} catch (error: any) {
		if (error instanceof BadRequestError) {
			return res.status(400).json({ error: error.message });
		}

		console.error('Error creating competition:', error.message);
		res.status(500).json({ error: 'Error creating competition: ' + error.message });
	}
}

export async function startComp(req: AuthenticatedRequest, res: Response) {}

export async function getComp(req: AuthenticatedRequest, res: Response) {
	if (!hasRequiredKeys(['competitionId'], req, res)) return;

	try {
		const competition = await getCompetition(req.params.competitionId);

		if (!competition) {
			return res.status(404).json({ error: `No competition found with id: ${req.params.competitionId}` });
		}

		return res.status(200).json({ competition });
	} catch (error: any) {
		console.error('Error getting competition:', error.message);
		res.status(500).json({ error: 'Error getting competition: ' + error.message });
	}
}

export async function getAllComps(req: AuthenticatedRequest, res: Response) {
	const page = req.query.page as string;
	const status = req.query.status as string;
	const pageSize = req.query.pageSize as string;

	try {
		const competitions = await getCompetitions(req.userId!, {
			page: page ? parseInt(page) : 1,
			pageSize: pageSize ? parseInt(pageSize) : 25,
			status
		});

		res.status(200).json({ competitions });
	} catch (error: any) {
		console.error('Error getting comps:', error.message);
		res.status(500).json({ error: 'Error getting comps: ' + error.message });
	}
}

export async function inviteUsersToComp(req: AuthenticatedRequest, res: Response) {
	if (!hasRequiredKeys(['competitionId', 'inviteUser'], req, res)) return;

	const competitionId = req.params.competitionId;
	const inviteUserId = req.body.inviteUser;

	try {
		const invitee = await getUser({ userId: inviteUserId });

		if (!invitee) {
			return res.status(404).json({ error: `No user found with id: ${inviteUserId}` });
		}

		const competition = await getCompetition(competitionId);

		if (!competition) {
			return res.status(404).json({ error: `No competition found with id: ${req.params.competitionId}` });
		}

		if (competition.users.find(u => u.user_id === inviteUserId && u.invite_status === 'accepted')) {
			return res.status(400).json({ error: `User ${inviteUserId} is already in this competition` });
		}

		if (!competition.users.find(u => u.user_id === req.userId! && u.invite_status === 'accepted')) {
			return res.status(401).json({ error: 'User does not have access to this competition' });
		}

		await sendCompetitionInvite(competitionId, inviteUserId);

		res.status(200).json({ message: `Successfully invited user ${inviteUserId} to competition ${competitionId}` });
	} catch (error: any) {
		console.error('Error inviting user:', error.message);
		res.status(500).json({ error: 'Error inviting user: ' + error.message });
	}
}

export async function getCompInvites(req: AuthenticatedRequest, res: Response) {
	try {
		const competitions = await getCompetitions(req.userId!, {
			page: parseInt(req.query.page as string) || 1,
			status: 'on_your_mark',
			pageSize: 25
		});
		res.status(200).json({ competitionInvites: competitions });
	} catch (error: any) {
		console.error('Error getting competition invites:', error.message);
		res.status(500).json({ error: 'Error getting competition invites: ' + error.message });
	}
}

export async function updateComp(req: AuthenticatedRequest, res: Response) {
	if (!hasRequiredKeys(['competitionId'], req, res)) return;

	const { competition_name, start_date, end_date, workouts, type, options } = req.body;
	const competitionId = req.params.competitionId;

	try {
		const existingCompetition = await getCompetition(competitionId);

		if (!existingCompetition) {
			return res.status(404).json({ error: `No competition found with id: ${competitionId}` });
		}

		if (existingCompetition.owner !== req.userId!) {
			return res.status(403).json({ error: 'Only the competition owner can update it' });
		}

		if (existingCompetition.start_date && new Date(existingCompetition.start_date) <= new Date()) {
			return res.status(400).json({ error: 'Cannot update a competition that has already started' });
		}

		const updatedCompetition = await updateCompetition({
			competitionId,
			competition_name,
			start_date,
			end_date,
			workouts,
			type,
			options
		});

		res.status(200).json({ competition: updatedCompetition });
	} catch (error: any) {
		if (error instanceof BadRequestError) {
			return res.status(400).json({ error: error.message });
		}

		console.error('Error updating competition:', error.message);
		res.status(500).json({ error: 'Error updating competition: ' + error.message });
	}
}

export function getCompInviteHandler(status: 'accepted' | 'declined') {
	return async function acceptCompInvite(req: AuthenticatedRequest, res: Response) {
		if (!hasRequiredKeys(['competitionId'], req, res)) return;

		try {
			const competitionId = req.params.competitionId;

			const competition = await getCompetition(competitionId);

			if (!competition) {
				return res.status(404).json({ error: `No competition found with id ${competitionId}` });
			}

			if (!competition.users.find(u => u.user_id === req.userId! && u.invite_status === 'pending')) {
				return res
					.status(400)
					.json({ error: `User ${req.userId!} does not have a pending invite to competition ${competitionId}` });
			}

			const updatedUserInfo = await updateCompetitionInvite(competitionId, req.userId!, status);

			competition.users = competition.users.map(u => (u.user_id === req.userId! ? updatedUserInfo : u));

			res.status(200).json({ competition });
		} catch (error: any) {
			console.error('Error handling invite:', error.message);
			res.status(500).json({ error: 'Error handling invite: ' + error.message });
		}
	};
}
