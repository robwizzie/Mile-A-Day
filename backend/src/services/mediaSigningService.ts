import crypto from "crypto";
import { Request, Response, NextFunction } from "express";

/**
 * Signed URLs for post photos. /uploads/posts holds user photos that were
 * previously fetchable by anyone who guessed or shared a URL; every outbound
 * media_url/story_photo_url is now stamped with `?e=<exp>&s=<hmac>` and the
 * static mount rejects unsigned or expired requests. Profile images stay
 * public (they back world-readable share pages).
 *
 * Expiries are quantized to a window boundary so the SAME url string is
 * produced for ~3 days at a time — AsyncImage/URLCache on the client caches
 * by exact url, and a per-request expiry would bust the cache on every feed
 * refresh. A url is valid for at least one full window after it stops being
 * minted (3–6 days total), and clients re-fetch feed payloads far more often
 * than that.
 */

const POSTS_MEDIA_PREFIX = "/uploads/posts/";
const WINDOW_SECONDS = 3 * 24 * 60 * 60;

let warnedNoSecret = false;

function signingKey(): Buffer | null {
  // Dedicated secret wins; otherwise derive from the JWT secret so no new
  // deploy configuration is required (media keys stay distinct from JWT keys).
  const dedicated = process.env.MEDIA_SIGNING_SECRET;
  if (dedicated) return Buffer.from(dedicated, "utf8");
  const jwt = process.env.APP_JWT_SECRET;
  if (jwt) {
    return crypto
      .createHmac("sha256", jwt)
      .update("media-url-signing")
      .digest();
  }
  if (!warnedNoSecret) {
    warnedNoSecret = true;
    console.warn(
      "[media] No MEDIA_SIGNING_SECRET or APP_JWT_SECRET set — post media urls are UNSIGNED and /uploads/posts is open.",
    );
  }
  return null;
}

function hmacFor(pathname: string, exp: number, key: Buffer): string {
  return crypto
    .createHmac("sha256", key)
    .update(`${pathname}:${exp}`)
    .digest("hex")
    .slice(0, 32);
}

/** Strip any query string — inbound media_url must be stored as a bare path. */
export function stripMediaQuery(url: string): string {
  const q = url.indexOf("?");
  return q === -1 ? url : url.slice(0, q);
}

/** Sign a /uploads/posts path. Anything else passes through untouched. */
export function signMediaUrl(url: string): string {
  if (typeof url !== "string" || !url.startsWith(POSTS_MEDIA_PREFIX))
    return url;
  const key = signingKey();
  if (!key) return url;
  const pathname = stripMediaQuery(url);
  const nowSec = Math.floor(Date.now() / 1000);
  // Quantized: current window + 2 boundaries out → stable within a window,
  // valid for at least one more full window beyond it.
  const exp = (Math.floor(nowSec / WINDOW_SECONDS) + 2) * WINDOW_SECONDS;
  return `${pathname}?e=${exp}&s=${hmacFor(pathname, exp, key)}`;
}

/**
 * Recursively sign every /uploads/posts string in a response payload —
 * post rows, feed items, story rails, and memories all carry media urls under
 * different keys/nesting, and this keeps the controller boundary to one call.
 */
export function signMediaUrlsDeep<T>(value: T): T {
  if (typeof value === "string") {
    return signMediaUrl(value) as unknown as T;
  }
  if (Array.isArray(value)) {
    return value.map((item) => signMediaUrlsDeep(item)) as unknown as T;
  }
  if (value !== null && typeof value === "object" && !(value instanceof Date)) {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      out[k] = signMediaUrlsDeep(v);
    }
    return out as unknown as T;
  }
  return value;
}

/**
 * Express middleware mounted on /uploads/posts BEFORE the static handler.
 * Rejects requests without a valid, unexpired signature. If no secret is
 * configured the gate stays open (with a logged warning) rather than
 * bricking every photo.
 */
export function verifyPostsMediaAccess(
  req: Request,
  res: Response,
  next: NextFunction,
): void {
  const key = signingKey();
  if (!key) return next();

  const pathname = `${POSTS_MEDIA_PREFIX.replace(/\/$/, "")}${req.path}`;
  const exp = parseInt(String(req.query.e ?? ""), 10);
  const sig = typeof req.query.s === "string" ? req.query.s : "";

  if (!Number.isFinite(exp) || !sig) {
    res.status(403).json({ error: "signed_url_required" });
    return;
  }
  if (exp * 1000 < Date.now()) {
    res.status(403).json({ error: "signed_url_expired" });
    return;
  }
  const expected = hmacFor(pathname, exp, key);
  const a = Buffer.from(sig);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    res.status(403).json({ error: "signed_url_invalid" });
    return;
  }
  next();
}
