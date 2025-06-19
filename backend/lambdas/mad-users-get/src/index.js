import { userDB } from './mock-data.js';

export const handler = async event => {
	const userId = event.pathParameters.userId;

	if (!userId) {
		return {
			statusCode: 400,
			body: JSON.stringify({ error: 'userId is undefined!' })
		};
	}

	const user = userDB[userId];

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
};
