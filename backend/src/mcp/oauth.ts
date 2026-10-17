/**
 * MCP database connector — the OAuth 2.1 authorization server behind
 * `mcpAuthRouter` (the MCP SDK supplies the HTTP handlers, PKCE S256 check,
 * redirect-URI matching and client registration; this file supplies storage
 * and the decisions).
 *
 * Who gets in is decided in exactly one place, `isUserAllowed`: the user id must
 * be in MCP_ALLOWED_USERS (host env) AND still carry users.role = 'admin'.
 * It runs at sign-in, at every token refresh, and on every MCP request. Which
 * Apple ID signs in as which user comes from that env list too, never from
 * users.apple_sub (see config.ts).
 *
 * Every secret this hands out (authorization code, access token, refresh
 * token) is random, opaque, and stored only as its SHA-256. Nothing is signed,
 * so there is no signing key to configure, leak or rotate, and revoking a grant
 * takes effect on the very next request.
 */
import crypto from "node:crypto";
import type { Response } from "express";
import type { OAuthServerProvider, AuthorizationParams } from "@modelcontextprotocol/sdk/server/auth/provider.js";
import type { OAuthRegisteredClientsStore } from "@modelcontextprotocol/sdk/server/auth/clients.js";
import type { AuthInfo } from "@modelcontextprotocol/sdk/server/auth/types.js";
import type {
  OAuthClientInformationFull,
  OAuthTokenRevocationRequest,
  OAuthTokens,
} from "@modelcontextprotocol/sdk/shared/auth.js";
import {
  InvalidClientMetadataError,
  InvalidGrantError,
  InvalidTargetError,
  InvalidTokenError,
} from "@modelcontextprotocol/sdk/server/auth/errors.js";
import { PostgresService } from "../services/DbService.js";
import { logError } from "../services/errorLogService.js";
import { CLAUDE_AI_CLIENT_ID, SUPPORTED_SCOPES, type McpConfig } from "./config.js";
import { recordAuthEvent } from "./dbTools.js";

const db = PostgresService.getInstance();

export const ACCESS_TOKEN_TTL_S = 60 * 60;
/** Sign in again every 30 days, however often the token is refreshed. */
export const GRANT_TTL_S = 30 * 24 * 60 * 60;
export const REQUEST_TTL_S = 10 * 60;
export const CODE_TTL_S = 2 * 60;
/**
 * Refresh tokens rotate, and presenting a used one normally means it was
 * stolen, so the whole grant is revoked. Two Claude sessions sharing one stored
 * login can, though, refresh at the same moment — the loser presents the token
 * the winner just rotated. Inside this window that is treated as the race it is.
 */
export const REFRESH_REUSE_GRACE_S = 60;

export const sha256 = (s: string) => crypto.createHash("sha256").update(s).digest("hex");
export const randomSecret = () => crypto.randomBytes(32).toString("base64url");

/**
 * Only clients whose codes land on the signing-in person's OWN machine may
 * register themselves: loopback, i.e. Claude Code (any port — it binds an
 * ephemeral one, RFC 8252 §7.3). A phished sign-in link then delivers its code
 * to the victim's localhost, where the phisher has nothing listening.
 *
 * claude.ai is deliberately NOT self-registrable: its callback is shared by
 * every claude.ai user, so a link from someone else's connector, signed into by
 * Dave, would hand that someone Dave's access (if claude.ai matches by state
 * alone). claude.ai instead uses one pre-registered client whose secret only
 * the people holding MCP_CLAUDE_AI_CLIENT_SECRET can enter.
 */
const CLAUDE_CALLBACKS = [
  "https://claude.ai/api/mcp/auth_callback",
  "https://claude.com/api/mcp/auth_callback",
];
const LOOPBACK_HOSTS = new Set(["localhost", "127.0.0.1", "[::1]"]);

export function isLoopbackRedirectUri(uri: string): boolean {
  let u: URL;
  try {
    u = new URL(uri);
  } catch {
    return false;
  }
  return u.protocol === "http:" && LOOPBACK_HOSTS.has(u.hostname) && !u.username && !u.password && uri.length <= 200;
}

