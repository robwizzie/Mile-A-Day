import { Router } from 'express';
import { getRecentWorkouts, getStreak, getUserStats, getWorkoutRange, uploadWorkouts, updateWorkout } from '../controllers/workoutController.js';
import { requireSelfAccess } from '../middleware/auth.js';

const router = Router();

router.post('/:userId/upload', requireSelfAccess('userId'), uploadWorkouts);
router.patch('/:userId/workout/:workoutId', requireSelfAccess('userId'), updateWorkout);
router.get('/:userId/streak', getStreak);
router.get('/:userId/range', getWorkoutRange);
router.get('/:userId/recent', getRecentWorkouts);
router.get('/:userId/stats', getUserStats);

export default router;
