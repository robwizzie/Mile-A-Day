import { Router } from "express";
import {
  getFriends,
  getFriendRequests,
  sendRequest,
  getFriendshipHandler,
  getSentRequests,
  getFriendsActivityToday,
  getSuggestions,
  getMutualFriends,
  getFriendsFeed,
} from "../controllers/friendshipsController.js";
import {
  nudgeFriend,
  checkNudgeStatus,
  checkNudgeStatusBatch,
} from "../controllers/friendNudgeController.js";
import { getSharedStreaksBatch } from "../controllers/sharedStreakController.js";
import {
  listCloseFriends,
  addCloseFriendHandler,
  removeCloseFriendHandler,
} from "../controllers/closeFriendsController.js";
import { requireSelfAccess } from "../middleware/auth.js";

const router = Router();

router.get(
  "/activity/today/:userId",
  requireSelfAccess("userId"),
  getFriendsActivityToday,
);
router.get("/suggestions/:userId", requireSelfAccess("userId"), getSuggestions);
// Public friends list — any authenticated user can view another user's friends
// (Instagram-style followers/following). No requireSelfAccess; two path
// segments so it never collides with the self-only '/:userId' below.
router.get("/list/:userId", getFriends);
// Mutual friend count between the authenticated viewer and :userId.
router.get("/mutual/:userId", getMutualFriends);
// Rolling-48h workout activity feed for the authenticated viewer + friends.
router.get("/feed", getFriendsFeed);
// NOTE: the self-only '/:userId' route lives below, AFTER the close-friends
// routes (which the friend-notif branch added), so those aren't shadowed.
router.get("/requests/:userId", requireSelfAccess("userId"), getFriendRequests);
router.get(
  "/sent-requests/:userId",
  requireSelfAccess("userId"),
  getSentRequests,
);

// Close friends routes (must be before /:userId to avoid shadowing)
router.get("/close", listCloseFriends);
router.post("/close/:friendId", addCloseFriendHandler);
router.delete("/close/:friendId", removeCloseFriendHandler);

router.get("/:userId", requireSelfAccess("userId"), getFriends);
router.post("/request", requireSelfAccess("fromUser"), sendRequest);
router.patch(
  "/accept",
  requireSelfAccess("toUser"),
  getFriendshipHandler("accepted"),
);
router.patch(
  "/ignore",
  requireSelfAccess("toUser"),
  getFriendshipHandler("ignored"),
);
router.delete(
  "/decline",
  requireSelfAccess("toUser"),
  getFriendshipHandler("rejected"),
);
router.delete(
  "/cancel",
  requireSelfAccess("fromUser"),
  getFriendshipHandler("rejected"),
);
router.delete(
  "/remove",
  requireSelfAccess("fromUser"),
  getFriendshipHandler("removed"),
);

// Friend streaks: shared consecutive-day streaks vs the viewer's friends.
// New endpoint (touches no existing route) — only the feature build calls it.
router.post("/shared-streaks", getSharedStreaksBatch);

// Nudge routes
router.post("/:friendId/nudge", nudgeFriend);
router.get("/:friendId/nudge-status", checkNudgeStatus);
router.post("/nudge-status/batch", checkNudgeStatusBatch);

export default router;
