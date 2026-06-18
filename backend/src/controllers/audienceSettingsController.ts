import { Response } from 'express';
import { AuthenticatedRequest } from '../middleware/auth.js';
import { getAudienceSettings, setAudienceSetting, SYSTEM_DEFAULTS } from '../services/audienceSettingsService.js';

export async function getAudienceSettingsHandler(req: AuthenticatedRequest, res: Response) {
	try {
		const settings = await getAudienceSettings(req.userId!);
		res.status(200).json({ settings, systemDefaults: SYSTEM_DEFAULTS });
	} catch (error: any) {
		console.error('Error getting audience settings:', error.message);
		res.status(500).json({ error: 'Error getting audience settings' });
	}
}

export async function putAudienceSettingHandler(req: AuthenticatedRequest, res: Response) {
	try {
		const { direction, event_type, activity_type, audience } = req.body;

		if (!direction || !event_type) {
			return res.status(400).json({ error: 'direction and event_type are required' });
		}

		// audience: null/undefined/omitted = reset (DELETE row); otherwise must be a valid value
		const audienceValue = audience ?? null;

		const result = await setAudienceSetting(req.userId!, direction, event_type, activity_type ?? '', audienceValue);

		if ('validationError' in result) {
			return res.status(400).json({ error: result.validationError });
		}

		res.status(200).json({ settings: result, systemDefaults: SYSTEM_DEFAULTS });
	} catch (error: any) {
		console.error('Error updating audience setting:', error.message);
		res.status(500).json({ error: 'Error updating audience setting' });
	}
}
