import { Request, Response } from 'express';
import { AppleAuthService } from '../services/appleAuthService.js';
import { AppleAuthRequest } from '../types/user.js';
import hasRequiredKeys from '../utils/hasRequiredKeys.js';

const appleAuthService = AppleAuthService.getInstance();

export async function authenticateWithApple(req: Request, res: Response) {
	// Validate required fields
	if (!hasRequiredKeys(['user_id', 'identity_token', 'authorization_code'], req, res)) return;

	const authData: AppleAuthRequest = {
		user_id: req.body.user_id,
		identity_token: req.body.identity_token,
		authorization_code: req.body.authorization_code,
		email: req.body.email,
		full_name: req.body.full_name
	};

	try {
		const result = await appleAuthService.authenticateUser(authData);

		res.json({
			user: result.user,
			token: result.token
		});
	} catch (error) {
		console.error('Apple authentication error:', error);
		res.status(500).json({
			error: 'Authentication failed',
			message: 'Failed to authenticate with Apple'
		});
	}
}

export async function verifyToken(req: Request, res: Response) {
	if (!hasRequiredKeys(['token'], req, res)) return;

	const { token } = req.body;
	const userId = appleAuthService.verifyAppToken(token);

	if (!userId) {
		return res.status(401).json({
			error: 'Invalid token',
			message: 'The provided token is invalid or expired'
		});
	}

	res.json({
		user_id: userId,
		valid: true
	});
}
