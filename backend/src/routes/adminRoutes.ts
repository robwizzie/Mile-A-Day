import { Router } from "express";
import {
  verifyAppleWeb,
  overview,
  milesByDay,
  users,
  userDetail,
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
  errorSummary,
  errorsByUser,
  errorTimeseries,
  postForensics,
  restorePost,
} from "../controllers/adminController.js";

// Public: Sign in with Apple (web) exchange -> admin access token.
// Mounted BEFORE authenticateToken in server.ts.
export const adminAuthRouter = Router();
adminAuthRouter.post("/apple", verifyAppleWeb);

// Protected: mounted AFTER authenticateToken + requireAdmin in server.ts.
const adminRouter = Router();
adminRouter.get("/overview", overview);
adminRouter.get("/miles-by-day", milesByDay);
adminRouter.get("/engagement", engagement);
adminRouter.get("/signups-by-day", signupsByDay);
adminRouter.get("/leaderboards", leaderboards);
adminRouter.get("/workout-types", workoutTypes);

// Users: paginated + searchable directory, and per-user deep detail.
adminRouter.get("/users", users);
adminRouter.get("/users/:userId", userDetail);

// Storage + post/photo analytics.
adminRouter.get("/storage", storage);
// Static segments are registered before the ":userId" param route so
// /posts/summary and /posts/by-day aren't captured as a user id.
adminRouter.get("/posts", postsList);
adminRouter.get("/posts/summary", postsSummary);
adminRouter.get("/posts/by-day", postsByDay);

adminRouter.get("/referrals", referrals);

adminRouter.get("/errors", errors);
adminRouter.get("/errors/summary", errorSummary);
adminRouter.get("/errors/by-user", errorsByUser);
adminRouter.get("/errors/timeseries", errorTimeseries);
// Support tooling: post rows incl. soft-deleted + on-disk file checks, and
// soft-delete undo — for "my photo disappeared" investigations.
adminRouter.get("/posts/:userId/forensics", postForensics);
adminRouter.post("/posts/:postId/restore", restorePost);

export default adminRouter;
