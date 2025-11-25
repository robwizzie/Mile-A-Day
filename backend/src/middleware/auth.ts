import { Request, Response, NextFunction } from 'express';
import { jwtVerify } from 'jose';

export interface AuthenticatedRequest extends Request {
	userId?: string;
}

export async function authenticateToken(req: AuthenticatedRequest, res: Response, next: NextFunction) {
	const authHeader = req.headers.authorization;
	const token = authHeader && authHeader.split(' ')[1];

	if (!token) {
		return res.status(401).json({ error: 'Access token required' });
	}

	try {
		const appJwtSecret = process.env.APP_JWT_SECRET;

		const { payload } = await jwtVerify(token, new TextEncoder().encode(appJwtSecret));
		req.userId = payload.sub as string;
		next();
	} catch (err) {
		console.error('Token verification failed:', err);
		return res.status(403).json({ error: 'Invalid or expired token' });
	}
}

export function requireOwnership(req: AuthenticatedRequest, res: Response, next: NextFunction) {
	const resourceUserId = req.params.userId;

	if (!req.userId) {
		return res.status(401).json({ error: 'Authentication required' });
	}

	if (req.userId !== resourceUserId) {
		return res.status(403).json({ error: 'Access denied - insufficient permissions' });
	}

	next();
}

export function requireSelfAccess(paramName: string = 'userId') {
	return (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
		const keys = { ...req.query, ...req.body, ...req.params };
		const resourceUserId = keys[paramName];

		if (!req.userId) {
			return res.status(401).json({ error: 'Authentication required' });
		}

		if (req.userId !== resourceUserId) {
			return res.status(403).json({ error: 'Access denied - can only access your own data' });
		}

		next();
	};
}