/** Cookie that ties one sign-in to the browser that started it. */
export const browserCookieName = (requestId: string) => `mcp_signin_${requestId.slice(0, 16)}`;

export interface PendingSignIn {
  id: string;
  client_id: string;
  redirect_uri: string;
  code_challenge: string;
  state: string | null;
  scope: string;
  resource: string;
  nonce: string;
}

interface GrantRow {
  grant_id: string;
  user_id: string;
  client_id: string;
  scope: string;
  resource: string;
  expires_at: string;
}

class ClientsStore implements OAuthRegisteredClientsStore {
  constructor(private config: McpConfig) {}

  async getClient(clientId: string): Promise<OAuthClientInformationFull | undefined> {
    if (clientId === CLAUDE_AI_CLIENT_ID) {
      if (!this.config.claudeAiClientSecret) return undefined;
      return {
        client_id: CLAUDE_AI_CLIENT_ID,
        client_secret: this.config.claudeAiClientSecret,
        client_name: "Claude (claude.ai)",
        redirect_uris: CLAUDE_CALLBACKS,
        token_endpoint_auth_method: "client_secret_post",
        grant_types: ["authorization_code", "refresh_token"],
        response_types: ["code"],
      };
    }
    const rows = await db.query<{ metadata: OAuthClientInformationFull }>(
      `SELECT metadata FROM mcp_oauth_clients WHERE client_id = $1`,
      [clientId],
    );
    return rows[0]?.metadata;
  }

  async registerClient(client: OAuthClientInformationFull) {
    const uris = (client.redirect_uris ?? []).map(String);
    if (!uris.length || uris.length > 5 || !uris.every(isLoopbackRedirectUri)) {
      throw new InvalidClientMetadataError(
        "Only loopback redirect URIs (Claude Code) may register; claude.ai uses the pre-registered client",
      );
    }
    // Only what the flow uses: registration is unauthenticated, so nothing
    // else a stranger sends is kept.
    const stored: OAuthClientInformationFull = {
      client_id: client.client_id,
      client_id_issued_at: client.client_id_issued_at,
      client_name: client.client_name?.slice(0, 100),
      redirect_uris: uris,
      token_endpoint_auth_method: client.token_endpoint_auth_method,
      client_secret: client.client_secret,
      client_secret_expires_at: client.client_secret_expires_at,
      grant_types: ["authorization_code", "refresh_token"],
      response_types: ["code"],
    };
    await db.query(`INSERT INTO mcp_oauth_clients (client_id, metadata) VALUES ($1, $2::jsonb)`, [
      client.client_id,
      JSON.stringify(stored),
    ]);
    return stored;
  }
}

export class McpOAuthProvider implements OAuthServerProvider {
  readonly clientsStore: ClientsStore;

  constructor(private config: McpConfig) {
    this.clientsStore = new ClientsStore(config);
  }

  /** Which user an Apple ID signs in as — from the env list, never users.apple_sub. */
  userIdForAppleSub(appleSub: string): string | null {
    for (const [userId, sub] of this.config.allowedUsers) if (sub === appleSub) return userId;
    return null;
  }

  /** THE access rule. Env allowlist first (no DB), then the live role. */
  async isUserAllowed(userId: string): Promise<boolean> {
    if (!this.config.allowedUsers.has(userId)) return false;
    const rows = await db.query<{ role: string | null }>(`SELECT role FROM users WHERE user_id = $1`, [userId]);
    return rows[0]?.role === "admin";
  }

