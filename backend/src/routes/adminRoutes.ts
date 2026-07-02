import { Router } from "express";
import {
  verifyAppleWeb,
  overview,
  milesByDay,
  errors,
  errorSummary,
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

export default adminRouter;
