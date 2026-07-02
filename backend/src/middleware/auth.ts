import { Request, Response, NextFunction } from 'express';
import { jwtVerify } from 'jose';
import { PostgresService } from '../services/DbService.js';

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
		// 401 (not 403) for a bad/expired credential: this is an AUTHENTICATION
		// failure the client must recover from by refreshing or signing out. 403
		// is reserved for AUTHORIZATION failures (authenticated but not allowed),
		// which must NOT trigger a sign-out. Shipped clients only run their
		// refresh+retry / force-logout path on 401, so returning 403 here left
		// users stuck: every call failed and they were never bounced to login.
		return res.status(401).json({ error: 'Invalid or expired token' });
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

// Gate for admin-only routes. Runs AFTER authenticateToken (req.userId set).
// 403 (authenticated but not allowed) so the app client's 401-only re-login path is not triggered.
export async function requireAdmin(req: AuthenticatedRequest, res: Response, next: NextFunction) {
	if (!req.userId) {
		return res.status(401).json({ error: 'Authentication required' });
	}

	try {
		const rows = await PostgresService.getInstance().query('SELECT role FROM users WHERE user_id = $1', [req.userId]);
		if (rows[0]?.role !== 'admin') {
			return res.status(403).json({ error: 'Admin access required' });
		}
		next();
	} catch (err) {
		console.error('requireAdmin lookup failed:', err);
		return res.status(500).json({ error: 'Authorization check failed' });
	}
}
