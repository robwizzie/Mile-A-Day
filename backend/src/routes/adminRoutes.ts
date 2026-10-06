import { Router } from "express";
import { signInLimiter } from "../middleware/rateLimit.js";
import {
  adminCreateDisplayKey,
  adminListDisplayKeys,
  adminRevokeDisplayKey,
  adminListDisplayMessages,
  adminSendDisplayMessage,
  adminDeskBoxes,
  adminDeskBox,
  adminDeskBoxSettings,
  adminDeskBoxTap,
  adminDeskBoxMessage,
} from "../controllers/displayController.js";
import {
  verifyAppleWeb,
  overview,
  milesByDay,
  users,
  userDetail,
  userFriends,
  userPosts,
  engagement,
  signupsByDay,
  leaderboards,
  workoutTypes,
  storage,
  postsSummary,
  postsByDay,
  postsList,
  referrals,
  errors,
  cronStatus,
  errorSummary,
  errorsByUser,
  errorTimeseries,
  postForensics,
  restorePost,
  competitions,
  streakTokens,
  featureAdoption,
  community,
  referralGraph,
  friendNetwork,
  userLocations,
  retention,
  activityRhythms,
  pulse,
  drilldown,
  trends,
  activation,
  atRisk,
  referralAlias,
  diagnostics,
} from "../controllers/adminController.js";

// Public: Sign in with Apple (web) exchange -> admin access token.
// Mounted BEFORE authenticateToken in server.ts.
export const adminAuthRouter = Router();
adminAuthRouter.post("/apple", signInLimiter, verifyAppleWeb);

// Protected: mounted AFTER authenticateToken + requireAdmin in server.ts.
const adminRouter = Router();
adminRouter.get("/overview", overview);

// Desk display keys (the LED counter). Plaintext key returned once on create.
adminRouter.get("/display-keys", adminListDisplayKeys);
adminRouter.post("/display-keys", adminCreateDisplayKey);
adminRouter.post("/display-keys/:id/revoke", adminRevokeDisplayKey);
adminRouter.get("/display-messages", adminListDisplayMessages);
adminRouter.post("/display-messages", adminSendDisplayMessage);
// The desk remote: every box (display key), one at a time.
adminRouter.get("/desk/boxes", adminDeskBoxes);
adminRouter.get("/desk/box/:id", adminDeskBox);
adminRouter.post("/desk/box/:id/settings", adminDeskBoxSettings);
adminRouter.post("/desk/box/:id/show", adminDeskBoxTap("show"));
adminRouter.post("/desk/box/:id/wake", adminDeskBoxTap("wake"));
adminRouter.post("/desk/box/:id/message", adminDeskBoxMessage);
adminRouter.get("/miles-by-day", milesByDay);
adminRouter.get("/engagement", engagement);
adminRouter.get("/signups-by-day", signupsByDay);
adminRouter.get("/leaderboards", leaderboards);
adminRouter.get("/workout-types", workoutTypes);

// Users: paginated + searchable directory, and per-user deep detail.
adminRouter.get("/users", users);
adminRouter.get("/users/:userId", userDetail);
// The social half of a profile: who they're friends with (each openable in
// turn) and what they've posted — loaded on demand by the modal's tabs.
adminRouter.get("/users/:userId/friends", userFriends);
adminRouter.get("/users/:userId/posts", userPosts);

// Storage + post/photo analytics.
adminRouter.get("/storage", storage);
// Static segments are registered before the ":userId" param route so
// /posts/summary and /posts/by-day aren't captured as a user id.
adminRouter.get("/posts", postsList);
adminRouter.get("/posts/summary", postsSummary);
adminRouter.get("/posts/by-day", postsByDay);

adminRouter.get("/referrals", referrals);
// Who actually referred whom, resolved from the free-text "a friend" answer.
adminRouter.get("/referral-graph", referralGraph);
// The Network tab: the whole friend graph with its groups, and a coarse
// grid of where people walk (from GPS routes — there is no location column).
adminRouter.get("/network", friendNetwork);
adminRouter.get("/network/locations", userLocations);

// Feature-usage analytics: is each feature being used, by how many people,
// and how often. All bounded aggregates, cached in the service.
adminRouter.get("/competitions", competitions);
adminRouter.get("/streak-tokens", streakTokens);
adminRouter.get("/feature-adoption", featureAdoption);
adminRouter.get("/community", community);
adminRouter.get("/retention", retention);
adminRouter.get("/activity-rhythms", activityRhythms);
adminRouter.get("/pulse", pulse);
adminRouter.get("/trends", trends);
adminRouter.get("/activation", activation);
adminRouter.get("/at-risk", atRisk);
// The one write here: resolve a typed referral name to a real account.
adminRouter.post("/referral-alias", referralAlias);
// The rows behind any one number on the dashboard — see DRILLDOWN_KINDS.
adminRouter.get("/drilldown", drilldown);

adminRouter.get("/errors", errors);
adminRouter.get("/errors/summary", errorSummary);
adminRouter.get("/errors/by-user", errorsByUser);
adminRouter.get("/errors/timeseries", errorTimeseries);
// Scheduled-job health: last run, duration and error per job since boot.
adminRouter.get("/cron", cronStatus);
// MetricKit crashes/hangs from the iOS app: per-version counts and top
// signatures. One signature's rows open through /drilldown
// (kind=diagnostic_signature).
adminRouter.get("/diagnostics", diagnostics);
// Support tooling: post rows incl. soft-deleted + on-disk file checks, and
// soft-delete undo — for "my photo disappeared" investigations.
adminRouter.get("/posts/:userId/forensics", postForensics);
adminRouter.post("/posts/:postId/restore", restorePost);

export default adminRouter;
