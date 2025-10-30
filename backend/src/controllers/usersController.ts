import { Request, Response } from 'express';
import { PostgresService } from '../services/DbService.js';
import crypto from 'crypto';
import hasRequiredKeys from '../utils/hasRequiredKeys.js';
import { updateUsername, checkUsernameAvailability, updateBio, updateProfileImage } from '../services/userService.js';

const db = PostgresService.getInstance();

export async function getUser(req: Request, res: Response) {
	if (!hasRequiredKeys(['userId'], req, res)) return;

	const results = await db.query('SELECT * FROM users WHERE user_id = $1', [req.params.userId]);

	if (!results.length) {
		return res.status(404).json({
			error: 'User not found'
		});
	}

	res.json(results[0]);
}

// TODO user should be excluded from their own results
export async function searchUsers(req: Request, res: Response) {
	if (!hasRequiredKeys(['query'], req, res)) return;

	const { query } = req.query;

	const results = await db.query(`SELECT * FROM users WHERE username ILIKE $1 OR email ILIKE $1 LIMIT 50`, [`%${query}%`]);

	if (!results.length) {
		return res.status(404).json({
			error: 'User not found'
		});
	}

	res.json(results);
}

const MUTABLE_FIELDS = ['username', 'first_name', 'last_name'];

export async function updateUser(req: Request, res: Response) {
	if (!hasRequiredKeys(['userId'], req, res)) return;

	const userId = req.params.userId;
	const existingUserResults = await db.query('SELECT * FROM users WHERE user_id = $1', [userId]);

	if (!existingUserResults.length) {
		return res.status(404).json({
			error: 'User not found'
		});
	}

	const updates: string[] = [];
	const values: any[] = [];

	MUTABLE_FIELDS.forEach(key => {
		const value = req.body[key];
		if (value === undefined) return;
		values.push(value);
		updates.push(`${key} = $${values.length}`);
	});

	if (!updates.length) {
		return res.status(400).json({ error: 'No valid update fields present in request.' });
	}

	values.push(userId);

	const query = `
        UPDATE users
        SET ${updates.join(', ')}
        WHERE user_id = $${values.length}
        RETURNING *
    `;

	const results = await db.query(query, values);

	res.json(results[0]);
}

export async function deleteUser(req: Request, res: Response) {
	if (!hasRequiredKeys(['userId'], req, res)) return;

	const userId = req.params.id;

	const results = await db.query('SELECT * FROM users WHERE user_id = $1', [userId]);

	if (!results.length) {
		return res.status(404).json({
			error: 'User not found'
		});
	}

	await db.query('DELETE FROM users WHERE user_id = $1', [userId]);

	res.json({
		message: `Successfully deleted user ${userId}`
	});
}

export async function updateUserUsername(req: Request, res: Response) {
	if (!hasRequiredKeys(['username'], req, res)) return;

	const userId = req.params.userId;
	const { username } = req.body;

	try {
		await updateUsername({ userId, username });
		res.json({ success: true, message: 'Username updated successfully' });
	} catch (error) {
		res.status(400).json({
			error: 'Username update failed',
			message: error instanceof Error ? error.message : 'Unknown error'
		});
	}
}

export async function checkUsername(req: Request, res: Response) {
	if (!hasRequiredKeys(['username'], req, res)) return;

	const { username } = req.query;

	try {
		const isAvailable = await checkUsernameAvailability(username as string);
		res.json({ available: isAvailable });
	} catch (error) {
		res.status(500).json({
			error: 'Username check failed',
			message: error instanceof Error ? error.message : 'Unknown error'
		});
	}
}

export async function updateUserBio(req: Request, res: Response) {
	if (!hasRequiredKeys(['bio'], req, res)) return;

	const userId = req.params.userId;
	const { bio } = req.body;

	try {
		await updateBio({ userId, bio });
		res.json({ success: true, message: 'Bio updated successfully' });
	} catch (error) {
		res.status(400).json({
			error: 'Bio update failed',
			message: error instanceof Error ? error.message : 'Unknown error'
		});
	}
}

export async function updateUserProfileImage(req: Request, res: Response) {
	if (!hasRequiredKeys(['profileImageUrl'], req, res)) return;

	const userId = req.params.userId;
	const { profileImageUrl } = req.body;

	try {
		await updateProfileImage({ userId, profileImageUrl });
		res.json({ success: true, message: 'Profile image updated successfully' });
	} catch (error) {
		res.status(400).json({
			error: 'Profile image update failed',
			message: error instanceof Error ? error.message : 'Unknown error'
		});
	}
}
