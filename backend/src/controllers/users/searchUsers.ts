import { Request, Response } from 'express';
import { PostgresService } from '../../services/DbService.js';

const db = PostgresService.getInstance();

export default async function searchUsers(req: Request, res: Response) {
	const { username, apple_id } = req.query;

	if (!username && !apple_id) {
		return res.status(400).json({ error: 'Missing username or apple_id query parameter' });
	}

	const results = await db.query(`SELECT * FROM users WHERE ${username ? 'username' : 'apple_id'} = $1`, [
		username ?? apple_id
	]);

	if (!results.length) {
		return res.status(404).json({
			error: 'User not found'
		});
	}

	res.json(results[0]);
}
