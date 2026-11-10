import { getPublicCommunityGoal } from "../services/communityGoalService.js";
import { Request, Response } from "express";
import { getPublicStats } from "../services/publicStatsService.js";
import { getPublicPostPreview } from "../services/postService.js";
import {
  addToAndroidWaitlist,
  normalizeWaitlistEmail,
} from "../services/waitlistService.js";
import { getPublicDeskFeed } from "../services/displayService.js";
import { getShowcasePhotos } from "../services/showcaseService.js";
import {
  addDeskInterest,
  cleanInterestName,
  cleanInterestPrice,
  normalizeInterestEmail,
} from "../services/deskInterestService.js";
import { countryOf, recordWebEvent } from "../services/webAnalyticsService.js";
import { clientIp } from "../middleware/rateLimit.js";

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

/** GET /public/desk — the website's live desk twin. Community aggregates only
 *  (the same block a box without a key shows), cached server-side. */
export async function getPublicDeskController(_req: Request, res: Response) {
  try {
    res.setHeader("Cache-Control", "public, max-age=15");
    res.json(await getPublicDeskFeed());
  } catch (error) {
    console.error("Failed to build the public desk feed:", error);
    res.status(500).json({ error: "Failed to load" });
  }
}

/** GET /public/community-goal: totals for the site's goal page. */
export async function getPublicCommunityGoalController(_req: Request, res: Response) {
  try {
    res.setHeader("Cache-Control", "public, max-age=60");
    res.json(await getPublicCommunityGoal());
  } catch (error) {
    console.error("Failed to build the public community goal:", error);
    res.status(500).json({ error: "Failed to load the goal" });
  }
}

/** POST /public/desk-interest {name, email, price?} — "I'd buy one". A filled
 *  honeypot field is quietly accepted and dropped. Same answer for new and
 *  repeat emails, so addresses can't be probed. */
export async function deskInterestController(req: Request, res: Response) {
  if (typeof req.body?.website === "string" && req.body.website.trim()) {
    return res.json({ ok: true });                // a bot filled the hidden field
  }
  const name = cleanInterestName(req.body?.name);
  const email = normalizeInterestEmail(req.body?.email);
  if (!name) return res.status(400).json({ error: "Please add your name" });
  if (!email) return res.status(400).json({ error: "A valid email is required" });
  try {
    await addDeskInterest(name, email, cleanInterestPrice(req.body?.price));
    res.json({ ok: true });
  } catch (error) {
    console.error("Failed to save desk interest:", error);
    res.status(500).json({ error: "Failed to save" });
  }
}

/** GET /public/showcase — example feed photos for onboarding (devices not yet
 *  signed in). An owner-chosen allowlist only; see showcaseService. */
export async function getShowcaseController(_req: Request, res: Response) {
  try {
    res.setHeader("Cache-Control", "public, max-age=600");
    res.json({ photos: await getShowcasePhotos() });
  } catch (error) {
    console.error("Failed to load showcase photos:", error);
    res.json({ photos: [] });
  }
}

/** POST /public/web-events: one page view or click from mileaday.run. Always
 *  204 (the tracker never waits on, retries or shows anything); bots and
 *  malformed events are dropped by recordWebEvent. */
export async function webEventController(req: Request, res: Response) {
  res.status(204).end();
  try {
    await recordWebEvent(req.body ?? {}, {
      ip: clientIp(req),
      userAgent: req.headers["user-agent"],
      country: countryOf(req.headers["cf-ipcountry"]),
    });
  } catch (error) {
    console.error("Failed to record web event:", error);
  }
}
