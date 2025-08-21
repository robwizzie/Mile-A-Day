import { PostgresService } from './DbService.js';
import { AppleAuthRequest, User } from '../types/user.js';
import crypto from 'crypto';

const db = PostgresService.getInstance();

export class AppleAuthService {
	private static instance: AppleAuthService;

	private constructor() {}

	public static getInstance(): AppleAuthService {
		if (!AppleAuthService.instance) {
			AppleAuthService.instance = new AppleAuthService();
		}
		return AppleAuthService.instance;
	}

	/**
	 * Authenticate user with Apple Sign In
	 */
	public async authenticateUser(authData: AppleAuthRequest): Promise<{ user: User; token: string }> {
		// For now, we'll do basic validation without full Apple token verification
		// In production, you should verify the identity token with Apple's servers

		// Check if user already exists
		let user = await this.findUserByAppleId(authData.user_id);

		if (!user) {
			// Create new user
			user = await this.createUserFromApple(authData);
		} else {
			// Update existing user if we have new information
			user = await this.updateUserFromApple(user.user_id, authData);
		}

		// Generate app token
		const token = this.generateAppToken(user.user_id);

		return { user, token };
	}

	/**
	 * Find user by Apple ID
	 */
	private async findUserByAppleId(appleId: string): Promise<User | null> {
		const results = await db.query('SELECT * FROM users WHERE apple_id = $1', [appleId]);
		return results.length > 0 ? results[0] : null;
	}

	/**
	 * Create new user from Apple Sign In data
	 */
	private async createUserFromApple(authData: AppleAuthRequest): Promise<User> {
		const user_id = crypto.randomUUID().replaceAll('-', '');
		const username = authData.full_name || `user_${user_id.slice(0, 8)}`;

		// Split full name into first and last name
		const nameParts = authData.full_name?.split(' ') || [];
		const first_name = nameParts[0] || undefined;
		const last_name = nameParts.slice(1).join(' ') || undefined;

		await db.query(
			'INSERT INTO users (user_id, username, email, first_name, last_name, apple_id, auth_provider) VALUES ($1, $2, $3, $4, $5, $6, $7)',
			[user_id, username, authData.email, first_name, last_name, authData.user_id, 'apple']
		);

		return {
			user_id,
			username,
			email: authData.email || '',
			first_name,
			last_name,
			apple_id: authData.user_id,
			auth_provider: 'apple'
		};
	}

	/**
	 * Update existing user with new Apple data
	 */
	private async updateUserFromApple(userId: string, authData: AppleAuthRequest): Promise<User> {
		const updates: string[] = [];
		const values: any[] = [];

		// Only update if we have new information
		if (authData.email) {
			values.push(authData.email);
			updates.push(`email = $${values.length}`);
		}

		if (authData.full_name) {
			const nameParts = authData.full_name.split(' ');
			const first_name = nameParts[0];
			const last_name = nameParts.slice(1).join(' ');

			values.push(first_name);
			updates.push(`first_name = $${values.length}`);
			values.push(last_name);
			updates.push(`last_name = $${values.length}`);
		}

		if (updates.length > 0) {
			values.push(userId);
			const query = `
				UPDATE users
				SET ${updates.join(', ')}
				WHERE user_id = $${values.length}
				RETURNING *
			`;
			const results = await db.query(query, values);
			return results[0];
		}

		// Return existing user if no updates needed
		const results = await db.query('SELECT * FROM users WHERE user_id = $1', [userId]);
		return results[0];
	}

	/**
	 * Generate a simple app token (in production, use proper JWT)
	 */
	private generateAppToken(userId: string): string {
		// This is a simple token generation - in production, use a proper JWT library
		const timestamp = Date.now();
		const randomBytes = crypto.randomBytes(16).toString('hex');
		return `${userId}.${timestamp}.${randomBytes}`;
	}

	/**
	 * Verify app token (in production, use proper JWT verification)
	 */
	public verifyAppToken(token: string): string | null {
		try {
			const parts = token.split('.');
			if (parts.length === 3) {
				return parts[0]; // Return user ID
			}
		} catch (error) {
			console.error('Token verification failed:', error);
		}
		return null;
	}
}
