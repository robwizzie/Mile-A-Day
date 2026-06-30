import { Router } from "express";
import {
  getRecentWorkouts,
  getStreak,
  getUserStats,
  getWorkoutRange,
  uploadWorkouts,
  updateWorkout,
  recalibrateStreak,
  deleteWorkout,
} from "../controllers/workoutController.js";
import { requireSelfAccess } from "../middleware/auth.js";

const router = Router();

router.post("/:userId/upload", requireSelfAccess("userId"), uploadWorkouts);
router.post(
  "/:userId/recalibrate-streak",
  requireSelfAccess("userId"),
  recalibrateStreak,
);
router.patch(
  "/:userId/workout/:workoutId",
  requireSelfAccess("userId"),
  updateWorkout,
);
router.delete(
  "/:userId/workout/:workoutId",
  requireSelfAccess("userId"),
  deleteWorkout,
);
router.get("/:userId/streak", getStreak);
router.get("/:userId/range", getWorkoutRange);
router.get("/:userId/recent", getRecentWorkouts);
router.get("/:userId/stats", getUserStats);

export default router;
