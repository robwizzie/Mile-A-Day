import { Request, Response } from 'express';
import { PostgresService } from '../../services/DbService.js';

const db = PostgresService.getInstance();

export default async function deleteUser(req: Request, res: Response) {
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
