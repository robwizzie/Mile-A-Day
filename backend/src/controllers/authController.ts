import { Request, Response } from 'express';
import hasRequiredKeys from '../utils/hasRequiredKeys.js';
import { getUser as dbGetUser, createUser as dbCreateUser } from '../services/userService.js';
import { createRemoteJWKSet, jwtVerify } from 'jose';
import { generateAccessToken } from '../services/tokenService.js';
import {
	createRefreshToken,
	rotateRefreshToken,
	revokeRefreshToken,
	revokeAllUserTokens
} from '../services/refreshTokenService.js';
import { AuthenticatedRequest } from '../middleware/auth.js';

export async function signIn(req: Request, res: Response) {
	if (!hasRequiredKeys(['user_id', 'identity_token', 'authorization_code'], req, res)) return;

	const identityToken = req.body.identity_token as string;
	const email = req.body.email as string;

	const expectedAudience = process.env.APPLE_CLIENT_ID;

	try {
		const APPLE_ISS = 'https://appleid.apple.com';
		const jwks = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));
		const { payload } = await jwtVerify(identityToken, jwks, {
			issuer: APPLE_ISS,
			audience: expectedAudience
		});

		const appleSub = payload.sub as string;
		const emailFromToken = (payload.email as string | undefined) ?? email;

		let user = await dbGetUser({ email: emailFromToken });

		if (!user) {
			user = await dbCreateUser({ email: emailFromToken, apple_sub: appleSub });
		}

		const accessToken = await generateAccessToken(user.user_id);
		const refreshToken = await createRefreshToken(user.user_id, {
			userAgent: req.headers['user-agent'],
			ipAddress: req.ip,
			deviceInfo: req.body.device_info
		});

		const expiresAt = Date.now() + 30 * 24 * 60 * 60 * 1000;

		return res.json({ user, accessToken, refreshToken, expiresIn: '30d', expiresAt });
	} catch (err) {
		console.error('Apple sign-in failed', err);
		return res.status(401).json({ error: 'Invalid Apple identity token' });
	}
}

export async function refresh(req: Request, res: Response) {
	if (!hasRequiredKeys(['refreshToken'], req, res)) return;

	const { refreshToken } = req.body;

	try {
		const tokenPair = await rotateRefreshToken(refreshToken, {
			userAgent: req.headers['user-agent'],
			ipAddress: req.ip,
			deviceInfo: req.body.device_info
		});

		const expiresAt = Date.now() + 30 * 24 * 60 * 60 * 1000;

		return res.json({ ...tokenPair, expiresIn: '30d', expiresAt });
	} catch (err) {
		console.error('Token refresh failed', err);
		return res.status(403).json({
			error: 'Invalid or expired refresh token',
			message: err instanceof Error ? err.message : 'Token refresh failed'
		});
	}
}

export async function logout(req: Request, res: Response) {
	if (!hasRequiredKeys(['refreshToken'], req, res)) return;

	const { refreshToken } = req.body;

	try {
		await revokeRefreshToken(refreshToken, 'manual_logout');
		return res.json({ success: true, message: 'Logged out successfully' });
	} catch (err) {
		console.error('Logout failed', err);
		return res.status(500).json({ error: 'Logout failed' });
	}
}

export async function logoutAll(req: AuthenticatedRequest, res: Response) {
	if (!req.userId) {
		return res.status(401).json({ error: 'Authentication required' });
	}

	try {
		const revokedCount = await revokeAllUserTokens(req.userId, 'manual_logout_all');
		return res.json({
			success: true,
			message: 'All sessions revoked',
			revokedCount
		});
	} catch (err) {
		console.error('Logout all failed', err);
		return res.status(500).json({ error: 'Logout all failed' });
	}
}
