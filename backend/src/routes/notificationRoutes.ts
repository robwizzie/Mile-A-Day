import { Router } from 'express';
import {
	getPreferences,
	updatePreferences,
	getFriendSettings,
	updateFriendSettings,
} from '../controllers/notificationSettingsController.js';

const router = Router();

// Global notification preferences
router.get('/preferences', getPreferences);
router.put('/preferences', updatePreferences);

// Friend-specific notification settings
router.get('/friends', getFriendSettings);
router.put('/friends/:friendId', updateFriendSettings);

export default router;
