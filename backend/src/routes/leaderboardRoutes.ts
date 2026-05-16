import { Router } from "express";
import { getLeaderboardHandler } from "../controllers/leaderboardController.js";

const router = Router();

router.get("/", getLeaderboardHandler);

export default router;
