/**
 * MCP database connector: lets Claude (Claude Code, claude.ai, the apps) read
 * and edit the production database for the people in MCP_ALLOWED_USERS,
 * from anywhere, without a database URL on anyone's machine.
 *
 *   POST /mcp                         the MCP endpoint (bearer token)
 *   /authorize /token /register /revoke, /.well-known/*   OAuth (MCP SDK handlers)
 *   POST /oauth/apple/callback        sign-in hand-back from mileaday.run/admin/connect
 *
 * Off (nothing mounted) unless MCP_ALLOWED_USERS is set (config.ts).
 */
import express, { type Express, type NextFunction, type Request, type Response } from "express";
import { ipKeyGenerator } from "express-rate-limit";
import { z } from "zod";
import type { JWTVerifyGetKey } from "jose";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { mcpAuthRouter, getOAuthProtectedResourceMetadataUrl } from "@modelcontextprotocol/sdk/server/auth/router.js";
import { requireBearerAuth } from "@modelcontextprotocol/sdk/server/auth/middleware/bearerAuth.js";
import type { AuthInfo } from "@modelcontextprotocol/sdk/server/auth/types.js";
import { clientIp, rateLimitsDisabled } from "../middleware/rateLimit.js";
import { loadMcpConfig, SCOPE_READ, SCOPE_WRITE, SUPPORTED_SCOPES, type McpConfigResult } from "./config.js";
import { McpOAuthProvider } from "./oauth.js";
import { appleSignInRouter } from "./appleSignIn.js";
import {
  checkRoleBoundary,
  configureDatabase,
  describeChanges,
  errorText,
  MAX_ROWS,
  recentAudit,
  renderResult,
  runRead,
  runWrite,
  type Caller,
} from "./dbTools.js";

type Reply = { content: { type: "text"; text: string }[]; isError?: boolean };
const text = (t: string, isError = false): Reply => ({ content: [{ type: "text", text: t }], ...(isError ? { isError } : {}) });

function buildServer(auth: AuthInfo): McpServer {
  const caller: Caller = { userId: String(auth.extra?.userId), grantId: String(auth.extra?.grantId) };
  const can = (scope: string) => auth.scopes.includes(scope);
  const server = new McpServer(
    { name: "mile-a-day-db", version: "1.0.0" },
    {
      instructions:
        "Direct access to the Mile A Day PRODUCTION Postgres database (live users). " +
        "Use `query` freely to read. Change data only with `execute`: dry-run first, show the user " +
        "the statement and the row count, and commit only after they confirm.",
    },
  );

  server.registerTool(
    "query",
    {
      title: "Read the database",
      description:
        "Run ONE read-only SQL statement (SELECT, WITH, EXPLAIN, SHOW, VALUES, TABLE) against production. " +
        "Runs as a role that cannot write, inside a READ ONLY transaction. " +
        `Returns at most ${MAX_ROWS} rows as {columns, rows}. The mcp_* tables read as empty here by design.`,
      inputSchema: { sql: z.string().min(1).max(100_000).describe("Exactly one SQL statement.") },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ sql }) => {
      if (!can(SCOPE_READ)) return text(`This sign-in lacks the ${SCOPE_READ} scope.`, true);
      try {
        return text(renderResult(await runRead(sql, caller)));
      } catch (err) {
        return text(`Query failed: ${errorText(err)}`, true);
      }
    },
  );

  server.registerTool(
    "execute",
    {
      title: "Change the database",
      description:
        "Run ONE INSERT, UPDATE, DELETE or MERGE (a WITH may wrap them) against production. By default " +
        "it is a DRY RUN: the statement runs inside a transaction that is rolled back, and you get exactly " +
        "what it would change in EVERY table, as counted by Postgres (cascades, triggers and CTEs " +
        "included), plus any RETURNING rows, plus a confirm_token. To save it, call again with the SAME " +
        "sql, commit=true and that confirm_token — after showing the user the changes and getting their " +
        "OK. If the statement or what it changes differs in any way from the dry run, everything is " +
        "rolled back. Tokens last 10 minutes. DROP, ALTER, TRUNCATE, CREATE, DO, COPY and setval() are " +
        "refused.",
      inputSchema: {
        sql: z.string().min(1).max(100_000).describe("Exactly one INSERT, UPDATE, DELETE or MERGE statement."),
        commit: z.boolean().default(false).describe("false = dry run (rolled back). true = save."),
        confirm_token: z
          .string()
          .max(100)
          .optional()
          .describe("Required when commit=true: the confirm_token the dry run of this exact sql returned."),
      },
      annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false },
    },
    async ({ sql, commit, confirm_token }) => {
      if (!can(SCOPE_WRITE)) return text(`This sign-in lacks the ${SCOPE_WRITE} scope.`, true);
      try {
        const out = await runWrite(sql, { commit: commit === true, confirmToken: confirm_token ?? null }, caller);
        const what = describeChanges(out.changes);
        const banner = out.committed
          ? `COMMITTED — ${out.changed} row(s) changed (${what}).`
          : out.confirmToken
            ? `DRY RUN — rolled back, nothing saved. This statement would change ${out.changed} row(s) (${what}). ` +
              `To save it, after the user confirms: same sql, commit=true, confirm_token="${out.confirmToken}".`
            : "DRY RUN — rolled back. This statement changes no rows, so there is nothing to commit.";
        const returned = out.columns.length ? `\nReturned: ${renderResult(out)}` : "";
        return text(banner + returned);
      } catch (err) {
        return text(`Statement failed: ${errorText(err)}`, true);
      }
    },
  );

  server.registerTool(
    "audit_log",
    {
      title: "Connector activity",
      description:
        "Recent connector activity, newest first: every statement (who, tool, rows, per-table changes, " +
        "committed or not) and every sign-in, refused sign-in and token alarm. Times are UTC.",
      inputSchema: {
        limit: z.number().int().min(1).max(100).default(25),
        writes_only: z.boolean().default(false).describe("Only `execute` calls (dry runs and commits)."),
      },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ limit, writes_only }) => {
      if (!can(SCOPE_READ)) return text(`This sign-in lacks the ${SCOPE_READ} scope.`, true);
      return text(JSON.stringify(await recentAudit(limit ?? 25, writes_only === true), null, 1));
    },
  );

  return server;
}

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
  const server = buildServer((req as Request & { auth: AuthInfo }).auth);
  const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined, enableJsonResponse: true });
  res.on("close", () => {
    void transport.close();
    void server.close();
  });
  await server.connect(transport);
  await transport.handleRequest(req, res, req.body);
}

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

