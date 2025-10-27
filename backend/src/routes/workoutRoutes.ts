import { Router } from 'express';
import { getRecentWorkouts, getStreak, getWorkoutRange, uploadWorkouts } from '../controllers/workoutController.js';
import { requireSelfAccess } from '../middleware/auth.js';

const router = Router();

router.post('/:userId/upload', requireSelfAccess('userId'), uploadWorkouts);
router.get('/:userId/streak', getStreak);
router.get('/:userId/range', getWorkoutRange);
router.get('/:userId/recent', getRecentWorkouts);

export default router;
