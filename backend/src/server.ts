import "dotenv/config";
import express, { Request, Response, NextFunction } from "express";
import compression from "compression";
import http from "http";
import fs from "fs";
import path from "path";
import userRoutes from "./routes/usersRoutes.js";
import friendRoutes from "./routes/friendshipsRoutes.js";
import authRoutes from "./routes/authRoutes.js";
import devRoutes from "./routes/devRoutes.js";
import workoutRoutes from "./routes/workoutRoutes.js";
import competitionRoutes from "./routes/competitionRoutes.js";
import deviceRoutes from "./routes/deviceRoutes.js";
import notificationRoutes from "./routes/notificationRoutes.js";
import hypeRoutes from "./routes/hypeRoutes.js";
import postsRoutes from "./routes/postsRoutes.js";
import blocksRoutes from "./routes/blocksRoutes.js";
import badgesRoutes, { publicBadgesRouter } from "./routes/badgesRoutes.js";
import dailyChallengesRoutes from "./routes/dailyChallengesRoutes.js";
import dailyStepsRoutes from "./routes/dailyStepsRoutes.js";
import leaderboardRoutes from "./routes/leaderboardRoutes.js";
import publicRoutes from "./routes/publicRoutes.js";
import { authenticateToken } from "./middleware/auth.js";
import { startCompetitionCron } from "./cron/competitionCron.js";
import { startNotificationCron } from "./cron/notificationCron.js";
import { startSilentSyncCron } from "./cron/silentSyncCron.js";
import { startStoriesCron } from "./cron/storiesCron.js";
import { startPendingSendCron } from "./cron/pendingSendCron.js";
import { seedExtraBadges } from "./services/badgeService.js";
import { seedExtraChallenges } from "./services/dailyChallengeService.js";
import { PostgresService } from "./services/DbService.js";
import { webcrypto } from "node:crypto";

(globalThis as any).crypto ??= webcrypto;

const app = express();
const PORT = parseInt(process.env.PORT ?? "3000");

app.use(compression());
// 2mb (default is 100kb): a workout-sync batch can now carry GPS route traces
// (~3-4KB per workout x 25-workout batches) and must never 413 mid-sync.
app.use(express.json({ limit: "2mb" }));

// Ensure uploads directories exist
const uploadsDir = path.join(process.cwd(), "uploads", "profile-images");
fs.mkdirSync(uploadsDir, { recursive: true });
fs.mkdirSync(path.join(process.cwd(), "uploads", "posts"), { recursive: true });

app.use("/uploads", express.static(path.join(process.cwd(), "uploads")));

app.get("/status", (req, res) => {
  res.send("healthy");
});

app.get("/test-signin.html", (req, res) => {
  res.sendFile(path.join(process.cwd(), "test-signin.html"));
});

// Public endpoint: get profile image URL by username
app.get(
  "/public/profile-image/:username",
  (req, res, next) => {
    res.setHeader("Access-Control-Allow-Origin", "*");
    next();
  },
  async (req, res) => {
    const db = PostgresService.getInstance();
    const results = await db.query(
      "SELECT profile_image_url FROM users WHERE username = $1",
      [req.params.username],
    );
    if (!results.length || !results[0].profile_image_url) {
      return res.status(404).json({ error: "Not found" });
    }
    res.json({ profile_image_url: results[0].profile_image_url });
  },
);

// Public endpoint: minimal profile by username for the marketing site's
// /u/<username> share pages. Intentionally excludes email and any other
// sensitive fields — this is world-readable.
app.get(
  "/public/users/:username",
  (req, res, next) => {
    res.setHeader("Access-Control-Allow-Origin", "*");
    next();
  },
  async (req, res) => {
    const db = PostgresService.getInstance();
    const results = await db.query(
      `SELECT user_id, username, first_name, last_name, bio,
              profile_image_url, current_streak
       FROM users
       WHERE LOWER(username) = LOWER($1)`,
      [req.params.username],
    );
    if (!results.length) {
      return res.status(404).json({ error: "Not found" });
    }
    res.json(results[0]);
  },
);

app.use("/auth", authRoutes);
app.use("/dev", devRoutes);
app.use("/badges", publicBadgesRouter);
app.use("/public", publicRoutes);

app.use(authenticateToken);
app.use("/users", userRoutes);
app.use("/users", badgesRoutes);
app.use("/users", dailyChallengesRoutes);
app.use("/users", dailyStepsRoutes);
app.use("/friends", friendRoutes);
app.use("/workouts", workoutRoutes);
app.use("/competitions", competitionRoutes);
app.use("/devices", deviceRoutes);
app.use("/notifications", notificationRoutes);
app.use("/hype", hypeRoutes);
app.use("/posts", postsRoutes);
app.use("/blocks", blocksRoutes);
app.use("/leaderboard", leaderboardRoutes);

app.use((err: Error, _req: Request, res: Response, _next: NextFunction) => {
  console.error("Error:", err.message);

  res.status(500).json({
    error: "Internal Server Error",
    message: err.message,
  });
});

const server = http.createServer(app);
server.listen(PORT, "0.0.0.0", () => {
  console.log(`Server running on port ${PORT}`);
  startCompetitionCron();
  startNotificationCron();
  startSilentSyncCron();
  startStoriesCron();
  startPendingSendCron();
  // Idempotently ensure the v2 social/app-function badges exist in the catalog.
  seedExtraBadges();
  // Idempotently ensure the v2 daily challenges (5K/10K/social) exist.
  seedExtraChallenges();
});
