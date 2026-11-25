/**
 * Coach MCP — the Sign in with Apple leg.
 *
 * The website's /connect/coach page runs Apple's JS popup (the website's
 * Services ID and registered return URL) with this request's nonce, then
 * form-POSTs Apple's id_token to /coach/oauth/apple/callback on the SAME
 * origin (the website proxies it here). Before a code is issued:
 *
 *   1. this browser holds the cookie set when /authorize parked the request
 *      (a sign-in link sent to someone else gets them nothing);
 *   2. Apple signed the id_token for our Services ID, recently, carrying the
 *      nonce minted for THIS request;
 *   3. the Apple `sub` is a Mile A Day account (`users.apple_sub`) and that
 *      account has Mile A Day+ right now.
 */
import express, { Router, type Request, type Response } from "express";
import crypto from "node:crypto";
import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from "jose";
import { rateLimit, ipKeyGenerator } from "express-rate-limit";
import { clientIp, rateLimitsDisabled } from "../middleware/rateLimit.js";
import { logError } from "../services/errorLogService.js";
import { browserCookieName, browserCookieOptions, type CoachOAuthProvider } from "./oauth.js";
import { recordCoachEvent } from "./audit.js";
import type { CoachMcpConfig } from "./config.js";

const APPLE_ISS = "https://appleid.apple.com";
const appleJwks = createRemoteJWKSet(new URL(`${APPLE_ISS}/auth/keys`));

export async function verifyAppleIdToken(
  idToken: string,
  nonce: string,
  audience: string,
  keys: JWTVerifyGetKey = appleJwks,
): Promise<string> {
  const { payload } = await jwtVerify(idToken, keys, { issuer: APPLE_ISS, audience, maxTokenAge: "10m" });
  const hashed = crypto.createHash("sha256").update(nonce).digest("hex");
  if (payload.nonce !== nonce && payload.nonce !== hashed) throw new Error("nonce mismatch");
  if (typeof payload.sub !== "string" || !payload.sub) throw new Error("no sub");
  return payload.sub;
}

function readCookie(req: Request, name: string): string | null {
  for (const part of (req.headers.cookie ?? "").split(";")) {
    const eq = part.indexOf("=");
    if (eq > 0 && part.slice(0, eq).trim() === name) return decodeURIComponent(part.slice(eq + 1).trim());
  }
  return null;
}

const escapeHtml = (s: string) =>
  s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

function page(res: Response, status: number, title: string, body: string) {
  res
    .status(status)
    .set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'")
    .type("html")
    .send(
      `<!doctype html><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">` +
        `<title>${escapeHtml(title)}</title>` +
        `<body style="font-family:system-ui;background:#0a0a0a;color:#eee;display:grid;place-items:center;min-height:90vh;margin:0">` +
        `<div style="max-width:28rem;padding:2rem"><h1 style="font-size:1.4rem">${escapeHtml(title)}</h1>` +
        `<p style="color:#aaa;line-height:1.5">${escapeHtml(body)}</p></div>`,
    );
}

/**
 * Its own bucket, not the app-wide `signInLimiter` (30/15 min): behind the
 * website's proxy the key is a Vercel egress IP shared by every runner
 * connecting through it (see COACH_MCP.md § Rate limits).
 */
const callbackLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 300,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req: Request) => ipKeyGenerator(clientIp(req) ?? "", 56),
  skip: (req: Request) => rateLimitsDisabled() || clientIp(req) === null,
  validate: { trustProxy: false, xForwardedForHeader: false, keyGeneratorIpFallback: false },
  message: { error: "Too many sign-in attempts. Please wait a few minutes and try again." },
});

/** Mounted inside the /coach router, so the path is /coach/oauth/apple/callback. */
export function coachAppleSignInRouter(
  config: CoachMcpConfig,
  provider: CoachOAuthProvider,
  appleKeys?: JWTVerifyGetKey,
): Router {
  const router = Router();

  router.post(
    "/oauth/apple/callback",
    callbackLimiter,
    express.urlencoded({ extended: false, limit: "16kb" }),
    async (req: Request, res: Response) => {
      res.set("Cache-Control", "no-store");
      const requestId = typeof req.body?.request === "string" ? req.body.request : "";
      const idToken = typeof req.body?.id_token === "string" ? req.body.id_token : "";
      if (!requestId || !idToken) {
        return page(res, 400, "Sign-in incomplete", "Start the connection again from Claude.");
      }

      const browserKey = readCookie(req, browserCookieName(requestId));
      const pending = browserKey ? await provider.consumeSignIn(requestId, browserKey) : null;
      res.clearCookie(browserCookieName(requestId), browserCookieOptions);
      if (!pending) {
        return page(
          res,
          400,
          "Sign-in expired",
          "This sign-in has expired, was already used, or was started in a different browser. Start the connection again from Claude.",
        );
      }

      let appleSub: string;
      try {
        appleSub = await verifyAppleIdToken(idToken, pending.nonce, config.appleClientId, appleKeys);
      } catch (err) {
        const reason = err instanceof Error ? err.message : String(err);
        logError("auth", "Coach MCP Apple sign-in rejected", { context: { reason } });
        await recordCoachEvent("sign_in_denied", null, null, `Apple id_token rejected: ${reason}`);
        return page(res, 401, "Sign-in failed", "Apple's response could not be verified. Start the connection again from Claude.");
      }

      const userId = await provider.userIdForAppleSub(appleSub);
      if (!userId) {
        await recordCoachEvent("sign_in_denied", null, null, `no Mile A Day account for Apple sub ${appleSub.slice(0, 12)}…`);
        return page(
          res,
          403,
          "No Mile A Day account",
          "This Apple ID isn't signed up for Mile A Day. Sign in with the Apple ID you use in the app.",
        );
      }
      if (!(await provider.isUserAllowed(userId))) {
        await recordCoachEvent("sign_in_denied", userId, null, "Mile A Day+ not active");
        return page(
          res,
          403,
          "Mile A Day+ required",
          "Connecting Claude to your run plan is part of Mile A Day+. Upgrade in the app, then start the connection again from Claude.",
        );
      }

      await recordCoachEvent("sign_in", userId, null, `signed in for client ${pending.client_id}`);
      return res.redirect(303, await provider.issueCode(pending, userId));
    },
  );

  return router;
}
