import { Request, Response } from 'express';

export default function hasRequiredKeys(keys: string[], req: Request, res: Response) {
	const missingKeys = keys.filter(key => !(key in req.body));

	if (!missingKeys.length) {
		return true;
	} else {
		res.status(400).send({
			error: `Body is missing required key${missingKeys.length > 1 ? 's' : ''}: ${missingKeys.join(', ')}`
		});

		return false;
	}
}
