import { Router } from 'express';
import {
	getPreferences,
	updatePreferences,
	getFriendSettings,
	updateFriendSettings
} from '../controllers/notificationSettingsController.js';
import {
	getInAppNotifications,
	markNotificationRead,
	markAllRead,
	getUnreadCount
} from '../controllers/inAppNotificationController.js';
import { getAudienceSettingsHandler, putAudienceSettingHandler } from '../controllers/audienceSettingsController.js';

const router = Router();

// Global notification preferences
router.get('/preferences', getPreferences);
router.put('/preferences', updatePreferences);

// Audience settings (who gets notified / who notifies me)
router.get('/audience', getAudienceSettingsHandler);
router.put('/audience', putAudienceSettingHandler);

// Friend-specific notification settings
router.get('/friends', getFriendSettings);
router.put('/friends/:friendId', updateFriendSettings);

// In-app notification center
router.get('/inbox', getInAppNotifications);
router.get('/inbox/unread-count', getUnreadCount);
router.put('/inbox/:notificationId/read', markNotificationRead);
router.put('/inbox/read-all', markAllRead);

export default router;
