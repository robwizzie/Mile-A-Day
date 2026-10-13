import { Response } from 'express';
import { AuthenticatedRequest } from '../middleware/auth.js';
import {
	upsertDailySteps,
	upsertDailyStepsBatch,
	DAILY_STEPS_BATCH_MAX_DAYS,
	DailyStepsBatchDay,
} from '../services/dailyStepsService.js';

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

/**
 * PUT /users/:userId/daily-steps/batch
 * Body: { days: [{ localDate: "YYYY-MM-DD", steps: number }], timezoneOffset: number }
 * The phone's step history in one request (see upsertDailyStepsBatch).
 */
export async function putDailyStepsBatch(req: AuthenticatedRequest, res: Response) {
	try {
		const userId = req.params.userId;
		const { days, timezoneOffset } = req.body ?? {};

		if (!Array.isArray(days)) {
			return res.status(400).json({ error: 'days must be an array' });
		}
		if (days.length > DAILY_STEPS_BATCH_MAX_DAYS) {
			return res
				.status(400)
				.json({ error: `days may hold at most ${DAILY_STEPS_BATCH_MAX_DAYS} entries` });
		}
		if (typeof timezoneOffset !== 'number' || !Number.isInteger(timezoneOffset)) {
			return res.status(400).json({ error: 'timezoneOffset must be an integer' });
		}

		const parsed: DailyStepsBatchDay[] = [];
		for (const d of days) {
			const localDate = d?.localDate;
			const steps = d?.steps;
			if (typeof localDate !== 'string' || !LOCAL_DATE_RE.test(localDate)) {
				return res.status(400).json({ error: 'every localDate must be YYYY-MM-DD' });
			}
			if (typeof steps !== 'number' || !Number.isFinite(steps) || steps < 0) {
				return res.status(400).json({ error: 'every steps must be a non-negative number' });
			}
			parsed.push({ localDate, steps: Math.floor(steps) });
		}

		const result = await upsertDailyStepsBatch(userId, parsed, timezoneOffset);
		return res.status(200).json(result);
	} catch (err: any) {
		console.error('Error upserting daily steps batch:', err.message);
		return res.status(500).json({ error: 'Error upserting daily steps batch: ' + err.message });
	}
}
