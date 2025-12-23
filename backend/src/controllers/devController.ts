import { Request, Response } from 'express';
import { SignJWT } from 'jose';

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
