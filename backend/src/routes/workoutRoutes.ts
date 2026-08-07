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
  getWorkoutRouteController,
  getRaceRecords,
  getRaceHistoryController,
  getStreakEras,
  getDuplicates,
  setDuplicateDecisionController,
  resolveDuplicates,
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
// Cross-app duplicates (the same run written to HealthKit by two connected
// apps). Self-only both ways: the read exposes the user's own workout history,
// and the resolve is the one action that can change their historical totals.
router.get("/:userId/duplicates", requireSelfAccess("userId"), getDuplicates);
router.post(
  "/:userId/duplicates/resolve",
  requireSelfAccess("userId"),
  resolveDuplicates,
);
// One workout, one answer: "count it" / "don't". The user's decision outranks
// detection and survives the recompute that runs on every sync.
//
// MUST stay below /resolve: Express matches in registration order, and a
// wildcard registered first would capture the literal "resolve" as a workout id
// and silently turn the history-cleanup action into a 404.
router.post(
  "/:userId/duplicates/:workoutId",
  requireSelfAccess("userId"),
  setDuplicateDecisionController,
);
// Self-only: friends' route visibility is governed by share_route_maps on
// feed payloads; the raw full-history dump is never exposed to others.
router.get(
  "/:userId/routes",
  requireSelfAccess("userId"),
  getUserRoutesController,
);
// ONE workout's trace, readable by any authenticated user so a friend's workout
// detail can draw its map — the same share_route_maps consent the feed applies
// gates it, and it can never become the full-history dump above.
router.get("/:userId/workout/:workoutId/route", getWorkoutRouteController);
router.get("/:userId/streak", getStreak);
// Streak history ("eras") + longest-ever, readable by any authenticated user
// (like /stats) so friend profiles can show the Hall of Streaks.
router.get("/:userId/streak-eras", getStreakEras);
router.get("/:userId/range", getWorkoutRange);
router.get("/:userId/recent", getRecentWorkouts);
router.get("/:userId/stats", getUserStats);
// Race PRs are readable by any authenticated user (like /stats) so friend
// profiles can display them. Specific `/race-records/:distance` first so it
// isn't shadowed.
router.get("/:userId/race-records/:distance", getRaceHistoryController);
router.get("/:userId/race-records", getRaceRecords);

export default router;
