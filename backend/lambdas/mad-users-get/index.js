import { query } from 'db-controller';

export const handler = async event => {
	try {
		const userId = event.pathParameters.userId;

		if (!userId) {
			return {
				statusCode: 400,
				body: JSON.stringify({ error: 'userId is undefined!' })
			};
		}

		const userQueryResults = await query('SELECT * FROM users WHERE user_id = $1', [userId]);
		const user = userQueryResults?.rows?.[0];

		if (!user) {
			return {
				statusCode: 404,
				body: JSON.stringify({ error: `No user found for ID: ${userId}` })
			};
		}

		return {
			statusCode: 200,
			body: JSON.stringify(user)
		};
	} catch (err) {
		return {
			statusCode: 500,
			body: JSON.stringify({ error: err.message })
		};
	}
};
