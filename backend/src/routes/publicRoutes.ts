import { Router } from "express";
import {
  getPublicUserCount,
  getPublicUserStreak,
} from "../controllers/usersController.js";
import {
  getPublicStatsController,
  getPublicPostController,
  joinAndroidWaitlistController,
} from "../controllers/publicController.js";

const router = Router();

// Public routes — mounted before authenticateToken. CORS open so the
// marketing site (mileaday.run) can fetch directly from the browser.
// The JSON waitlist POST triggers a browser preflight, so OPTIONS must be
// answered here too (with the allowed methods/headers), not fall to a 404.
router.use((req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  if (req.method === "OPTIONS") {
    return res.sendStatus(204);
  }
  next();
});

router.get("/user-count", getPublicUserCount);
// Alias — same count payload. Exposes NO per-user data.
router.get("/users", getPublicUserCount);
// Streaks are public only for allowlisted usernames (see PUBLIC_STREAK_USERNAMES)
router.get("/streak/:username", getPublicUserStreak);
// Community-wide counters for the site's live stats band. Aggregates only.
router.get("/stats", getPublicStatsController);
// Shared post links (mileaday.run/p/<id>) — author identity only, never the
// photo or caption. The page exists to hand off to the app.
router.get("/posts/:postId", getPublicPostController);
// Android launch waitlist signups from the site footer form.
router.post("/android-waitlist", joinAndroidWaitlistController);

// Unknown /public/* paths should 404 here, not fall through to the auth
// middleware (which confusingly answers "access token required").
router.use((_req, res) => {
  res.status(404).json({ error: "Not found" });
});

export default router;
