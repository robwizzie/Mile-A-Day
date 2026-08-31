import { Request, Response } from "express";
import { createRemoteJWKSet, jwtVerify } from "jose";
import { generateAccessToken } from "../services/tokenService.js";
import { logError } from "../services/errorLogService.js";
import {
  getUserByAppleSub,
  getOverview,
  getMilesByDay,
  getErrors,
  getErrorSummary,
  getErrorsByUser,
  getErrorTimeseries,
  getPostForensics,
  restoreDeletedPost,
  getUsers,
  getUserDetail,
  getEngagement,
  getSignupsByDay,
  getLeaderboards,
  getWorkoutTypeBreakdown,
  getStorageStats,
  getPostsSummary,
  getPostsByDay,
  listPosts,
  getReferralStats,
  type PostFilter,
} from "../services/adminService.js";
import {
  getCompetitionStats,
  getStreakTokenStats,
  getFeatureAdoption,
  getCommunityStats,
  getReferralGraph,
  getRetentionCohorts,
  getActivityRhythms,
  getPulse,
  getDrilldown,
  getTrends,
  getActivation,
  getAtRisk,
  DRILLDOWN_KINDS,
  type DrilldownKind,
} from "../services/adminAnalyticsService.js";
import { signMediaUrlsDeep } from "../services/mediaSigningService.js";

const APPLE_ISS = "https://appleid.apple.com";
const appleJwks = createRemoteJWKSet(
  new URL("https://appleid.apple.com/auth/keys"),
);

/**
 * Verify a Sign in with Apple (web) id_token, confirm the resolved user is an
 * admin, and mint a normal app access token the dashboard replays to the
 * protected /admin endpoints. Public route — this is how you get a token.
 *
 * Web SIWA uses the Services ID as the token audience (distinct from the
 * native app's APPLE_CLIENT_ID), so we verify against APPLE_WEB_CLIENT_ID.
 */
export async function verifyAppleWeb(req: Request, res: Response) {
  const idToken = req.body?.id_token as string | undefined;
  if (!idToken) {
    return res.status(400).json({ error: "id_token required" });
  }

  // Default to the registered Services ID (team NS237SS5KD) — the client id
  // is public by design (it travels in every SIWA request), so a code default
  // is safe and removes the host-env dependency. Env var wins when set.
  const audience =
    process.env.APPLE_WEB_CLIENT_ID || "org.robertwiscount.Mile-A-Day.web";

  try {
    const { payload } = await jwtVerify(idToken, appleJwks, {
      issuer: APPLE_ISS,
      audience,
    });

    const sub = payload.sub as string;
    const user = await getUserByAppleSub(sub);

    if (!user || user.role !== "admin") {
      logError("auth", "Admin sign-in denied (not an admin)", {
        userId: user?.user_id ?? null,
        context: { email: (payload.email as string) ?? user?.email ?? null },
      });
      return res.status(403).json({ error: "Not authorized" });
    }

    const accessToken = await generateAccessToken(user.user_id);
    return res.json({ accessToken });
  } catch (err) {
    logError("auth", "Admin Apple-web verify failed", {
      context: { reason: err instanceof Error ? err.message : String(err) },
    });
    return res.status(401).json({ error: "Invalid Apple identity token" });
  }
}

export async function overview(_req: Request, res: Response) {
  res.json(await getOverview());
}

export async function milesByDay(_req: Request, res: Response) {
  res.json(await getMilesByDay());
}

const USER_SORTS = new Set([
  "recent",
  "streak",
  "miles",
  "active",
  "photos",
]);

export async function users(req: Request, res: Response) {
  const search =
    typeof req.query.search === "string" && req.query.search.trim()
      ? req.query.search.trim()
      : null;
  const limit = Math.min(
    Math.max(parseInt(String(req.query.limit ?? "25"), 10) || 25, 1),
    100,
  );
  const offset = Math.max(
    parseInt(String(req.query.offset ?? "0"), 10) || 0,
    0,
  );
  const sortParam = String(req.query.sort ?? "recent");
  const sort = (USER_SORTS.has(sortParam) ? sortParam : "recent") as
    | "recent"
    | "streak"
    | "miles"
    | "active"
    | "photos";
  res.json(await getUsers({ search, limit, offset, sort }));
}

