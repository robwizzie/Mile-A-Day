/**
 * Coach MCP (Run Plans for Claude) — configuration.
 *
 * Separate from the MCP database connector (src/mcp) in every way: its own
 * env flag, tables (`coach_mcp_*`), router (mounted at /coach), issuer and
 * token audience. The public face is the WEBSITE (https://mileaday.run/mcp):
 * Vercel rewrites the public paths to this backend's /coach/* (see
 * website/next.config.mjs), so every URL in the OAuth metadata is a
 * mileaday.run URL and Claude's discovery never sees the backend host.
 *
 *   public (mileaday.run)                      backend
 *   /mcp                                       /coach/mcp
 *   /authorize /token /register /revoke        /coach/authorize …
 *   /.well-known/oauth-authorization-server    /coach/.well-known/oauth-authorization-server
 *   /.well-known/oauth-protected-resource/mcp  /coach/.well-known/oauth-protected-resource/mcp
 *   /coach/oauth/apple/callback                /coach/oauth/apple/callback
 *
 * Off (nothing mounted) unless COACH_MCP_ENABLED=1, so deploying it is dark.
 */

export const COACH_SCOPE = "coach";
export const COACH_SCOPES = [COACH_SCOPE];

/** The one pre-registered client: claude.ai's custom connector. */
export const COACH_CLAUDE_AI_CLIENT_ID = "mad-coach-claude-ai";

/** Where the coach router is mounted on the backend. */
export const COACH_MOUNT = "/coach";
/** Public (and backend-relative-to-mount) path of the Apple hand-back. */
export const COACH_CALLBACK_PATH = "/coach/oauth/apple/callback";
/** The browser-binding cookie's path: the public callback's directory. */
export const COACH_COOKIE_PATH = "/coach/oauth/";

export interface CoachMcpConfig {
  /** OAuth issuer: the public origin, e.g. https://mileaday.run/ */
  issuerUrl: URL;
  /** The public MCP endpoint; coach tokens are bound to exactly this. */
  resourceUrl: URL;
  /** The website's sign-in page (Sign in with Apple). */
  signInPageUrl: URL;
  /** Apple Services ID the website's Sign in with Apple uses. */
  appleClientId: string;
  /** Enables the claude.ai client; unset = Claude Code (loopback) only. */
  claudeAiClientSecret: string | null;
}

export type CoachMcpConfigResult =
  | { enabled: true; config: CoachMcpConfig }
  | { enabled: false; reason: string };

const truthy = (v: string | undefined) => ["1", "true", "on", "yes"].includes((v ?? "").trim().toLowerCase());

export function loadCoachMcpConfig(env: NodeJS.ProcessEnv = process.env): CoachMcpConfigResult {
  if (!truthy(env.COACH_MCP_ENABLED)) return { enabled: false, reason: "COACH_MCP_ENABLED is not set" };

  const claudeAiClientSecret = env.COACH_MCP_CLAUDE_AI_CLIENT_SECRET || null;
  if (claudeAiClientSecret !== null && claudeAiClientSecret.length < 32) {
    return { enabled: false, reason: "COACH_MCP_CLAUDE_AI_CLIENT_SECRET must be at least 32 characters" };
  }
  if (claudeAiClientSecret !== null && claudeAiClientSecret === env.MCP_CLAUDE_AI_CLIENT_SECRET) {
    return { enabled: false, reason: "COACH_MCP_CLAUDE_AI_CLIENT_SECRET must differ from MCP_CLAUDE_AI_CLIENT_SECRET" };
  }

  try {
    const publicUrl = new URL(env.COACH_MCP_PUBLIC_URL || "https://mileaday.run");
    if (publicUrl.pathname !== "/" || publicUrl.search || publicUrl.hash) {
      return { enabled: false, reason: "COACH_MCP_PUBLIC_URL must be an origin (no path)" };
    }
    // The DB connector's issuer is the backend origin. Sharing it would make
    // the two authorization servers indistinguishable to a client.
    const dbIssuer = new URL(env.MCP_BASE_URL || "https://mad.mindgoblin.tech").origin;
    if (publicUrl.origin === dbIssuer) {
      return { enabled: false, reason: "COACH_MCP_PUBLIC_URL must not be the DB connector's MCP_BASE_URL" };
    }
    return {
      enabled: true,
      config: {
        issuerUrl: new URL(publicUrl.origin + "/"),
        resourceUrl: new URL("/mcp", publicUrl.origin),
        signInPageUrl: new URL(env.COACH_MCP_SIGNIN_PAGE_URL || new URL("/connect/coach", publicUrl.origin).href),
        appleClientId: env.APPLE_WEB_CLIENT_ID || "org.robertwiscount.Mile-A-Day.web",
        claudeAiClientSecret,
      },
    };
  } catch {
    return { enabled: false, reason: "COACH_MCP_PUBLIC_URL or COACH_MCP_SIGNIN_PAGE_URL is not a valid URL" };
  }
}
