/**
 * MCP database connector — the Sign in with Apple leg.
 *
 * Same sign-in as the admin dashboard: the website's /admin/connect page runs
 * Apple's JS popup with the dashboard's Services ID and registered return URL,
 * so no Apple Developer change is needed. The page then form-POSTs Apple's
 * id_token back here. Three things must all hold before a code is issued:
 *
 *   1. this browser holds the cookie set when /authorize parked the request
 *      (a sign-in link sent to someone else gets them nothing);
 *   2. Apple signed the id_token for our Services ID, recently, and it carries
 *      the nonce minted for THIS request (an id_token from any other sign-in,
 *      including the dashboard's, is useless here);
 *   3. the Apple account is one pinned in MCP_ALLOWED_USERS (env — never looked
 *      up through users.apple_sub, which a connector session could rewrite),
 *      and that user still has role 'admin'.
 */
import express, { Router, type Request, type Response } from "express";
import crypto from "node:crypto";
import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from "jose";
import { signInLimiter } from "../middleware/rateLimit.js";
import { logError } from "../services/errorLogService.js";
import { browserCookieName, type McpOAuthProvider } from "./oauth.js";
import { recordAuthEvent } from "./dbTools.js";
import type { McpConfig } from "./config.js";

const APPLE_ISS = "https://appleid.apple.com";
const appleJwks = createRemoteJWKSet(new URL(`${APPLE_ISS}/auth/keys`));

export async function verifyAppleIdToken(
  idToken: string,
  nonce: string,
  audience: string,
  keys: JWTVerifyGetKey = appleJwks,
): Promise<string> {
  const { payload } = await jwtVerify(idToken, keys, { issuer: APPLE_ISS, audience, maxTokenAge: "10m" });
  // Apple's web flow echoes the nonce as sent; accept its SHA-256 too, which is
  // the native-app convention. Either way it must be THIS request's nonce.
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
    .type("html")
    .send(
      `<!doctype html><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">` +
        `<title>${escapeHtml(title)}</title>` +
        `<body style="font-family:system-ui;background:#0a0a0a;color:#eee;display:grid;place-items:center;min-height:90vh;margin:0">` +
        `<div style="max-width:28rem;padding:2rem"><h1 style="font-size:1.4rem">${escapeHtml(title)}</h1>` +
        `<p style="color:#aaa;line-height:1.5">${escapeHtml(body)}</p></div>`,
    );
}

export function appleSignInRouter(
  config: McpConfig,
  provider: McpOAuthProvider,
  appleKeys?: JWTVerifyGetKey,
): Router {
  const router = Router();

  router.post(
    "/oauth/apple/callback",
    signInLimiter,
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
      res.clearCookie(browserCookieName(requestId), { path: "/oauth/", secure: true, sameSite: "none", httpOnly: true });
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
        logError("auth", "MCP Apple sign-in rejected", { context: { reason } });
        await recordAuthEvent("sign_in_denied", null, `Apple id_token rejected: ${reason}`);
        return page(res, 401, "Sign-in failed", "Apple's response could not be verified. Start the connection again from Claude.");
      }

      const userId = provider.userIdForAppleSub(appleSub);
      if (!userId || !(await provider.isUserAllowed(userId))) {
        logError("auth", "MCP sign-in denied (not on the connector allowlist)", { userId });
        await recordAuthEvent(
          "sign_in_denied",
          userId,
          userId ? "allowlisted Apple ID, but the user is not an admin" : `Apple ID not on the allowlist (sub ${appleSub.slice(0, 12)}…)`,
        );
        return page(res, 403, "Not authorized", "This Apple ID is not allowed to use the Mile A Day database connector.");
      }

      await recordAuthEvent("sign_in", userId, `signed in for client ${pending.client_id}`);
      return res.redirect(303, await provider.issueCode(pending, userId));
    },
  );

  return router;
}
