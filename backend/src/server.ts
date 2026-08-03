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
import liveTrackingRoutes from "./routes/liveTrackingRoutes.js";
import publicRoutes from "./routes/publicRoutes.js";
import {
  authenticateToken,
  requireAdmin,
  AuthenticatedRequest,
} from "./middleware/auth.js";
import { logError } from "./services/errorLogService.js";
import adminRoutes, { adminAuthRouter } from "./routes/adminRoutes.js";
import { startCompetitionCron } from "./cron/competitionCron.js";
import { startNotificationCron } from "./cron/notificationCron.js";
import { startSilentSyncCron } from "./cron/silentSyncCron.js";
import { startStoriesCron } from "./cron/storiesCron.js";
import { startPendingSendCron } from "./cron/pendingSendCron.js";
import { startWeeklyRecapCron } from "./cron/weeklyRecapCron.js";
import { startH2hChallengeCron } from "./cron/h2hChallengeCron.js";
import { startStreakFeaturesCron } from "./cron/streakFeaturesCron.js";
import { seedExtraBadges } from "./services/badgeService.js";
import { seedExtraChallenges } from "./services/dailyChallengeService.js";
import { PostgresService } from "./services/DbService.js";
import {
  runPendingMigrations,
  getMigrationReport,
} from "./db/runMigrations.js";
import { backfillFeedRoles } from "./db/backfillFeedRoles.js";
import { backfillLongestStreaks } from "./db/backfillLongestStreaks.js";
import {
  getUnifiedFeed,
  getStoriesRail,
  UNIFIED_FEED_SQL,
} from "./services/postService.js";

// Throttle for /status/schema?profile=feed. The probe runs a real EXPLAIN
// ANALYZE (~seconds), so an unthrottled public endpoint would be a cheap
// amplification vector. One run per 20s is plenty for diagnosis.
let lastFeedProfileAt = 0;
import { verifyPostsMediaAccess } from "./services/mediaSigningService.js";
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

// Post photos require a signed url (issued on every post/feed response);
// profile images below stay public. Mounted BEFORE the general static
// handler so unsigned /uploads/posts requests never reach the files.
app.use("/uploads/posts", verifyPostsMediaAccess);
app.use("/uploads", express.static(path.join(process.cwd(), "uploads")));

app.get("/status", (req, res) => {
  res.send("healthy");
});

