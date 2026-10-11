/**
 * MCP database connector — configuration.
 *
 * The connector is OFF unless MCP_ALLOWED_USERS is set. That variable is the
 * whole access list, as `<users.user_id>:<Apple sub>` pairs, and it lives in
 * the host's env, NOT the database, on purpose: a connector session can edit
 * rows, including `users.role` and `users.apple_sub`. If either the list or the
 * Apple-ID-to-account mapping lived in the database, one UPDATE could let a
 * stranger's Apple ID sign in as Dave.
 */

export const SCOPE_READ = "db:read";
export const SCOPE_WRITE = "db:write";
export const SUPPORTED_SCOPES = [SCOPE_READ, SCOPE_WRITE];

/** The one pre-registered client: claude.ai's custom connector (see oauth.ts). */
export const CLAUDE_AI_CLIENT_ID = "mad-claude-ai";

export interface McpConfig {
  /** OAuth issuer and public origin, e.g. https://mad.mindgoblin.tech/ */
  issuerUrl: URL;
  /** The MCP endpoint; tokens are bound to exactly this resource. */
  resourceUrl: URL;
  /** The sign-in page on the website (Sign in with Apple, same as /admin). */
  signInPageUrl: URL;
  /** Apple Services ID the admin dashboard already uses. */
  appleClientId: string;
  /** users.user_id → the Apple `sub` that may sign in as that user. */
  allowedUsers: ReadonlyMap<string, string>;
  /** Enables the claude.ai client; unset = Claude Code (loopback) only. */
  claudeAiClientSecret: string | null;
  readDatabaseUrl: string;
  writeDatabaseUrl: string;
}

export type McpConfigResult =
  | { enabled: true; config: McpConfig }
  | { enabled: false; reason: string };

// users.user_id is randomUUID() with the dashes stripped; Apple subs look like
// 001234.0123456789abcdef0123456789abcdef.1234.
const USER_ID = /^[A-Za-z0-9_-]{8,64}$/;
const APPLE_SUB = /^[A-Za-z0-9._-]{6,128}$/;

export function loadMcpConfig(env: NodeJS.ProcessEnv = process.env): McpConfigResult {
  const entries = (env.MCP_ALLOWED_USERS ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  if (!entries.length) return { enabled: false, reason: "MCP_ALLOWED_USERS is not set" };
  const allowedUsers = new Map<string, string>();
  for (const entry of entries) {
    const [userId, sub, extra] = entry.split(":");
    if (extra !== undefined || !USER_ID.test(userId ?? "") || !APPLE_SUB.test(sub ?? "")) {
      return { enabled: false, reason: `MCP_ALLOWED_USERS entry is not <user_id>:<apple_sub>: ${entry.slice(0, 12)}…` };
    }
    allowedUsers.set(userId, sub);
  }

  const readDatabaseUrl = env.MCP_DATABASE_URL_RO ?? "";
  const writeDatabaseUrl = env.MCP_DATABASE_URL_RW ?? "";
  if (!readDatabaseUrl || !writeDatabaseUrl) {
    return { enabled: false, reason: "MCP_DATABASE_URL_RO and MCP_DATABASE_URL_RW are both required" };
  }
  // The whole design rests on these being the restricted roles. The app's own
  // connection string here would hand the connector table ownership.
  if (env.DATABASE_URL && (readDatabaseUrl === env.DATABASE_URL || writeDatabaseUrl === env.DATABASE_URL)) {
    return { enabled: false, reason: "MCP_DATABASE_URL_RO/RW must not be the app's DATABASE_URL" };
  }

  const claudeAiClientSecret = env.MCP_CLAUDE_AI_CLIENT_SECRET || null;
  if (claudeAiClientSecret !== null && claudeAiClientSecret.length < 32) {
    return { enabled: false, reason: "MCP_CLAUDE_AI_CLIENT_SECRET must be at least 32 characters" };
  }

  try {
    const issuerUrl = new URL(env.MCP_BASE_URL || "https://mad.mindgoblin.tech");
    return {
      enabled: true,
      config: {
        issuerUrl: new URL(issuerUrl.origin + "/"),
        resourceUrl: new URL("/mcp", issuerUrl.origin),
        signInPageUrl: new URL(env.MCP_SIGNIN_PAGE_URL || "https://mileaday.run/admin/connect"),
        appleClientId: env.APPLE_WEB_CLIENT_ID || "org.robertwiscount.Mile-A-Day.web",
        allowedUsers,
        claudeAiClientSecret,
        readDatabaseUrl,
        writeDatabaseUrl,
      },
    };
  } catch {
    return { enabled: false, reason: "MCP_BASE_URL or MCP_SIGNIN_PAGE_URL is not a valid URL" };
  }
}
