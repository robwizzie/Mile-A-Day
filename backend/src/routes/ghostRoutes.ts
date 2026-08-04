import { Router } from "express";
import { friendGhosts } from "../controllers/ghostController.js";

const router = Router();

// Self-scoped on req.userId (mounted after authenticateToken in server.ts).
// Read-only: picking someone as your ghost tells them nothing and changes
// nothing on their side — the only thing they ever hear about is being BEATEN.
router.get("/friends", friendGhosts);

export default router;
