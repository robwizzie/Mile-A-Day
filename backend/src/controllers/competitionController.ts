import { AuthenticatedRequest } from '../middleware/auth';
import { Response } from 'express';
import hasRequiredKeys from '../utils/hasRequiredKeys';
import { BadRequestError } from '../errors/Errors';
import { createCompetition, getCompetition } from '../services/competitionService';

export async function createComp(req: AuthenticatedRequest, res: Response) {
	if (!hasRequiredKeys(['competition_name', 'type', 'userId'], req, res)) return;

	const { competition_name, start_date, end_date, workouts, type, options } = req.body;

	try {
		const competitionId = createCompetition({
			competition_name,
			start_date,
			end_date,
			workouts,
			type,
			options,
			owner: req.userId
		});

		res.status(200).json({ competition_id: competitionId });
	} catch (error: any) {
		if (error instanceof BadRequestError) {
			return res.status(400).json({ error: error.message });
		}

		res.status(500).json({ error: error.message });
	}
}

export async function startComp(req: AuthenticatedRequest, res: Response) {}

export async function getComp(req: AuthenticatedRequest, res: Response) {
	if (!hasRequiredKeys(['competitionId', 'userId'], req, res)) return;

	try {
		const competition = await getCompetition(req.params.competitionId);

		if (!competition) {
			return res.status(404).json({ error: `No competition found with id: ${req.params.competitionId}` });
		} else return competition;
	} catch (error: any) {
		res.status(500).json({ error: error.message });
	}
}

export async function getAllComps() {}

export async function inviteUsersToComp() {}

export async function getCompInvites() {}

export async function acceptCompInvite() {}

export async function declineCompInvite() {}
