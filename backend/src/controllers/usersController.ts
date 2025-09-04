import { Request, Response } from 'express';
import { PostgresService } from '../services/DbService.js';
import crypto from 'crypto';
import hasRequiredKeys from '../utils/hasRequiredKeys.js';
import { getUser as dbFetchUser, createUser as dbCreateUser } from '../services/userService.js';
import { AppleAuthRequest } from '../types/user.js';

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

export async function searchUsers(req: Request, res: Response) {
	if (!hasRequiredKeys([['username', 'email']], req, res)) return;

	const { username, email } = req.query;

	const results = await db.query(`SELECT * FROM users WHERE ${username ? 'username' : 'email'} = $1`, [username ?? email]);

	if (!results.length) {
		return res.status(404).json({
			error: 'User not found'
		});
	}

	res.json(results[0]);
}

export async function createUser(req: Request, res: Response) {
	const user_id = crypto.randomUUID().replaceAll('-', '');
	const { username, email, first_name = null, last_name = null } = req.body;

	const existingAppleId = await db.query('SELECT user_id FROM users WHERE email = $1', [email]);

	if (existingAppleId.length) {
		return res.status(400).json({
			error: 'Bad Request',
			message: `User already exists with Apple ID ${email}`
		});
	}

	await db.query('INSERT INTO users (user_id, username, email, first_name, last_name) VALUES ($1, $2, $3, $4, $5)', [
		user_id,
		username,
		email,
		first_name,
		last_name
	]);

	res.json({
		user_id,
		username,
		email,
		first_name,
		last_name
	});
}

export async function signIn(req: Request, res: Response) {
	if (!hasRequiredKeys(['user_id', 'identity_token', 'authorization_code'], req, res)) return;

	const authData: AppleAuthRequest = {
		user_id: req.body.user_id,
		identity_token: req.body.identity_token,
		authorization_code: req.body.authorization_code,
		email: req.body.email
	};

	let user = await dbFetchUser({ email: req.body.email });

	if (!user) {
		const { user_id } = await dbCreateUser({ email: req.body.email, apple_id: authData.user_id });
		user = { user_id, email: req.body.email };
	}

	const timestamp = Date.now();
	const randomBytes = crypto.randomBytes(16).toString('hex');
	const token = `${user.user_id}.${timestamp}.${randomBytes}`;
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
