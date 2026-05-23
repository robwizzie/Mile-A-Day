import { Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import {
  getLeaderboard,
  clampLimit,
  clampOffset,
  LeaderboardMetric,
  LeaderboardPeriod,
} from "../services/leaderboardService.js";

const VALID_METRICS: ReadonlySet<LeaderboardMetric> = new Set([
  "miles",
  "streak",
]);
const VALID_PERIODS: ReadonlySet<LeaderboardPeriod> = new Set([
  "today",
  "week",
  "month",
  "year",
  "all",
]);

export async function getLeaderboardHandler(
  req: AuthenticatedRequest,
  res: Response,
) {
  const userId = req.userId;
  if (!userId)
    return res.status(401).json({ error: "Authentication required" });

  const metricRaw = String(req.query.metric ?? "miles");
  const periodRaw = String(req.query.period ?? "week");

  if (!VALID_METRICS.has(metricRaw as LeaderboardMetric)) {
    return res.status(400).json({
      error: `Invalid metric. Must be one of: ${[...VALID_METRICS].join(", ")}`,
    });
  }
  if (!VALID_PERIODS.has(periodRaw as LeaderboardPeriod)) {
    return res.status(400).json({
      error: `Invalid period. Must be one of: ${[...VALID_PERIODS].join(", ")}`,
    });
  }

  const metric = metricRaw as LeaderboardMetric;
  const period =
    metricRaw === "streak" ? "all" : (periodRaw as LeaderboardPeriod);
  const limit = clampLimit(Number(req.query.limit));
  const offset = clampOffset(Number(req.query.offset));

  try {
    const page = await getLeaderboard({
      metric,
      period,
      userId,
      limit,
      offset,
    });
    res.json(page);
  } catch (err: any) {
    console.error("Error fetching leaderboard:", err.message);
    res.status(500).json({ error: "Failed to fetch leaderboard" });
  }
}
