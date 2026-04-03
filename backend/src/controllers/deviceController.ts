import { Response } from 'express';
import { AuthenticatedRequest } from '../middleware/auth.js';
import { registerDeviceToken, unregisterDeviceToken } from '../services/pushNotificationService.js';
import hasRequiredKeys from '../utils/hasRequiredKeys.js';

export async function registerDevice(req: AuthenticatedRequest, res: Response) {
	if (!hasRequiredKeys(['device_token'], req, res)) return;

	try {
		await registerDeviceToken(req.userId!, req.body.device_token);
		res.status(200).json({ message: 'Device registered' });
	} catch (error: any) {
		console.error('Error registering device:', error.message);
		res.status(500).json({ error: 'Error registering device' });
	}
}

export async function unregisterDevice(req: AuthenticatedRequest, res: Response) {
	if (!hasRequiredKeys(['device_token'], req, res)) return;

	try {
		await unregisterDeviceToken(req.userId!, req.body.device_token);
		res.status(200).json({ message: 'Device unregistered' });
	} catch (error: any) {
		console.error('Error unregistering device:', error.message);
		res.status(500).json({ error: 'Error unregistering device' });
	}
}
