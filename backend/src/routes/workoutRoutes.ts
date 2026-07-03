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
  getUserRoutesController,
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
// Self-only: friends' route visibility is governed by share_route_maps on
// feed payloads; the raw full-history dump is never exposed to others.
router.get(
  "/:userId/routes",
  requireSelfAccess("userId"),
  getUserRoutesController,
);
router.get("/:userId/streak", getStreak);
router.get("/:userId/range", getWorkoutRange);
router.get("/:userId/recent", getRecentWorkouts);
router.get("/:userId/stats", getUserStats);

export default router;
