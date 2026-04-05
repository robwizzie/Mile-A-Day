import { Response } from 'express';
import { AuthenticatedRequest } from '../middleware/auth.js';
import {
	getNotificationPreferences,
	updateNotificationPreferences,
	getFriendNotificationSettings,
	updateFriendNotificationSettings,
} from '../services/notificationSettingsService.js';

export async function getPreferences(req: AuthenticatedRequest, res: Response) {
	try {
		const prefs = await getNotificationPreferences(req.userId!);
		res.status(200).json(prefs);
	} catch (error: any) {
		console.error('Error getting notification preferences:', error.message);
		res.status(500).json({ error: 'Error getting notification preferences' });
	}
}

export async function updatePreferences(req: AuthenticatedRequest, res: Response) {
	try {
		const updated = await updateNotificationPreferences(req.userId!, req.body);
		res.status(200).json(updated);
	} catch (error: any) {
		console.error('Error updating notification preferences:', error.message);
		res.status(500).json({ error: 'Error updating notification preferences' });
	}
}

export async function getFriendSettings(req: AuthenticatedRequest, res: Response) {
	try {
		const settings = await getFriendNotificationSettings(req.userId!);
		res.status(200).json({ settings });
	} catch (error: any) {
		console.error('Error getting friend notification settings:', error.message);
		res.status(500).json({ error: 'Error getting friend notification settings' });
	}
}

export async function updateFriendSettings(req: AuthenticatedRequest, res: Response) {
	const friendId = req.params.friendId;
	const { muted, nudges_muted, activity_muted } = req.body;

	try {
		const updated = await updateFriendNotificationSettings(req.userId!, friendId, {
			muted,
			nudges_muted,
			activity_muted,
		});
		res.status(200).json(updated);
	} catch (error: any) {
		console.error('Error updating friend notification settings:', error.message);
		res.status(500).json({ error: 'Error updating friend notification settings' });
	}
}
