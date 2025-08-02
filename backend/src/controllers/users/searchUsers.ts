import { Request, Response } from 'express';
import { PostgresService } from '../../services/DbService.js';

const db = PostgresService.getInstance();

export default async function searchUsers(req: Request, res: Response) {
	const { username, email } = req.query;

	if (!username && !email) {
		return res.status(400).json({ error: 'Missing username or email query parameter' });
	}

	const results = await db.query(`SELECT * FROM users WHERE ${username ? 'username' : 'email'} = $1`, [username ?? email]);

	if (!results.length) {
		return res.status(404).json({
			error: 'User not found'
		});
	}

	res.json(results[0]);
}
