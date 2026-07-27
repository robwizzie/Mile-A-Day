import { Request, Response } from "express";
import { getPublicStats } from "../services/publicStatsService.js";
import { getPublicPostPreview } from "../services/postService.js";
import {
  addToAndroidWaitlist,
  normalizeWaitlistEmail,
} from "../services/waitlistService.js";

/** Global community counters for the marketing site. Aggregates only — the
 *  service layer is the gate for what may ever appear in this payload. */
export async function getPublicStatsController(_req: Request, res: Response) {
  try {
    const stats = await getPublicStats();
    res.json(stats);
  } catch (error) {
    console.error("Failed to fetch public stats:", error);
    res.status(500).json({ error: "Failed to fetch stats" });
  }
}

/** Android-launch waitlist signup from the marketing site. Responds the same
 *  for new and already-subscribed emails so addresses can't be enumerated. */
export async function joinAndroidWaitlistController(
  req: Request,
  res: Response,
) {
  const email = normalizeWaitlistEmail(req.body?.email);
  if (!email) {
    return res.status(400).json({ error: "A valid email is required" });
  }

  try {
    await addToAndroidWaitlist(email, "website");
    res.json({ ok: true });
  } catch (error) {
    console.error("Failed to save waitlist signup:", error);
    res.status(500).json({ error: "Failed to save signup" });
  }
}

/**
 * GET /public/posts/:postId — the signpost behind a shared post link.
 *
 * Author identity only (already public via /public/users/:username). The photo
 * and caption are friends-only content and a share link travels anywhere, so
 * the web page names who posted and hands off to the app, which re-authorizes
 * the viewer properly. 404 for a deleted or story-only post.
 */
export async function getPublicPostController(req: Request, res: Response) {
  try {
    const preview = await getPublicPostPreview(req.params.postId);
    if (!preview) return res.status(404).json({ error: "Post not found" });
    res.json(preview);
  } catch (error) {
    // A malformed uuid reaches the ::uuid cast and throws — that's a 404, not
    // a 500: it means "no such post", the same as any other bad link.
    console.warn("Public post lookup failed:", error);
    res.status(404).json({ error: "Post not found" });
  }
}
