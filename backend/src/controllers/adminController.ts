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
} from "../services/adminService.js";
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

export async function users(_req: Request, res: Response) {
  res.json(await getUsers());
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