export async function userDetail(req: Request, res: Response) {
  const detail = await getUserDetail(req.params.userId);
  if (!detail) return res.status(404).json({ error: "User not found" });
  res.json(signMediaUrlsDeep(detail));
}

export async function engagement(_req: Request, res: Response) {
  res.json(await getEngagement());
}

export async function signupsByDay(_req: Request, res: Response) {
  res.json(await getSignupsByDay());
}

export async function leaderboards(_req: Request, res: Response) {
  res.json(await getLeaderboards());
}

export async function workoutTypes(_req: Request, res: Response) {
  res.json(await getWorkoutTypeBreakdown());
}

export async function storage(_req: Request, res: Response) {
  res.json(await getStorageStats());
}

export async function postsSummary(_req: Request, res: Response) {
  res.json(await getPostsSummary());
}

export async function postsByDay(_req: Request, res: Response) {
  res.json(await getPostsByDay());
}

const POST_FILTERS = new Set<PostFilter>([
  "all",
  "live",
  "deleted",
  "feed",
  "story",
  "auto",
  "user",
]);

export async function postsList(req: Request, res: Response) {
  const search =
    typeof req.query.search === "string" && req.query.search.trim()
      ? req.query.search.trim()
      : null;
  const filterParam = String(req.query.filter ?? "all") as PostFilter;
  const filter = POST_FILTERS.has(filterParam) ? filterParam : "all";
  const limit = Math.min(
    Math.max(parseInt(String(req.query.limit ?? "24"), 10) || 24, 1),
    100,
  );
  const offset = Math.max(
    parseInt(String(req.query.offset ?? "0"), 10) || 0,
    0,
  );
  const result = await listPosts({ search, filter, limit, offset });
  res.json({ total: result.total, posts: signMediaUrlsDeep(result.posts) });
}

export async function referrals(_req: Request, res: Response) {
  res.json(await getReferralStats());
}

export async function errors(req: Request, res: Response) {
  const category =
    typeof req.query.category === "string" && req.query.category
      ? req.query.category
      : null;
  const limit = Math.min(
    Math.max(parseInt(String(req.query.limit ?? "100"), 10) || 100, 1),
    500,
  );
  const userId =
    typeof req.query.userId === "string" && req.query.userId
      ? req.query.userId
      : null;
  res.json(await getErrors(category, limit, userId));
}

export async function errorSummary(_req: Request, res: Response) {
  res.json(await getErrorSummary());
}

export async function errorsByUser(_req: Request, res: Response) {
  res.json(await getErrorsByUser());
}

export async function errorTimeseries(req: Request, res: Response) {
  const r = req.query.range;
  const range = r === "24h" || r === "30d" ? r : "7d";
  const groupBy = req.query.groupBy === "user" ? "user" : "category";
  res.json(await getErrorTimeseries(range, groupBy));
}

/**
 * GET /admin/posts/:userId/forensics?from=YYYY-MM-DD&to=YYYY-MM-DD
 * Every posts row (INCLUDING soft-deleted) for the user in the window, with
 * whether each media file still exists on disk and signed URLs so the photos
 * are viewable in a browser. Support tooling for "my photo disappeared".
 */
