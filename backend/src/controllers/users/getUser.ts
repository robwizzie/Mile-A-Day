import { Request, Response } from 'express';

export default function getUser(_, res: Response) {
	res.json({
		username: 'david',
		first_name: 'david',
		last_name: 'simmerman',
		user_id: 'abc123',
		apple_id: 'david.simmerman@icloud.com'
	});
}