  private canonicalResource(resource: URL | string | undefined): string {
    const expected = this.config.resourceUrl.href;
    if (resource === undefined) return expected;
    const norm = (s: string) => s.replace(/#.*$/, "").replace(/\/$/, "");
    if (norm(String(resource)) !== norm(expected)) throw new InvalidTargetError("Unknown resource");
    return expected;
  }

  // ---- /authorize: park the request, bind it to this browser, go sign in ----

  async authorize(client: OAuthClientInformationFull, params: AuthorizationParams, res: Response): Promise<void> {
    const resource = this.canonicalResource(params.resource);
    // Scopes are not a boundary between the two people allowed in (both get
    // everything); unknown ones are ignored, none means all.
    const asked = (params.scopes ?? []).filter((s) => SUPPORTED_SCOPES.includes(s));
    const scope = (asked.length ? [...new Set(asked)] : SUPPORTED_SCOPES).join(" ");

    await this.pruneExpired();

    const id = randomSecret();
    const browserKey = randomSecret();
    const nonce = crypto.randomBytes(32).toString("hex");
    await db.query(
      `INSERT INTO mcp_oauth_requests
         (id, browser_key_hash, client_id, redirect_uri, code_challenge, state, scope, resource, nonce, expires_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, now() + make_interval(secs => $10))`,
      [id, sha256(browserKey), client.client_id, params.redirectUri, params.codeChallenge,
        params.state ?? null, scope, resource, nonce, REQUEST_TTL_S],
    );

    // SameSite=None: the sign-in page on the website hands back with a
    // cross-site form POST, and a Lax cookie would not ride along. The cookie
    // only proves "this browser started this sign-in"; it unlocks nothing alone.
    res.cookie(browserCookieName(id), browserKey, {
      httpOnly: true,
      secure: true,
      sameSite: "none",
      path: "/oauth/",
      maxAge: REQUEST_TTL_S * 1000,
    });

    const page = new URL(this.config.signInPageUrl);
    page.searchParams.set("request", id);
    page.searchParams.set("nonce", nonce);
    page.searchParams.set("client", (client.client_name || "Claude").slice(0, 60));
    page.searchParams.set("to", CLAUDE_CALLBACKS.includes(params.redirectUri) ? "claude.ai" : "this computer");
    res.redirect(302, page.href);
  }

  /**
   * Take the parked request — only if this browser holds its cookie, and only
   * once. Consumed whatever happens next, so a sign-in can never be replayed.
   */
  async consumeSignIn(requestId: string, browserKey: string): Promise<PendingSignIn | null> {
    const rows = await db.query<PendingSignIn>(
      `DELETE FROM mcp_oauth_requests
        WHERE id = $1 AND browser_key_hash = $2 AND expires_at > now()
        RETURNING id, client_id, redirect_uri, code_challenge, state, scope, resource, nonce`,
      [requestId, sha256(browserKey)],
    );
    return rows[0] ?? null;
  }

  /** Signed in and allowed: mint the code and say where to send the browser. */
  async issueCode(pending: PendingSignIn, userId: string): Promise<string> {
    const code = randomSecret();
    await db.query(
      `INSERT INTO mcp_oauth_codes
         (code_hash, client_id, user_id, redirect_uri, code_challenge, scope, resource, expires_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, now() + make_interval(secs => $8))`,
      [sha256(code), pending.client_id, userId, pending.redirect_uri, pending.code_challenge,
        pending.scope, pending.resource, CODE_TTL_S],
    );
    const to = new URL(pending.redirect_uri);
    to.searchParams.set("code", code);
    if (pending.state) to.searchParams.set("state", pending.state);
    return to.href;
  }

  // ---- /token ----

  async challengeForAuthorizationCode(client: OAuthClientInformationFull, code: string): Promise<string> {
    const rows = await db.query<{ client_id: string; code_challenge: string }>(
      `SELECT client_id, code_challenge FROM mcp_oauth_codes WHERE code_hash = $1 AND expires_at > now()`,
      [sha256(code)],
    );
    if (!rows[0] || rows[0].client_id !== client.client_id) throw new InvalidGrantError("Invalid authorization code");
    return rows[0].code_challenge;
  }

  async exchangeAuthorizationCode(
    client: OAuthClientInformationFull,
    code: string,
    _codeVerifier?: string,
    redirectUri?: string,
    resource?: URL,
  ): Promise<OAuthTokens> {
    // DELETE … RETURNING: of two concurrent redemptions exactly one gets the row.
    const rows = await db.query<{
      client_id: string; user_id: string; redirect_uri: string; scope: string; resource: string; live: boolean;
    }>(
      `DELETE FROM mcp_oauth_codes WHERE code_hash = $1
        RETURNING client_id, user_id, redirect_uri, scope, resource, expires_at > now() AS live`,
      [sha256(code)],
    );
    const row = rows[0];
    if (!row || !row.live || row.client_id !== client.client_id) throw new InvalidGrantError("Invalid authorization code");
    if (redirectUri !== undefined && redirectUri !== row.redirect_uri) throw new InvalidGrantError("redirect_uri mismatch");
    if (resource !== undefined && this.canonicalResource(resource) !== row.resource) {
      throw new InvalidGrantError("resource mismatch");
    }
    if (!(await this.isUserAllowed(row.user_id))) throw new InvalidGrantError("Not authorized");

    const grants = await db.query<GrantRow>(
      `INSERT INTO mcp_oauth_grants (user_id, client_id, scope, resource, expires_at)
       VALUES ($1, $2, $3, $4, now() + make_interval(secs => $5))
       RETURNING grant_id, user_id, client_id, scope, resource, expires_at`,
      [row.user_id, row.client_id, row.scope, row.resource, GRANT_TTL_S],
    );
    return this.issueTokens(grants[0], row.scope);
  }

  async exchangeRefreshToken(
    client: OAuthClientInformationFull,
    refreshToken: string,
    scopes?: string[],
    resource?: URL,
  ): Promise<OAuthTokens> {
    // FOR UPDATE inside a transaction: a refresh racing another refresh of the
    // same token waits, then reads the winner's committed used_at — so the
    // loser lands in the grace window instead of revoking the sign-in.
    const tx = await db.getClient();
    let row: (GrantRow & { usable: boolean; used: boolean; in_grace: boolean }) | undefined;
    try {
      await tx.query("BEGIN");
      row = (
        await tx.query(
          `SELECT g.grant_id, g.user_id, g.client_id, g.scope, g.resource, g.expires_at,
                  (t.expires_at > now() AND g.expires_at > now() AND g.revoked_at IS NULL) AS usable,
                  t.used_at IS NOT NULL AS used,
                  coalesce(t.used_at > now() - make_interval(secs => $2), false) AS in_grace
             FROM mcp_oauth_tokens t JOIN mcp_oauth_grants g USING (grant_id)
            WHERE t.token_hash = $1 AND t.kind = 'refresh'
              FOR UPDATE OF t`,
          [sha256(refreshToken), REFRESH_REUSE_GRACE_S],
        )
      ).rows[0];
      if (row && !row.used) {
        await tx.query(`UPDATE mcp_oauth_tokens SET used_at = now() WHERE token_hash = $1`, [sha256(refreshToken)]);
      }
      await tx.query("COMMIT");
    } catch (err) {
      await tx.query("ROLLBACK").catch(() => {});
      throw err;
    } finally {
      tx.release();
    }

    if (!row || row.client_id !== client.client_id || !row.usable) throw new InvalidGrantError("Invalid refresh token");
    if (row.used && !row.in_grace) {
      await this.revokeGrant(row.grant_id);
      logError("auth", "MCP refresh token reused — grant revoked", { userId: row.user_id, context: { grant: row.grant_id } });
      await recordAuthEvent("refresh_reuse", row.user_id, `refresh token reused after the grace window; grant ${row.grant_id} revoked`);
      throw new InvalidGrantError("Refresh token already used; sign in again");
    }
    if (resource !== undefined && this.canonicalResource(resource) !== row.resource) {
      throw new InvalidGrantError("resource mismatch");
    }
    if (!(await this.isUserAllowed(row.user_id))) {
      await this.revokeGrant(row.grant_id);
      throw new InvalidGrantError("Not authorized");
    }
    const granted = row.scope.split(" ");
    const scope = scopes?.length ? scopes.filter((s) => granted.includes(s)).join(" ") || row.scope : row.scope;
    return this.issueTokens(row, scope);
  }

  private async issueTokens(grant: GrantRow, scope: string): Promise<OAuthTokens> {
    const access = randomSecret();
    const refresh = randomSecret();
    // Neither may outlive the grant: the 30-day sign-in is a hard ceiling.
    const rows = await db.query<{ access_expires_in: number }>(
      `WITH a AS (
         INSERT INTO mcp_oauth_tokens (token_hash, grant_id, kind, expires_at)
         VALUES ($1, $3, 'access', LEAST(now() + make_interval(secs => $4), $5::timestamptz))
         RETURNING expires_at
       ), r AS (
         INSERT INTO mcp_oauth_tokens (token_hash, grant_id, kind, expires_at)
         VALUES ($2, $3, 'refresh', $5::timestamptz)
       )
       SELECT GREATEST(1, floor(extract(epoch FROM (a.expires_at - now()))))::int AS access_expires_in FROM a`,
      [sha256(access), sha256(refresh), grant.grant_id, ACCESS_TOKEN_TTL_S, grant.expires_at],
    );
    return {
      access_token: access,
      token_type: "Bearer",
      expires_in: rows[0].access_expires_in,
      refresh_token: refresh,
      scope,
    };
  }

  // ---- every MCP request ----

  async verifyAccessToken(token: string): Promise<AuthInfo> {
    const rows = await db.query<{
      grant_id: string; user_id: string; client_id: string; scope: string; resource: string;
      expires_at_s: number; stale: boolean;
    }>(
      `SELECT g.grant_id, g.user_id, g.client_id, g.scope, g.resource,
              extract(epoch FROM t.expires_at)::bigint AS expires_at_s,
              (g.last_used_at IS NULL OR g.last_used_at < now() - interval '5 minutes') AS stale
         FROM mcp_oauth_tokens t JOIN mcp_oauth_grants g USING (grant_id)
        WHERE t.token_hash = $1 AND t.kind = 'access' AND t.expires_at > now()
          AND g.revoked_at IS NULL AND g.expires_at > now()`,
      [sha256(token)],
    );
    const row = rows[0];
    if (!row) throw new InvalidTokenError("Invalid or expired token");
    if (!(await this.isUserAllowed(row.user_id))) throw new InvalidTokenError("Not authorized");
    if (row.stale) {
      void db
        .query(`UPDATE mcp_oauth_grants SET last_used_at = now() WHERE grant_id = $1`, [row.grant_id])
        .catch(() => {});
    }
    return {
      token,
      clientId: row.client_id,
      scopes: row.scope.split(" "),
      expiresAt: Number(row.expires_at_s),
      resource: new URL(row.resource),
      extra: { userId: row.user_id, grantId: row.grant_id },
    };
  }

  // ---- /revoke: either token kills the whole sign-in ----

  async revokeToken(client: OAuthClientInformationFull, request: OAuthTokenRevocationRequest): Promise<void> {
    await db.query(
      `UPDATE mcp_oauth_grants g SET revoked_at = now()
         FROM mcp_oauth_tokens t
        WHERE t.token_hash = $1 AND t.grant_id = g.grant_id
          AND g.client_id = $2 AND g.revoked_at IS NULL`,
      [sha256(request.token), client.client_id],
    );
  }

  async revokeGrant(grantId: string): Promise<void> {
    await db.query(`UPDATE mcp_oauth_grants SET revoked_at = now() WHERE grant_id = $1 AND revoked_at IS NULL`, [grantId]);
  }

  /** Housekeeping on each /authorize — rare, and keeps every table tiny. */
  private async pruneExpired(): Promise<void> {
    await db.query(`DELETE FROM mcp_oauth_requests WHERE expires_at < now()`);
    await db.query(`DELETE FROM mcp_oauth_codes WHERE expires_at < now()`);
    await db.query(`DELETE FROM mcp_oauth_tokens WHERE expires_at < now() - interval '1 day'`);
    await db.query(
      `DELETE FROM mcp_oauth_grants
        WHERE expires_at < now() - interval '1 day' OR revoked_at < now() - interval '1 day'`,
    );
    // Claude registers a fresh client per connection; drop the ones nobody signed in with.
    await db.query(
      `DELETE FROM mcp_oauth_clients c
        WHERE c.created_at < now() - interval '30 days'
          AND NOT EXISTS (SELECT 1 FROM mcp_oauth_grants g WHERE g.client_id = c.client_id)`,
    );
  }
}
