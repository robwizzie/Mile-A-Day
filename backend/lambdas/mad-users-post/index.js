import { query } from 'db-controller';
import crypto from 'node:crypto';

const REQUIRED_KEYS = ['apple_id', 'username'];

export const handler = async event => {
	try {
		const body = JSON.parse(event.body);

		const missing_keys = REQUIRED_KEYS.filter(key => !body[key]);

		if (missing_keys.length) {
			return {
				statusCode: 400,
				body: JSON.stringify({ error: `missing required key(s): ${missing_keys.join(', ')}.` })
			};
		}

		const existingIdResults = await query('SELECT user_id, apple_id FROM users WHERE apple_id = $1', [body.apple_id]);
		const appleIdExists = !!existingIdResults?.rows?.length;

		if (appleIdExists) {
			return {
				statusCode: 400,
				body: JSON.stringify({ error: `account for ${body.apple_id} already exits.` })
			};
		}

		const userId = crypto.randomUUID().replaceAll('-', '');

		await query('INSERT INTO users (user_id, username, apple_id) VALUES ($1, $2, $3)', [
			userId,
			body.username,
			body.apple_id
		]);

		return {
			statusCode: 200,
			body: JSON.stringify({ message: 'user successfully created', user_id: userId })
		};
	} catch (err) {
		return {
			statusCode: 500,
			body: JSON.stringify({ error: err.message })
		};
	}
};
