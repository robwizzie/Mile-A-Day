import { Router } from "express";
import { displayLimiter } from "../middleware/rateLimit.js";
import { displayFeed, requireDisplayKey } from "../controllers/displayController.js";

// Desk display feed. Mounted BEFORE authenticateToken: it takes a display key,
// never a user JWT. Rate limited per IP before the key is even looked at, so
// guessing keys is throttled too. No CORS headers on purpose.
const router = Router();

router.get("/feed", displayLimiter, requireDisplayKey, displayFeed);

router.use((_req, res) => {
  res.status(404).json({ error: "Not found" });
});

export default router;
