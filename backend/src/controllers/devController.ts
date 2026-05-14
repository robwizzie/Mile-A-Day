import { Request, Response } from 'express';
import { SignJWT } from 'jose';
import { resolveExpiredCompetitions } from '../services/competitionService.js';
import { sendPush, sendSilentPushToUser } from '../services/pushNotificationService.js';
import { runSilentSyncPushFanout } from '../cron/silentSyncCron.js';

export async function generateTestToken(req: Request, res: Response) {
	const env = process.env.NODE_ENV;

	if (env === 'production') {
		return res.status(403).json({
			error: 'Test token generation is not available in production'
		});
	}

	const { userId } = req.body;

	if (!userId) {
		return res.status(400).json({
			error: 'userId is required in request body'
		});
	}

	const appJwtSecret = process.env.APP_JWT_SECRET;

	if (!appJwtSecret) {
		return res.status(500).json({
			error: 'APP_JWT_SECRET is not configured'
		});
	}

	try {
		const token = await new SignJWT({ provider: 'test' })
			.setProtectedHeader({ alg: 'HS256' })
			.setSubject(userId)
			.setIssuedAt()
			.setExpirationTime('30d')
			.sign(new TextEncoder().encode(appJwtSecret));

		const expiresAt = Date.now() + 30 * 24 * 60 * 60 * 1000;

		return res.json({
			token,
			userId,
			expiresIn: '30d',
			expiresAt,
			environment: env
		});
	} catch (err) {
		console.error('Error generating test token:', err);
		return res.status(500).json({
			error: 'Failed to generate test token'
		});
	}
}

export async function sendTestNotification(req: Request, res: Response) {
	if (process.env.NODE_ENV === 'production') {
		return res.status(403).json({ error: 'Not available in production' });
	}

	const { userId, message } = req.body;
	if (!userId || !message) {
		return res.status(400).json({ error: 'userId and message are required' });
	}

	try {
		await sendPush(userId, {
			title: 'Test Notification',
			body: message,
			type: 'friend_request',
			data: {}
		});
		return res.json({ success: true });
	} catch (err: any) {
		return res.status(500).json({ error: err.message });
	}
}

export async function triggerCompetitionCron(_req: Request, res: Response) {
	if (process.env.NODE_ENV === 'production') {
		return res.status(403).json({ error: 'Not available in production' });
	}

	try {
		await resolveExpiredCompetitions();
		return res.json({ success: true });
	} catch (err: any) {
		return res.status(500).json({ error: err.message });
	}
}

export async function triggerSilentSyncFanout(req: Request, res: Response): Promise<void> {
	try {
		const result = await runSilentSyncPushFanout();
		res.json({ success: true, ...result });
	} catch (err: any) {
		res.status(500).json({ success: false, error: err.message });
	}
}

export async function triggerSilentSyncForUser(req: Request, res: Response): Promise<void> {
	const userId = req.params.userId;
	if (!userId) {
		res.status(400).json({ success: false, error: 'userId required' });
		return;
	}
	try {
		const pushes = await sendSilentPushToUser(userId, 'background_sync');
		res.json({ success: true, userId, pushes });
	} catch (err: any) {
		res.status(500).json({ success: false, error: err.message });
	}
}