export async function postForensics(req: Request, res: Response) {
  // "me" resolves to the authenticated admin — lets the dashboard query the
  // signed-in user without knowing their id.
  const userId =
    req.params.userId === "me"
      ? ((req as any).userId as string)
      : req.params.userId;
  const from =
    typeof req.query.from === "string" &&
    /^\d{4}-\d{2}-\d{2}$/.test(req.query.from)
      ? req.query.from
      : null;
  const to =
    typeof req.query.to === "string" && /^\d{4}-\d{2}-\d{2}$/.test(req.query.to)
      ? req.query.to
      : null;
  if (!from || !to) {
    return res
      .status(400)
      .json({ error: "from and to (YYYY-MM-DD) are required" });
  }
  try {
    const rows = await getPostForensics(userId, from, to);
    res.json({ posts: signMediaUrlsDeep(rows) });
  } catch (error: any) {
    console.error("Error in post forensics:", error.message);
    res.status(500).json({ error: "Error fetching post forensics" });
  }
}

/**
 * POST /admin/posts/:postId/restore — clear a soft-deleted post's deleted_at.
 * 404 unknown id, 409 already live or the slot is now occupied by a live
 * post. Restoring only brings the photo back if the media file survived the
 * orphan sweep (see media_file_exists in the forensics response).
 */
export async function restorePost(req: Request, res: Response) {
  const postId = req.params.postId;
  // Non-uuid ids would blow up the ::uuid cast as a 500 — 404 them instead.
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      postId,
    )
  ) {
    return res.status(404).json({ error: "Post not found" });
  }
  try {
    const result = await restoreDeletedPost(postId);
    switch (result.status) {
      case "not_found":
        return res.status(404).json({ error: "Post not found" });
      case "already_live":
        return res.status(409).json({ error: "Post is not deleted" });
      case "slot_taken":
        return res.status(409).json({
          error: "A live post now occupies this workout's slot",
          occupied_by: result.by,
        });
      case "restored":
        return res.json({ ok: true });
    }
  } catch (error: any) {
    console.error("Error restoring post:", error.message);
    res.status(500).json({ error: "Error restoring post" });
  }
}

// ─── Feature-usage analytics ────────────────────────────────────────
// Thin pass-throughs: every one of these is a bounded aggregate the service
// already caches, and none of them takes a request parameter.

export async function competitions(_req: Request, res: Response) {
  res.json(await getCompetitionStats());
}

export async function streakTokens(_req: Request, res: Response) {
  res.json(await getStreakTokenStats());
}

export async function featureAdoption(_req: Request, res: Response) {
  res.json(await getFeatureAdoption());
}

export async function community(_req: Request, res: Response) {
  res.json(await getCommunityStats());
}

export async function referralGraph(_req: Request, res: Response) {
  res.json(await getReferralGraph());
}

export async function retention(_req: Request, res: Response) {
  res.json(await getRetentionCohorts());
}

export async function activityRhythms(_req: Request, res: Response) {
  res.json(await getActivityRhythms());
}

export async function pulse(_req: Request, res: Response) {
  res.json(await getPulse());
}

export async function trends(_req: Request, res: Response) {
  res.json(await getTrends());
}

export async function activation(_req: Request, res: Response) {
  res.json(await getActivation());
}

export async function atRisk(_req: Request, res: Response) {
  res.json(await getAtRisk());
}

const DRILLDOWN_KIND_SET = new Set<string>(DRILLDOWN_KINDS);

/**
 * GET /admin/drilldown?kind=<kind>&id=<id>
 * The rows behind one dashboard number. `kind` must be one of the whitelisted
 * set; `id` is free text but every branch binds it as a query parameter or
 * resolves it against a code-controlled table, so it never reaches the SQL.
 * An unknown kind or an id that matches nothing is a 404, not an empty 200 —
 * a drawer that opens on nothing should say so.
 */
export async function drilldown(req: Request, res: Response) {
  const kind = String(req.query.kind ?? "");
  if (!DRILLDOWN_KIND_SET.has(kind)) {
    return res.status(400).json({ error: "Unknown drilldown kind" });
  }
  const id =
    typeof req.query.id === "string" && req.query.id.trim()
      ? req.query.id.trim()
      : null;
  const result = await getDrilldown(kind as DrilldownKind, id);
  if (!result) return res.status(404).json({ error: "Nothing to show" });
  res.json(result);
}
