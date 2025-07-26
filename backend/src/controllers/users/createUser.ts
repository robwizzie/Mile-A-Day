import { Request, Response } from 'express';
import { PostgresService } from '../../services/DbService.js';
import crypto from 'crypto';

const REQUIRED_KEYS = ['username', 'apple_id'];

const db = PostgresService.getInstance();

export default async function createUser(req: Request, res: Response) {
	const missingKeys = REQUIRED_KEYS.filter(k => !Object.keys(req.body).includes(k));

	if (missingKeys.length) {
		return res.status(400).json({
			error: 'Bad Request',
			message: `Missing required keys: ${missingKeys.join(', ')}`
		});
	}

	const user_id = crypto.randomUUID().replaceAll('-', '');
	const { username, apple_id, first_name = null, last_name = null } = req.body;

	const existingAppleId = await db.query('SELECT user_id FROM users WHERE apple_id = $1', [apple_id]);

	if (existingAppleId.length) {
		return res.status(400).json({
			error: 'Bad Request',
			message: `User already exists with Apple ID ${apple_id}`
		});
	}

	await db.query('INSERT INTO users (user_id, username, apple_id, first_name, last_name) VALUES ($1, $2, $3, $4, $5)', [
		user_id,
		username,
		apple_id,
		first_name,
		last_name
	]);

	res.json({
		user_id,
		username,
		apple_id,
		first_name,
		last_name
	});
}
