import { Request, Response } from 'express';
import { PostgresService } from '../../services/DbService.js';

const db = PostgresService.getInstance();

const MUTABLE_FIELDS = ['username', 'first_name', 'last_name'];

export default async function updateUser(req: Request, res: Response) {
	const userId = req.params.id;
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
