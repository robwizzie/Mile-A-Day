import { Request, Response } from 'express';
import { PostgresService } from '../services/DbService.js';
import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import sharp from 'sharp';
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

const MUTABLE_FIELDS = ['username', 'first_name', 'last_name', 'bio'];

export async function updateUser(req: Request, res: Response) {
	if (!hasRequiredKeys(['userId'], req, res)) return;

	const userId = req.params.userId;
	const existingUserResults = await db.query('SELECT * FROM users WHERE user_id = $1', [userId]);

	if (!existingUserResults.length) {
		return res.status(404).json({
			error: 'User not found'
		});
	}

	// Check username uniqueness if being updated
	if (req.body.username !== undefined) {
		const existingUser = await db.query('SELECT user_id FROM users WHERE username = $1 AND user_id != $2', [
			req.body.username,
			userId
		]);
		if (existingUser.length > 0) {
			return res.status(400).json({ error: 'Username already taken' });
		}
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

	const userId = req.params.userId;

	const results = await db.query('SELECT * FROM users WHERE user_id = $1', [userId]);

	if (!results.length) {
		return res.status(404).json({
			error: 'User not found'
		});
	}

	// Permanently remove the account and every user-scoped row, in one transaction
	// (App Store Guideline 5.1.1(v) — account deletion must remove the user's data).
	//
	// Some child tables ON DELETE CASCADE from users (competition_users, daily_steps,
	// device_tokens, friendships, pending_notifications, refresh_tokens, user_badges,
	// user_challenge_completions) and would be cleaned up automatically — but we delete
	// them explicitly so this stays correct if constraints change. The tables below have
	// NO foreign key (the *_log + notification tables) or a NO ACTION FK
	// (in_app_notifications), so they MUST be deleted here or the final DELETE FROM users
	// either leaves orphaned rows or fails outright. competitions.owner/winner are
	// ON DELETE SET NULL, so the user's competitions survive with a null owner.
	const p = [userId];
	await db.transaction([
		{
			query: 'DELETE FROM workout_splits WHERE workout_id IN (SELECT workout_id FROM workouts WHERE user_id = $1)',
			params: p
		},
		{ query: 'DELETE FROM workouts WHERE user_id = $1', params: p },
		{ query: 'DELETE FROM competition_users WHERE user_id = $1', params: p },
		{
			query: 'DELETE FROM friendships WHERE user_id = $1 OR friend_id = $1',
			params: p
		},
		{
			query: 'DELETE FROM friend_notification_settings WHERE user_id = $1 OR friend_id = $1',
			params: p
		},
		{ query: 'DELETE FROM refresh_tokens WHERE user_id = $1', params: p },
		{ query: 'DELETE FROM device_tokens WHERE user_id = $1', params: p },
		{ query: 'DELETE FROM daily_steps WHERE user_id = $1', params: p },
		{ query: 'DELETE FROM user_badges WHERE user_id = $1', params: p },
		{
			query: 'DELETE FROM user_challenge_completions WHERE user_id = $1',
			params: p
		},
		{ query: 'DELETE FROM pending_notifications WHERE user_id = $1', params: p },
		{ query: 'DELETE FROM in_app_notifications WHERE user_id = $1', params: p },
		{ query: 'DELETE FROM notification_log WHERE user_id = $1', params: p },
		{ query: 'DELETE FROM notification_settings WHERE user_id = $1', params: p },
		{
			query: 'DELETE FROM workout_completion_notifications WHERE user_id = $1',
			params: p
		},
		{
			query: 'DELETE FROM milestone_notifications WHERE user_id = $1',
			params: p
		},
		{
			query: 'DELETE FROM hype_log WHERE sender_id = $1 OR target_id = $1',
			params: p
		},
		{
			query: 'DELETE FROM nudge_log WHERE sender_id = $1 OR target_id = $1',
			params: p
		},
		{
			query: 'DELETE FROM friend_nudge_log WHERE sender_id = $1 OR target_id = $1',
			params: p
		},
		{
			query: 'DELETE FROM flex_log WHERE sender_id = $1 OR target_id = $1',
			params: p
		},
		{ query: 'DELETE FROM users WHERE user_id = $1', params: p }
	]);

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
	} catch (error: any) {
		console.error('Error: username check failed:', error.message);
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

export async function uploadProfileImage(req: Request, res: Response) {
	const userId = req.params.userId;

	if (!req.file) {
		return res.status(400).json({ error: 'No image file provided' });
	}

	try {
		// Look up existing profile image to delete old file
		const existingUser = await db.query('SELECT profile_image_url FROM users WHERE user_id = $1', [userId]);
		if (existingUser.length && existingUser[0].profile_image_url) {
			const oldPath = path.join(process.cwd(), existingUser[0].profile_image_url);
			if (fs.existsSync(oldPath)) {
				fs.unlinkSync(oldPath);
			}
		}

		// Process image with sharp: resize and compress
		const filename = `${userId}-${Date.now()}.jpg`;
		const outputPath = path.join(process.cwd(), 'uploads', 'profile-images', filename);

		await sharp(req.file.buffer).resize(512, 512, { fit: 'cover' }).jpeg({ quality: 80 }).toFile(outputPath);

		const profileImageUrl = `/uploads/profile-images/${filename}`;
		await updateProfileImage({ userId, profileImageUrl });

		res.json({ success: true, profileImageUrl });
	} catch (error) {
		res.status(500).json({
			error: 'Profile image upload failed',
			message: error instanceof Error ? error.message : 'Unknown error'
		});
	}
}
