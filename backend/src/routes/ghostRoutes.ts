import { Router } from "express";
import { friendGhosts, ghostHistory } from "../controllers/ghostController.js";

const router = Router();

// Self-scoped on req.userId (mounted after authenticateToken in server.ts).
// Read-only: picking someone as your ghost tells them nothing and changes
// nothing on their side — the only thing they ever hear about is being BEATEN.
router.get("/friends", friendGhosts);
// Your own races, wins and losses. Self-scoped on the token.
router.get("/history", ghostHistory);

export default router;
