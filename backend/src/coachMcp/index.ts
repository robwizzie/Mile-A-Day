/**
 * Coach MCP: lets Claude (Claude Code, claude.ai) read a runner's plan, runs
 * and check-ins and propose plan changes — for any Mile A Day+ member, signed
 * in with their own Apple ID. Public at https://mileaday.run/mcp (the website
 * proxies to /coach/* here; see config.ts for the path table).
 *
 *   POST /coach/mcp                          the MCP endpoint (bearer token)
 *   /coach/{authorize,token,register,revoke} OAuth (MCP SDK handlers)
 *   /coach/.well-known/*                     discovery metadata (public URLs)
 *   POST /coach/oauth/apple/callback         sign-in hand-back from /connect/coach
 *
 * Completely separate from the DB connector (src/mcp): other tables, issuer,
 * resource and token audience. Off unless COACH_MCP_ENABLED=1.
 */
import express, { Router, type Express, type NextFunction, type Request, type Response } from "express";
import { ipKeyGenerator } from "express-rate-limit";
import type { JWTVerifyGetKey } from "jose";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { mcpAuthRouter, getOAuthProtectedResourceMetadataUrl } from "@modelcontextprotocol/sdk/server/auth/router.js";
import { requireBearerAuth } from "@modelcontextprotocol/sdk/server/auth/middleware/bearerAuth.js";
import type { AuthInfo } from "@modelcontextprotocol/sdk/server/auth/types.js";
import { clientIp, rateLimitsDisabled } from "../middleware/rateLimit.js";
import { COACH_MOUNT, COACH_SCOPES, loadCoachMcpConfig, type CoachMcpConfigResult } from "./config.js";
import { CoachOAuthProvider } from "./oauth.js";
import { coachAppleSignInRouter } from "./appleSignIn.js";
import { buildCoachServer } from "./tools.js";

const RESOURCE_NAME = "Mile A Day run coach";

/** Stateless: a fresh server + transport per POST, so nothing leaks between callers. */
async function handleMcp(req: Request, res: Response) {
  if (req.method !== "POST") {
    res.set("Allow", "POST").status(405).json({
      jsonrpc: "2.0",
      error: { code: -32000, message: "Method not allowed" },
      id: null,
    });
    return;
  }
  const server = buildCoachServer((req as Request & { auth: AuthInfo }).auth);
  const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined, enableJsonResponse: true });
  res.on("close", () => {
    void transport.close();
    void server.close();
  });
  await server.connect(transport);
  await transport.handleRequest(req, res, req.body);
}

/** Accept client_secret_basic too, by moving its credentials into the body (see src/mcp/index.ts). */
function basicClientAuth(req: Request, _res: Response, next: NextFunction) {
  const header = req.headers.authorization;
  if (req.method === "POST" && header?.toLowerCase().startsWith("basic ")) {
    const decoded = Buffer.from(header.slice(6).trim(), "base64").toString("utf8");
    const colon = decoded.indexOf(":");
    if (colon > 0) {
      const body = (req.body ?? {}) as Record<string, unknown>;
      try {
        body.client_id ??= decodeURIComponent(decoded.slice(0, colon).replace(/\+/g, " "));
        body.client_secret ??= decodeURIComponent(decoded.slice(colon + 1).replace(/\+/g, " "));
        req.body = body;
      } catch {
        // Malformed encoding: leave the body alone; the SDK will refuse the client.
      }
    }
  }
  next();
}

export interface MountCoachOptions {
  env?: NodeJS.ProcessEnv;
  /** Test seam only: verify Apple id_tokens against these keys. server.ts never passes it. */
  appleKeys?: JWTVerifyGetKey;
}

/** Mount BEFORE `authenticateToken`. Returns what it did, for the boot log and tests. */
export function mountCoachMcp(app: Express, opts: MountCoachOptions = {}): CoachMcpConfigResult {
  const loaded = loadCoachMcpConfig(opts.env);
  if (!loaded.enabled) {
    console.log(`[coach-mcp] off: ${loaded.reason}`);
    return loaded;
  }
  const { config } = loaded;
  const provider = new CoachOAuthProvider(config);

  // Keyed like every other limiter (clientIp, never req.ip). Behind the
  // website's proxy the key is a Vercel egress IP SHARED by everyone
  // connecting through it, so the maxes are well above the SDK defaults
  // (token 50/15 min would 429 a few hundred hourly refreshes). Every secret
  // here is 256-bit random, so the limits are flood control, not brute-force
  // protection. See COACH_MCP.md § Rate limits.
  const FIFTEEN_MIN = 15 * 60 * 1000;
  const rateLimit = {
    keyGenerator: (req: Request) => ipKeyGenerator(clientIp(req) ?? "", 56),
    skip: (req: Request) => rateLimitsDisabled() || clientIp(req) === null,
    validate: { trustProxy: false, xForwardedForHeader: false, keyGeneratorIpFallback: false },
  };

  const router = Router();
  router.use(["/token", "/revoke"], express.urlencoded({ extended: false, limit: "16kb" }), basicClientAuth);
  // The SDK router serves /authorize, /token, /register, /revoke and the two
  // .well-known documents at the root of wherever it is mounted (here
  // /coach), and writes the PUBLIC URLs (issuer = the website origin) into
  // the metadata — the website rewrites those public paths to /coach/*.
  router.use(
    mcpAuthRouter({
      provider,
      issuerUrl: config.issuerUrl,
      resourceServerUrl: config.resourceUrl,
      scopesSupported: COACH_SCOPES,
      resourceName: RESOURCE_NAME,
      authorizationOptions: { rateLimit: { ...rateLimit, windowMs: FIFTEEN_MIN, max: 300 } },
      tokenOptions: { rateLimit: { ...rateLimit, windowMs: FIFTEEN_MIN, max: 1000 } },
      clientRegistrationOptions: { rateLimit: { ...rateLimit, windowMs: 60 * 60 * 1000, max: 200 } },
      revocationOptions: { rateLimit: { ...rateLimit, windowMs: FIFTEEN_MIN, max: 300 } },
    }),
  );
  router.get("/.well-known/oauth-protected-resource", (_req, res) => {
    res.json({
      resource: config.resourceUrl.href,
      authorization_servers: [config.issuerUrl.href],
      scopes_supported: COACH_SCOPES,
      resource_name: RESOURCE_NAME,
    });
  });
  router.use(coachAppleSignInRouter(config, provider, opts.appleKeys));
  router.all(
    "/mcp",
    requireBearerAuth({
      verifier: provider,
      resourceMetadataUrl: getOAuthProtectedResourceMetadataUrl(config.resourceUrl),
      expectedResource: config.resourceUrl,
    }),
    handleMcp,
  );
  app.use(COACH_MOUNT, router);

  console.log(
    `[coach-mcp] on: public ${config.resourceUrl.href} → backend ${COACH_MOUNT}/mcp` +
      (config.claudeAiClientSecret ? "; claude.ai client on" : "; Claude Code only"),
  );
  return loaded;
}
