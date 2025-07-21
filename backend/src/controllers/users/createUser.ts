import { Request, Response } from 'express';
import { PostgresService } from '../../services/DbService.js';

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
