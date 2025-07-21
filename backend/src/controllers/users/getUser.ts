import { Request, Response } from 'express';
import { PostgresService } from '../../services/DbService.js';

const db = PostgresService.getInstance();

export default async function getUser(req: Request, res: Response) {
	const results = await db.query('SELECT * FROM users WHERE user_id = $1', [req.params.id]);

	if (!results.length) {
		return res.status(404).json({
			error: 'User not found'
		});
	}

	res.json(results[0]);
}
