import { Response } from 'express';
import { AuthenticatedRequest } from '../middleware/auth.js';
import { upsertDailySteps } from '../services/dailyStepsService.js';

const LOCAL_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

export async function putDailySteps(req: AuthenticatedRequest, res: Response) {
	try {
		const userId = req.params.userId;
		const { localDate, steps, timezoneOffset } = req.body ?? {};

		if (typeof localDate !== 'string' || !LOCAL_DATE_RE.test(localDate)) {
			return res.status(400).json({ error: 'localDate must be YYYY-MM-DD' });
		}
		if (typeof steps !== 'number' || !Number.isFinite(steps) || steps < 0) {
			return res.status(400).json({ error: 'steps must be a non-negative number' });
		}
		if (typeof timezoneOffset !== 'number' || !Number.isInteger(timezoneOffset)) {
			return res.status(400).json({ error: 'timezoneOffset must be an integer' });
		}

		const result = await upsertDailySteps(userId, localDate, Math.floor(steps), timezoneOffset);
		return res.status(200).json(result);
	} catch (err: any) {
		console.error('Error upserting daily steps:', err.message);
		return res.status(500).json({ error: 'Error upserting daily steps: ' + err.message });
	}
}
