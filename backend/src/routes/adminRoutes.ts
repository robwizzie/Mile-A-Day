import { Router } from "express";
import {
  verifyAppleWeb,
  overview,
  milesByDay,
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
adminRouter.get("/errors", errors);
adminRouter.get("/errors/summary", errorSummary);
adminRouter.get("/errors/by-user", errorsByUser);
adminRouter.get("/errors/timeseries", errorTimeseries);
// Support tooling: post rows incl. soft-deleted + on-disk file checks, and
// soft-delete undo — for "my photo disappeared" investigations.
adminRouter.get("/posts/:userId/forensics", postForensics);
adminRouter.post("/posts/:postId/restore", restorePost);

export default adminRouter;
