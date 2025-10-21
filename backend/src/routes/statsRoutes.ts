import { Router } from 'express';
import { getStats, updateStats, addUserBadges, markUserBadgesViewed } from '../controllers/statsController.js';
import { requireSelfAccess } from '../middleware/auth.js';

const router = Router();

// Get user stats and badges (public endpoint - anyone can view)
router.get('/:userId', getStats);

// Update user stats (protected - can only update own stats)
router.patch('/:userId', requireSelfAccess('userId'), updateStats);

// Add badges to user (protected - can only add to own badges)
router.post('/:userId/badges', requireSelfAccess('userId'), addUserBadges);

// Mark all badges as viewed (protected - can only mark own badges)
router.patch('/:userId/badges/mark-viewed', requireSelfAccess('userId'), markUserBadgesViewed);

export default router;