export interface MountOptions {
  env?: NodeJS.ProcessEnv;
  /** Test seam only: verify Apple id_tokens against these keys. server.ts never passes it. */
  appleKeys?: JWTVerifyGetKey;
}

/** Mount BEFORE `authenticateToken`. Returns what it did, for the boot log and tests. */
export function mountMcpConnector(app: Express, opts: MountOptions = {}): McpConfigResult {
  const loaded = loadMcpConfig(opts.env);
  if (!loaded.enabled) {
    console.log(`[mcp] connector off: ${loaded.reason}`);
    return loaded;
  }
  const { config } = loaded;
  configureDatabase(config.readDatabaseUrl, config.writeDatabaseUrl);
  const provider = new McpOAuthProvider(config);

  // The SDK's limiters, keyed like every other limiter here (clientIp, never req.ip).
  const rateLimit = {
    keyGenerator: (req: Request) => ipKeyGenerator(clientIp(req) ?? "", 56),
    // Unknown address: skip rather than share one bucket (the repo-wide rule).
    skip: (req: Request) => rateLimitsDisabled() || clientIp(req) === null,
    validate: { trustProxy: false, xForwardedForHeader: false, keyGeneratorIpFallback: false },
  };

  // The SDK only reads a client secret from the form body (client_secret_post).
  // claude.ai doesn't document which method it uses, so accept HTTP Basic too
  // by moving its credentials into the body (RFC 6749 §2.3.1: each part is
  // form-encoded inside the base64).
  app.use(["/token", "/revoke"], express.urlencoded({ extended: false, limit: "16kb" }), basicClientAuth);
  app.use(
    mcpAuthRouter({
      provider,
      issuerUrl: config.issuerUrl,
      resourceServerUrl: config.resourceUrl,
      scopesSupported: SUPPORTED_SCOPES,
      resourceName: "Mile A Day database",
      authorizationOptions: { rateLimit },
      tokenOptions: { rateLimit },
      clientRegistrationOptions: { rateLimit },
      revocationOptions: { rateLimit },
    }),
  );
  // Clients that skip the path-specific metadata URL try the root one next.
  app.get("/.well-known/oauth-protected-resource", (_req, res) => {
    res.json({
      resource: config.resourceUrl.href,
      authorization_servers: [config.issuerUrl.href],
      scopes_supported: SUPPORTED_SCOPES,
      resource_name: "Mile A Day database",
    });
  });
  app.use(appleSignInRouter(config, provider, opts.appleKeys));
  app.all(
    "/mcp",
    requireBearerAuth({
      verifier: provider,
      resourceMetadataUrl: getOAuthProtectedResourceMetadataUrl(config.resourceUrl),
      expectedResource: config.resourceUrl,
    }),
    handleMcp,
  );

  console.log(`[mcp] connector on at ${config.resourceUrl.href} for ${config.allowedUsers.size} user(s)` +
      (config.claudeAiClientSecret ? "; claude.ai client on" : "; Claude Code only"));
  // Say so at boot, not at first use, if a role is stronger than it should be.
  for (const kind of ["read", "write"] as const) {
    checkRoleBoundary(kind)
      .then((problem) => problem && console.error(`[mcp] ${kind} role refused: ${problem}`))
      .catch((err) => console.error(`[mcp] ${kind} role check failed: ${errorText(err)}`));
  }
  return loaded;
}
