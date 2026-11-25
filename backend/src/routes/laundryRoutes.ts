import { Router } from "express";
import { laundryLimiter } from "../middleware/rateLimit.js";
import { laundryReport, requireLaundryKey } from "../controllers/laundryController.js";

// Laundry plugs report their power readings here. Mounted BEFORE
// authenticateToken: it takes a plug key, never a user JWT. Rate limited per
// IP before the key is even looked at. No CORS headers on purpose.
const router = Router();

router.post("/report", laundryLimiter, requireLaundryKey, laundryReport);

router.use((_req, res) => {
  res.status(404).json({ error: "Not found" });
});

export default router;