// Public schema diagnostics: the startup-migration boot report plus live
// probes for the marker objects recent code depends on. Contains only schema
// booleans, migration tags, and counts — no user data. Exists because prod
// has no shell/log access; this is how schema state gets diagnosed.
app.get("/status/schema", async (req, res) => {
  const probe = async (sql: string): Promise<boolean | string> => {
    try {
      const db = PostgresService.getInstance();
      const rows = await db.query<{ ok: boolean }>(sql);
      return rows[0]?.ok === true;
    } catch (e: any) {
      return `error: ${e?.message ?? e}`;
    }
  };
  res.json({
    migration_report: getMigrationReport(),
    probes: {
      posts_is_auto: await probe(
        `SELECT EXISTS (SELECT 1 FROM information_schema.columns
					WHERE table_name = 'posts' AND column_name = 'is_auto') AS ok`,
      ),
      workout_routes_table: await probe(
        `SELECT EXISTS (SELECT 1 FROM information_schema.tables
					WHERE table_name = 'workout_routes') AS ok`,
      ),
      share_route_maps: await probe(
        `SELECT EXISTS (SELECT 1 FROM information_schema.columns
					WHERE table_name = 'notification_settings' AND column_name = 'share_route_maps') AS ok`,
      ),
      error_log_table: await probe(
        `SELECT EXISTS (SELECT 1 FROM information_schema.tables
					WHERE table_name = 'error_log') AS ok`,
      ),
      journal_rows: await probe(
        `SELECT EXISTS (SELECT 1 FROM "drizzle"."__drizzle_migrations") AS ok`,
      ),
    },
    // Execute the REAL feed queries as the most recently active user and
    // report only row counts (or the SQL error text) — proves end-to-end
    // whether the feed works in production without exposing any content.
    feed_probe: await (async () => {
      try {
        const db = PostgresService.getInstance();
        const rows = await db.query<{ user_id: string }>(
          `SELECT user_id FROM workouts WHERE deleted_at IS NULL
					ORDER BY device_end_date DESC LIMIT 1`,
        );
        const uid = rows[0]?.user_id;
        if (!uid) return "no workouts in db";
        const [feed, rail] = await Promise.all([
          getUnifiedFeed(uid, 5, null),
          getStoriesRail(uid),
        ]);
        return { unified_feed_rows: feed.length, story_groups: rail.length };
      } catch (e: any) {
        return `error: ${e?.message ?? e}`;
      }
    })(),
    // Opt-in deep profile: /status/schema?profile=feed
    //
    // Diagnostic for "why is the feed slow". Reports TIMINGS, ROW COUNTS and
    // plan node types only — never post content, captions or media — matching
    // the row-counts-only contract feed_probe already follows above. Absent
    // from the default response, so routine health checks stay cheap.
    //
    // Remove once the feed is fast; this is not meant to live here forever.
    feed_profile:
      req.query.profile === "feed"
        ? await (async () => {
            const sinceLast = Date.now() - lastFeedProfileAt;
            if (sinceLast < 20_000) {
              return `throttled — retry in ${Math.ceil((20_000 - sinceLast) / 1000)}s`;
            }
            lastFeedProfileAt = Date.now();
            try {
              const db = PostgresService.getInstance();
              const who = await db.query<{ user_id: string }>(
                `SELECT user_id FROM workouts WHERE deleted_at IS NULL
									ORDER BY device_end_date DESC LIMIT 1`,
              );
              const uid = who[0]?.user_id;
              if (!uid) return "no workouts in db";

              const t0 = Date.now();
              const rows = await getUnifiedFeed(uid, 20, null);
              const fullMs = Date.now() - t0;

              // EXPLAIN the byte-identical SQL getUnifiedFeed just ran.
              const explained = await db.query<any>(
                `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ${UNIFIED_FEED_SQL}`,
                [uid, null, 20],
              );
              const root = explained[0]?.["QUERY PLAN"]?.[0];

              // Flatten the tree so the hot node is obvious at a glance.
              const nodes: any[] = [];
              const walk = (n: any) => {
                if (!n) return;
                const loops = n["Actual Loops"] ?? 1;
                nodes.push({
                  node: n["Node Type"],
                  on:
                    n["Relation Name"] ??
                    n["Index Name"] ??
                    n["CTE Name"] ??
                    undefined,
                  // Names the correlated subquery when the hot node is one.
                  subplan: n["Subplan Name"] ?? undefined,
                  rows: n["Actual Rows"],
                  loops,
                  // A node that reads a lot and discards a lot is the tell for
                  // a scan running per-row that should have been an index hit.
                  discarded: n["Rows Removed by Filter"] ?? undefined,
                  ms: Math.round((n["Actual Total Time"] ?? 0) * loops),
                });
                for (const c of n["Plans"] ?? []) walk(c);
              };
              // FORMAT JSON wraps the tree: root is
              // { Plan: {...}, "Planning Time": n, "Execution Time": n }
              // so the node tree hangs off root.Plan, not root itself.
              walk(root?.["Plan"]);
              nodes.sort((a, b) => b.ms - a.ms);

              const scale = await db.query<any>(
                `SELECT
									(SELECT count(*)::int FROM friendships
										WHERE user_id = $1 AND status = 'accepted') AS friends,
									(SELECT count(*)::int FROM user_blocks
										WHERE blocker_id = $1 OR blocked_id = $1) AS blocks,
									(SELECT count(*)::int FROM workouts w
										WHERE w.deleted_at IS NULL AND w.exclusion_reason IS NULL
											AND w.feed_role IN ('daily_mile','extra')
											AND w.user_id IN (
												SELECT friend_id FROM friendships
													WHERE user_id = $1 AND status = 'accepted'
												UNION SELECT $1)) AS workout_candidates,
									(SELECT count(*)::int FROM posts
										WHERE deleted_at IS NULL AND share_to_feed) AS posts_shared`,
                [uid],
              );

              return {
                rows_returned: rows.length,
                full_query_ms: fullMs,
                planning_ms: Math.round(root?.["Planning Time"] ?? 0),
                execution_ms: Math.round(root?.["Execution Time"] ?? 0),
                scale: scale[0],
                // Inclusive time, so parents contain their children — read the
                // deepest expensive node, not just the top one.
                hottest_nodes: nodes.slice(0, 12),
              };
            } catch (e: any) {
              return `error: ${e?.message ?? e}`;
            }
          })()
        : undefined,
  });
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
// Admin login (Apple-web verify) is public — it's how the dashboard gets a token.
app.use("/admin/auth", adminAuthRouter);

app.use(authenticateToken);
// Admin dashboard data — authenticated AND role=admin.
app.use("/admin", requireAdmin, adminRoutes);
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
app.use("/live", liveTrackingRoutes);

app.use((err: Error, req: Request, res: Response, _next: NextFunction) => {
  console.error("Error:", err.message);
  logError("api", err.message || "Unhandled request error", {
    userId: (req as AuthenticatedRequest).userId ?? null,
    context: {
      method: req.method,
      path: req.originalUrl,
      stack: err.stack?.slice(0, 1000),
    },
  });

  // Generic body only: raw err.message can carry SQL fragments or file paths.
  // The full message + stack already went to error_log above (admin dashboard).
  // `message` field kept for response-shape compatibility with shipped clients.
  res.status(500).json({
    error: "Internal Server Error",
    message: "Something went wrong. Please try again.",
  });
});

const server = http.createServer(app);
// Apply any pending schema migrations BEFORE accepting traffic. Deploys are
// git-driven with no shell access to run `npm run db:migrate` by hand, so the
// server owns its own migrations. Failure is logged (and error-monitored),
// not fatal — endpoints that don't touch new columns keep serving.
runPendingMigrations()
  .then((ok) => {
    if (!ok) {
      logError(
        "api",
        "Startup migrations failed — schema may be behind the code",
        {
          userId: null,
          context: { source: "runPendingMigrations" },
        },
      );
    }
  })
  .finally(() => {
    server.listen(PORT, "0.0.0.0", () => {
      console.log(`Server running on port ${PORT}`);
      startCrons();
      // Deliberately after listen() and deliberately not awaited: classifying
      // the workouts back catalogue into feed_role is too big to sit in a
      // migration (see backfillFeedRoles for why) and must not delay readiness.
      // Rows it hasn't reached yet read 'extra', i.e. the pre-feature feed.
      void backfillFeedRoles();
      // Same contract: post-listen, not awaited, resumable. Fills
      // users.longest_streak from workout history; rows it hasn't reached
      // read 0, which every API surface degrades to max(0, current streak).
      void backfillLongestStreaks();
    });
  });

function startCrons() {
  startCompetitionCron();
  startNotificationCron();
  startSilentSyncCron();
  startStoriesCron();
  startPendingSendCron();
  startWeeklyRecapCron();
  startH2hChallengeCron();
  startStreakFeaturesCron();
  // Idempotently ensure the v2 social/app-function badges exist in the catalog.
  seedExtraBadges();
  // Idempotently ensure the v2 daily challenges (5K/10K/social) exist.
  seedExtraChallenges();
}
