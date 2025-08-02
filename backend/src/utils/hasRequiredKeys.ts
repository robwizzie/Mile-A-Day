import { Request, Response } from 'express';

export default function hasRequiredKeys(keys: any[], req: Request, res: Response) {
	const definedKeys = { ...req.query, ...req.body, ...req.params };

	const missingKeys = keys
		.filter(key => {
			if (typeof key === 'string') {
				return !(key in definedKeys);
			} else if (Array.isArray(key)) {
				return key.every(key => !(key in definedKeys));
			}
		})
		.flat();

	if (!missingKeys.length) {
		return true;
	} else {
		res.status(400).send({
			error: `Missing required key${missingKeys.length > 1 ? 's' : ''}: ${missingKeys.join(', ')}`
		});

		return false;
	}
}
