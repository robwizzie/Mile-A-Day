// MCP database connector check (src/mcp). The whole sign-in and every guard,
// against a real Postgres, driven by the MCP SDK's own OAuth client — the
// same discovery → registration → PKCE → token path Claude takes.
//
// Only Apple is faked: id_tokens are signed with a local key and verified
// against it through mountMcpConnector's `appleKeys` test seam.
//
// Creates the two connector roles (mad_mcp_ro / mad_mcp_rw) by running the
// production setup file, scripts/mcp-db-roles.sql, and drops them at the end.
// Refuses to run if they already exist in the cluster.
//
// Usage: npm run build && DATABASE_URL=... node scripts/mcp-check.mjs
import assert from "node:assert/strict";
import crypto from "node:crypto";
import http from "node:http";
import { execFileSync } from "node:child_process";
import express from "express";
import pg from "pg";
import { generateKeyPair, exportJWK, SignJWT, createLocalJWKSet } from "jose";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";
import { UnauthorizedError } from "@modelcontextprotocol/sdk/client/auth.js";

// Dozens of sign-ins from one address in a few seconds.
process.env.RATE_LIMITS_DISABLED = "1";

const { mountMcpConnector } = await import("../dist/mcp/index.js");
const { closeMcpPools, configureDatabase, checkRoleBoundary, SafeCursor } = await import("../dist/mcp/dbTools.js");
const { loadMcpConfig } = await import("../dist/mcp/config.js");
const { PostgresService } = await import("../dist/services/DbService.js");

const admin = new pg.Pool({ connectionString: process.env.DATABASE_URL, max: 3 });
const q = async (sql, params) => (await admin.query(sql, params)).rows;

let failures = 0;
async function check(name, fn) {
  try {
    await fn();
    console.log(`  ok   ${name}`);
  } catch (err) {
    failures++;
    console.log(`  FAIL ${name}\n       ${err?.stack?.split("\n").slice(0, 3).join("\n       ") ?? err}`);
  }
}

// ---------------------------------------------------------------------------
// Roles: created by the production setup file itself.
// ---------------------------------------------------------------------------
const RO = "mad_mcp_ro";
const RW = "mad_mcp_rw";
const PW = crypto.randomBytes(12).toString("hex");
const [{ db: DB }] = await q(`SELECT current_database() AS db`);
const preexisting = (await q(`SELECT count(*)::int AS n FROM pg_roles WHERE rolname IN ($1, $2)`, [RO, RW]))[0].n;
if (preexisting) {
  console.log(`mcp-check: ${RO}/${RW} already exist in this cluster; refusing to reset their passwords.`);
  process.exit(1);
}
const dropRoles = async () => {
  for (const role of [RO, RW, "mcp_check_broad"]) {
    await q(`DROP OWNED BY ${role}`).catch(() => {});
    await q(`DROP ROLE IF EXISTS ${role}`).catch((e) => console.log(`  (could not drop ${role}: ${e.message})`));
  }
};
try {
  execFileSync("psql", [process.env.DATABASE_URL, "-q", "-v", `ro_pw=${PW}`, "-v", `rw_pw=${PW}`,
    "-f", new URL("./mcp-db-roles.sql", import.meta.url).pathname], { stdio: ["ignore", "ignore", "inherit"] });
} catch {
  console.log("mcp-check: FAILED — scripts/mcp-db-roles.sql did not run cleanly");
  await dropRoles();
  process.exit(1);
}
const urlAs = (user, password = PW) => {
  const u = new URL(process.env.DATABASE_URL);
  u.username = user;
  u.password = password;
  return u.href;
};

// ---------------------------------------------------------------------------
// People: dave + rob are the two allowed; eve is no one; mal is on the list
// but not an admin.
// ---------------------------------------------------------------------------
const uid = () => crypto.randomBytes(16).toString("hex");
const people = {
  dave: { id: uid(), role: "admin" },
  rob: { id: uid(), role: "admin" },
  eve: { id: uid(), role: "user" },
  mal: { id: uid(), role: "user" },
};
for (const [name, p] of Object.entries(people)) {
  p.sub = `001234.${crypto.randomBytes(16).toString("hex")}.${name}`;
  p.username = `mcp_${name}_${p.id.slice(0, 6)}`;
  await q(
    `INSERT INTO users (user_id, apple_sub, email, username, role) VALUES ($1, $2, $3, $4, $5)`,
    [p.id, p.sub, `${p.id}@example.com`, p.username, p.role],
  );
}
const ourUsers = Object.values(people).map((p) => p.id);
const runStart = (await q(`SELECT now() AS t`))[0].t;

// ---------------------------------------------------------------------------
// Fake Apple.
// ---------------------------------------------------------------------------
const { publicKey, privateKey } = await generateKeyPair("RS256");
const appleKeys = createLocalJWKSet({ keys: [{ ...(await exportJWK(publicKey)), kid: "check", alg: "RS256" }] });
const SERVICES_ID = "org.robertwiscount.Mile-A-Day.web";
function appleIdToken(sub, nonce, o = {}) {
  return new SignJWT({ nonce })
    .setProtectedHeader({ alg: "RS256", kid: "check" })
    .setIssuer(o.iss ?? "https://appleid.apple.com")
    .setAudience(o.aud ?? SERVICES_ID)
    .setSubject(sub)
    .setIssuedAt(o.iat ?? Math.floor(Date.now() / 1000))
    .setExpirationTime(o.exp ?? Math.floor(Date.now() / 1000) + 600)
    .sign(privateKey);
}

// ---------------------------------------------------------------------------
// The server: same order as server.ts (json → connector → everything else).
// ---------------------------------------------------------------------------
const app = express();
app.set("trust proxy", 1);
app.use(express.json({ limit: "2mb" }));
const server = http.createServer(app);
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const BASE = `http://127.0.0.1:${server.address().port}`;
const MCP_URL = new URL(`${BASE}/mcp`);
const CLAUDE_AI_SECRET = crypto.randomBytes(24).toString("hex");
const env = {
  MCP_ALLOWED_USERS: [people.dave, people.rob, people.mal].map((p) => `${p.id}:${p.sub}`).join(", "),
  MCP_DATABASE_URL_RO: urlAs(RO),
  MCP_DATABASE_URL_RW: urlAs(RW),
  MCP_BASE_URL: BASE,
  MCP_CLAUDE_AI_CLIENT_SECRET: CLAUDE_AI_SECRET,
  DATABASE_URL: process.env.DATABASE_URL,
};
const mounted = mountMcpConnector(app, { env, appleKeys });
app.use((_req, res) => res.status(418).json({ error: "fell through to the app" }));

// ---------------------------------------------------------------------------
// Helpers: a browser doing the sign-in, PKCE, a raw token call.
// ---------------------------------------------------------------------------
const pkce = () => {
  const verifier = crypto.randomBytes(32).toString("base64url");
  return { verifier, challenge: crypto.createHash("sha256").update(verifier).digest("base64url") };
};
function authorizeUrl(clientId, redirectUri, challenge, extra = {}, base = BASE) {
  return `${base}/authorize?${new URLSearchParams({
    response_type: "code",
    client_id: clientId,
    redirect_uri: redirectUri,
    code_challenge: challenge,
    code_challenge_method: "S256",
    state: "st-123",
    resource: `${base}/mcp`,
    ...extra,
  })}`;
}

/** GET /authorize like a browser: returns the sign-in page params + the cookie it set. */
async function openAuthorize(url) {
  const res = await fetch(url, { redirect: "manual" });
  assert.equal(res.status, 302, `authorize → ${res.status} ${await res.text().catch(() => "")}`);
  const page = new URL(res.headers.get("location"));
  const setCookies = res.headers.getSetCookie();
  return {
    page,
    request: page.searchParams.get("request"),
    nonce: page.searchParams.get("nonce"),
    setCookies,
    cookie: setCookies.map((c) => c.split(";")[0]).join("; "),
  };
}

/** The website page's form POST back. */
async function postCallback({ request, idToken, cookie }, base = BASE) {
  const headers = { "content-type": "application/x-www-form-urlencoded" };
  if (cookie) headers.cookie = cookie;
  return fetch(`${base}/oauth/apple/callback`, {
    method: "POST",
    redirect: "manual",
    headers,
    body: new URLSearchParams({ request, id_token: idToken }),
  });
}

async function signIn(url, person, base = BASE) {
  const a = await openAuthorize(url);
  const res = await postCallback({ request: a.request, idToken: await appleIdToken(person.sub, a.nonce), cookie: a.cookie }, base);
  return { ...a, res };
}

async function token(body, base = BASE) {
  const res = await fetch(`${base}/token`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(body),
  });
  return { status: res.status, body: await res.json().catch(() => ({})) };
}

async function register(redirect_uris, base = BASE) {
  return fetch(`${base}/register`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ client_name: "reg-test", redirect_uris, token_endpoint_auth_method: "none" }),
  });
}

/** A raw MCP tools/call with a bearer token. */
async function rawCall(accessToken, name, args, base = BASE) {
  const res = await fetch(`${base}/mcp`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      accept: "application/json, text/event-stream",
      authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name, arguments: args } }),
  });
  return { status: res.status, body: await res.json().catch(() => null), www: res.headers.get("www-authenticate") };
}

class MemoryAuthProvider {
  constructor(redirectUrl) {
    this._redirectUrl = redirectUrl;
  }
  get redirectUrl() {
    return this._redirectUrl;
  }
  get clientMetadata() {
    return {
      client_name: "Claude Code (mcp-check)",
      redirect_uris: [this._redirectUrl],
      grant_types: ["authorization_code", "refresh_token"],
      response_types: ["code"],
      token_endpoint_auth_method: "none",
    };
  }
  clientInformation() {
    return this.info;
  }
  saveClientInformation(info) {
    this.info = info;
  }
  tokens() {
    return this._tokens;
  }
  saveTokens(t) {
    this._tokens = t;
  }
  redirectToAuthorization(url) {
    this.authUrl = url;
  }
  saveCodeVerifier(v) {
    this.verifier = v;
  }
  codeVerifier() {
    return this.verifier;
  }
}

const bio = async (who) => (await q(`SELECT bio FROM users WHERE user_id = $1`, [who.id]))[0].bio;
const tokenIn = (text) => /confirm_token="([^"]+)"/.exec(text)?.[1];

try {
  console.log("mcp-check: connector config");
  await check("mounts with the pinned users + both role URLs", () => {
    assert.equal(mounted.enabled, true, mounted.reason);
    assert.equal(mounted.config.allowedUsers.size, 3);
    assert.equal(mounted.config.allowedUsers.get(people.dave.id), people.dave.sub);
  });
  await check("stays off without MCP_ALLOWED_USERS, or with an entry missing its Apple ID", () => {
    assert.equal(loadMcpConfig({ ...env, MCP_ALLOWED_USERS: "" }).enabled, false);
    assert.equal(loadMcpConfig({ ...env, MCP_ALLOWED_USERS: people.dave.id }).enabled, false);
  });
  await check("refuses the app's own DATABASE_URL as a connector role", () => {
    const r = loadMcpConfig({ ...env, MCP_DATABASE_URL_RW: process.env.DATABASE_URL });
    assert.equal(r.enabled, false);
    assert.match(r.reason, /must not be the app's DATABASE_URL/);
  });

  console.log("mcp-check: discovery");
  await check("unauthenticated /mcp → 401 pointing at the resource metadata", async () => {
    const r = await rawCall("nope", "query", { sql: "select 1" });
    assert.equal(r.status, 401);
    assert.match(r.www, new RegExp(`resource_metadata="${BASE}/.well-known/oauth-protected-resource/mcp"`));
  });
  await check("protected-resource metadata (path-specific and root) names /mcp and the issuer", async () => {
    for (const path of ["/.well-known/oauth-protected-resource/mcp", "/.well-known/oauth-protected-resource"]) {
      const m = await (await fetch(BASE + path)).json();
      assert.equal(m.resource, MCP_URL.href, path);
      assert.deepEqual(m.authorization_servers, [`${BASE}/`], path);
    }
  });
  await check("authorization-server metadata: S256 only, registration on", async () => {
    const m = await (await fetch(`${BASE}/.well-known/oauth-authorization-server`)).json();
    assert.equal(m.issuer, `${BASE}/`);
    assert.deepEqual(m.code_challenge_methods_supported, ["S256"]);
    assert.equal(m.registration_endpoint, `${BASE}/register`);
  });

  console.log("mcp-check: client registration");
  await check("only loopback (Claude Code) may self-register — not claude.ai, not anywhere else", async () => {
    for (const uris of [["https://evil.example/cb"], ["http://evil.example/cb"], ["https://claude.ai/api/mcp/auth_callback"],
      ["http://localhost:1/cb", "https://evil.example/cb"], ["http://user:pw@localhost:1/cb"]]) {
      assert.equal((await register(uris)).status, 400, uris.join(","));
    }
  });
  let otherClient;
  await check("loopback can, any port, both hosts; only the needed fields are kept", async () => {
    for (const uris of [["http://localhost:61234/callback"], ["http://127.0.0.1:9/callback"]]) {
      const r = await register(uris);
      assert.equal(r.status, 201, uris.join(","));
      otherClient ??= (await r.json()).client_id;
    }
    const big = await fetch(`${BASE}/register`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ redirect_uris: ["http://localhost:2/cb"], token_endpoint_auth_method: "none",
        client_name: "x".repeat(500), jwks: { keys: [{ junk: "y".repeat(100_000) }] } }),
    });
    const id = (await big.json()).client_id;
    const [{ size }] = await q(`SELECT length(metadata::text) AS size FROM mcp_oauth_clients WHERE client_id = $1`, [id]);
    assert.ok(size < 1000, `${size} bytes stored`);
  });

  console.log("mcp-check: full sign-in with the MCP SDK client (as Claude Code does it)");
  const auth = new MemoryAuthProvider("http://localhost:53682/callback");
  let client;
  await check("connect → 401 → discovery → registration → authorize URL", async () => {
    const t = new StreamableHTTPClientTransport(MCP_URL, { authProvider: auth });
    await assert.rejects(new Client({ name: "mcp-check", version: "1" }).connect(t), UnauthorizedError);
    assert.ok(auth.info?.client_id, "registered");
    assert.ok(auth.authUrl, "got an authorize URL");
    assert.equal(auth.authUrl.searchParams.get("resource"), MCP_URL.href);
  });
  await check("authorize parks the request and sets a browser-binding cookie; sign-in returns a code", async () => {
    const a = await openAuthorize(auth.authUrl);
    assert.equal(a.page.origin + a.page.pathname, "https://mileaday.run/admin/connect");
    assert.match(a.request, /^[A-Za-z0-9_-]{40,}$/);
    assert.match(a.nonce, /^[0-9a-f]{64}$/);
    assert.equal(a.page.searchParams.get("to"), "this computer");
    const c = a.setCookies.join(" | ");
    for (const attr of ["HttpOnly", "Secure", "SameSite=None", "Path=/oauth/"]) assert.ok(c.includes(attr), attr);
    const res = await postCallback({ request: a.request, idToken: await appleIdToken(people.dave.sub, a.nonce), cookie: a.cookie });
    assert.equal(res.status, 303, await res.text());
    const back = new URL(res.headers.get("location"));
    assert.equal(back.origin + back.pathname, "http://localhost:53682/callback");
    auth.code = back.searchParams.get("code");
    assert.ok(auth.code);
    assert.equal(back.searchParams.get("state"), auth.authUrl.searchParams.get("state"));
  });
  await check("finishAuth exchanges the code; reconnect lists the three tools", async () => {
    await new StreamableHTTPClientTransport(MCP_URL, { authProvider: auth }).finishAuth(auth.code);
    assert.ok(auth.tokens()?.access_token && auth.tokens()?.refresh_token);
    assert.ok(auth.tokens().expires_in <= 3600);
    client = new Client({ name: "mcp-check", version: "1" });
    await client.connect(new StreamableHTTPClientTransport(MCP_URL, { authProvider: auth }));
    const names = (await client.listTools()).tools.map((t) => t.name).sort();
    assert.deepEqual(names, ["audit_log", "execute", "query"]);
  });
  await check("the code cannot be redeemed a second time", async () => {
    const r = await token({ grant_type: "authorization_code", code: auth.code, code_verifier: auth.verifier,
      client_id: auth.info.client_id, redirect_uri: auth.redirectUrl });
    assert.equal(r.body.error, "invalid_grant");
  });

  const call = async (name, args) => {
    const r = await client.callTool({ name, arguments: args });
    return { text: r.content[0].text, isError: r.isError === true };
  };
  const dryRun = async (sql) => {
    const r = await call("execute", { sql });
    assert.equal(r.isError, false, r.text);
    return r;
  };

  console.log("mcp-check: query (read role, READ ONLY)");
  await check("reads", async () => {
    const r = await call("query", { sql: `SELECT username FROM users WHERE user_id = '${people.rob.id}'` });
    assert.equal(r.isError, false, r.text);
    assert.match(r.text, /^1 row\(s\)/);
    assert.ok(r.text.includes(people.rob.username));
  });
  await check("cannot write, not even inside a CTE", async () => {
    const r = await call("query", {
      sql: `WITH u AS (UPDATE users SET bio = 'x' WHERE user_id = '${people.rob.id}' RETURNING 1) SELECT * FROM u`,
    });
    assert.equal(r.isError, true);
    assert.match(r.text, /read-only transaction|permission denied/, r.text);
    assert.equal(await bio(people.rob), null);
  });
  await check("only read statements are sent at all (UPDATE, DO, CALL, SET, LOCK, COPY refused up front)", async () => {
    for (const sql of [`UPDATE users SET bio = 'x'`, "DO $$ BEGIN PERFORM pg_sleep(5); END $$", "CALL x()",
      "SET work_mem = '2GB'", "LOCK TABLE users", "COPY (SELECT 1) TO STDOUT",
      "/* a /* nested */ c */ -- x\n copy users TO STDOUT", " ; ;\t(COPY (SELECT 1) TO STDOUT)"]) {
      const r = await call("query", { sql });
      assert.equal(r.isError, true, sql);
      assert.match(r.text, /query only runs SELECT/, sql);
    }
  });
  await check("one statement per call", async () => {
    const r = await call("query", { sql: "SELECT 1; SELECT 2" });
    assert.equal(r.isError, true);
    assert.match(r.text, /multiple commands/);
  });
  await check("a huge result streams: 200 rows shown, not 100k loaded", async () => {
    const r = await call("query", { sql: "SELECT g, repeat('x', 50) FROM generate_series(1, 100000) g" });
    assert.equal(r.isError, false, r.text);
    assert.match(r.text, /^more than 200 rows/);
    assert.equal(JSON.parse(r.text.split("\n")[1]).rows.length, 200);
  });
  await check("wide rows can't fill the API's memory: the socket is cut at 8 MB", async () => {
    global.gc?.();
    const rss0 = process.memoryUsage().rss;
    for (const sql of ["SELECT repeat('x', 1000000) FROM generate_series(1, 201)", "SELECT repeat('x', 60000000)"]) {
      const r = await call("query", { sql });
      assert.equal(r.isError, true, sql);
      assert.match(r.text, /Result too large/, r.text);
    }
    const grew = (process.memoryUsage().rss - rss0) / 1024 / 1024;
    console.log(`       (RSS grew ${grew.toFixed(0)} MB across both; uncapped, the first alone added ~262 MB)`);
    assert.ok(grew < 120, `RSS grew ${grew.toFixed(0)} MB`);
    const after = await call("query", { sql: "SELECT 1 AS still_works" });
    assert.equal(after.isError, false, after.text);
  });
  await check("long cells are clipped and the reply stays under 60k chars", async () => {
    const r = await call("query", { sql: "SELECT repeat('y', 5000) FROM generate_series(1, 150)" });
    assert.ok(r.text.length <= 61_000, `${r.text.length} chars`);
    assert.match(r.text, /…\[\+3000 chars\]/);
  });
  await check("if a COPY ever got through, the cursor survives it (it would crash plain pg-cursor)", async () => {
    const c = new pg.Client({ connectionString: urlAs(RW) });
    c.on("error", () => {});
    await c.connect();
    try {
      for (const sql of ["COPY (SELECT 1) TO STDOUT", "COPY display_messages FROM STDIN"]) {
        const cur = c.query(new SafeCursor(sql, undefined, { rowMode: "array" }));
        const outcome = await new Promise((resolve) => cur.read(10, (err, rows) => resolve(err ? `error: ${err.message}` : `rows: ${rows.length}`)));
        console.log(`       (${sql} → ${outcome})`);
      }
      assert.equal((await c.query("SELECT 42 AS n")).rows[0].n, 42, "connection still usable");
    } finally {
      await c.end();
    }
  });
  await check("a connection killed mid-query fails that call and nothing else", async () => {
    const pending = call("query", { sql: "SELECT pg_sleep(3)" });
    await new Promise((r) => setTimeout(r, 700));
    const killed = await q(`SELECT pg_terminate_backend(pid) AS ok FROM pg_stat_activity
      WHERE application_name = 'mad_mcp_read' AND query LIKE '%pg_sleep%'`);
    assert.equal(killed.length, 1, "found the running query");
    const r = await pending;
    assert.equal(r.isError, true, r.text);
    assert.equal((await call("query", { sql: "SELECT 1 AS still_works" })).isError, false);
  });
  await check("the mcp_* tables read as empty (row-level security)", async () => {
    for (const table of ["mcp_audit_log", "mcp_oauth_tokens", "mcp_oauth_grants", "mcp_oauth_clients"]) {
      const real = Number((await q(`SELECT count(*) FROM ${table}`))[0].count);
      assert.ok(real > 0, `${table} has rows for the app role`);
      const r = await call("query", { sql: `SELECT count(*)::int AS n FROM ${table}` });
      assert.deepEqual(JSON.parse(r.text.split("\n")[1]).rows, [[0]], table);
    }
  });

  console.log("mcp-check: execute (write role, dry run → token-confirmed commit)");
  const upd = `UPDATE users SET bio = 'mcp-check' WHERE user_id = '${people.dave.id}'`;
  let updToken;
  await check("dry run by default: per-table changes + a confirm token, nothing saved", async () => {
    const r = await dryRun(upd);
    assert.match(r.text, /^DRY RUN .* would change 1 row\(s\) \(users: 1 updated\)/);
    updToken = tokenIn(r.text);
    assert.match(updToken ?? "", /^\d+\.[A-Za-z0-9_-]{32}$/);
    assert.equal(await bio(people.dave), null);
  });
  await check("commit without a token, or with a forged/expired one, is refused before running", async () => {
    for (const confirm_token of [undefined, "1.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", `${Math.floor(Date.now() / 1000)}.forged`]) {
      const r = await call("execute", { sql: upd, commit: true, confirm_token });
      assert.equal(r.isError, true, String(confirm_token));
    }
    assert.equal(await bio(people.dave), null);
  });
  await check("a token commits only ITS statement: a different one with the same count rolls back", async () => {
    const other = `UPDATE users SET bio = 'swapped' WHERE user_id = '${people.rob.id}'`;
    const r = await call("execute", { sql: other, commit: true, confirm_token: updToken });
    assert.equal(r.isError, true);
    assert.match(r.text, /not what the dry run showed/);
    assert.equal(await bio(people.rob), null);
  });
  await check("the right token saves", async () => {
    const r = await call("execute", { sql: upd, commit: true, confirm_token: updToken });
    assert.equal(r.isError, false, r.text);
    assert.match(r.text, /^COMMITTED — 1 row\(s\) changed \(users: 1 updated\)/);
    assert.equal(await bio(people.dave), "mcp-check");
  });
  await check("if the data moved since the dry run, the commit rolls back", async () => {
    const sql = `UPDATE users SET bio = 'moved' WHERE bio = 'mcp-check'`;
    const t = tokenIn((await dryRun(sql)).text);
    await q(`UPDATE users SET bio = 'mcp-check' WHERE user_id = $1`, [people.rob.id]); // now 2 rows match
    const r = await call("execute", { sql, commit: true, confirm_token: t });
    assert.equal(r.isError, true);
    assert.match(r.text, /now changes users: 2 updated/);
    await q(`UPDATE users SET bio = NULL WHERE user_id = $1`, [people.rob.id]);
  });
  await check("a statement that changes nothing gets no token and can't commit", async () => {
    const r = await dryRun(`UPDATE users SET bio = 'x' WHERE false`);
    assert.match(r.text, /changes no rows, so there is nothing to commit/);
    assert.equal(tokenIn(r.text), undefined);
  });
  await check("`…; COMMIT` cannot smuggle a commit past a dry run", async () => {
    const r = await call("execute", { sql: `UPDATE users SET bio = 'smuggled' WHERE user_id = '${people.dave.id}'; COMMIT` });
    assert.equal(r.isError, true);
    assert.equal(await bio(people.dave), "mcp-check");
  });
  await check("only DML is sent: ALTER ROLE, DO, LOCK, SELECT, COPY, DDL are refused up front", async () => {
    for (const sql of [`ALTER ROLE ${RW} PASSWORD 'pwned'`, `ALTER ROLE ${RW} SET work_mem = '2GB'`,
      "DO $$ BEGIN LOCK TABLE users IN ACCESS EXCLUSIVE MODE; PERFORM pg_sleep(4); END $$",
      "LOCK TABLE users IN ACCESS EXCLUSIVE MODE", "SELECT lo_from_bytea(0, 'x')", "COPY users FROM STDIN",
      "DROP TABLE users", "TRUNCATE users", "ALTER TABLE users ADD COLUMN mcp_x int", "CREATE TABLE mcp_x (a int)"]) {
      const r = await call("execute", { sql });
      assert.equal(r.isError, true, sql);
      assert.match(r.text, /execute only runs INSERT, UPDATE, DELETE, MERGE or WITH/, sql);
    }
  });
  await check("…and the write role itself can't DROP/TRUNCATE/ALTER/CREATE/setval (Postgres, not the gate)", async () => {
    const c = new pg.Client({ connectionString: urlAs(RW) });
    await c.connect();
    try {
      const [{ seq }] = (await c.query(`SELECT c.oid::regclass::text AS seq FROM pg_class c
        WHERE c.relkind = 'S' AND c.relnamespace = 'public'::regnamespace ORDER BY 1 LIMIT 1`)).rows;
      for (const sql of ["DROP TABLE users", "TRUNCATE users", "ALTER TABLE users ADD COLUMN mcp_x int",
        "CREATE TABLE public.mcp_x (a int)", `SELECT setval('${seq}', 987654)`]) {
        await assert.rejects(c.query(sql), /must be owner|permission denied/, sql);
      }
    } finally {
      await c.end();
    }
  });
  await check("a delete shows what it cascades into, and RETURNING rows come back", async () => {
    await q(`INSERT INTO display_keys (user_id, key_hash, key_prefix) VALUES ($1, $2, 'mcpchk')`,
      [people.mal.id, crypto.randomBytes(32).toString("hex")]);
    const r = await dryRun(`DELETE FROM users WHERE user_id = '${people.mal.id}' RETURNING username`);
    assert.match(r.text, /would change 2 row\(s\) \(.*display_keys: 1 deleted.*users: 1 deleted/);
    assert.ok(r.text.includes(people.mal.username), "RETURNING row shown");
    assert.equal((await q(`SELECT count(*)::int AS n FROM display_keys WHERE user_id = $1`, [people.mal.id]))[0].n, 1);
  });
  await check("a write hidden in a CTE is counted, so it can't pass as a smaller change", async () => {
    const sql = `WITH d AS (UPDATE users SET bio = 'cte' WHERE user_id IN ('${people.dave.id}', '${people.rob.id}') RETURNING 1)
                 SELECT 1 AS one`;
    const r = await dryRun(sql);
    assert.match(r.text, /would change 2 row\(s\) \(users: 2 updated\)/, r.text);
    const bad = await call("execute", { sql, commit: true, confirm_token: updToken });
    assert.equal(bad.isError, true);
    assert.equal(await bio(people.rob), null);
  });
  await check("returned rows past 200 are counted exactly (cursor drain), changes stay 0", async () => {
    const r = await dryRun("WITH s AS (SELECT g FROM generate_series(1, 1234) g) SELECT g FROM s");
    assert.match(r.text, /changes no rows/, r.text);
    assert.match(r.text, /Returned: 1234 row\(s\)/, r.text);
  });
  await check("sequences: nextval() yes, setval() no (it would survive even a dry run)", async () => {
    const [{ seq }] = await q(`SELECT c.oid::regclass::text AS seq FROM pg_class c
      WHERE c.relkind = 'S' AND c.relnamespace = 'public'::regnamespace ORDER BY 1 LIMIT 1`);
    await dryRun(`WITH n AS (SELECT nextval('${seq}')) SELECT * FROM n`);
    const before = (await q(`SELECT last_value::text AS v FROM ${seq}`))[0].v;
    const set = await call("execute", { sql: `WITH s AS (SELECT setval('${seq}', 987654)) SELECT * FROM s` });
    assert.equal(set.isError, true);
    assert.match(set.text, /permission denied/);
    assert.equal((await q(`SELECT last_value::text AS v FROM ${seq}`))[0].v, before, seq);
  });
  await check("nothing a statement leaves on its session outlives the call (advisory lock)", async () => {
    await dryRun("WITH l AS (SELECT pg_advisory_lock(424242)) SELECT * FROM l");
    const c = await admin.connect();
    try {
      assert.equal((await c.query("SELECT pg_try_advisory_lock(424242) AS got")).rows[0].got, true);
      await c.query("SELECT pg_advisory_unlock(424242)");
    } finally {
      c.release();
    }
  });
  await check("cannot erase the audit trail or plant a token (row-level security)", async () => {
    const before = Number((await q(`SELECT count(*) FROM mcp_audit_log`))[0].count);
    assert.match((await dryRun("DELETE FROM mcp_audit_log")).text, /changes no rows/);
    assert.match((await dryRun(`INSERT INTO mcp_oauth_tokens (token_hash, grant_id, kind, expires_at)
      SELECT 'x', grant_id, 'access', now() + interval '1 year' FROM mcp_oauth_grants`)).text, /changes no rows/);
    const direct = await call("execute", {
      sql: `INSERT INTO mcp_oauth_grants (user_id, client_id, scope, resource, expires_at)
            VALUES ('${people.eve.id}', 'x', 'db:read db:write', '${MCP_URL.href}', now() + interval '1 year')`,
    });
    assert.equal(direct.isError, true);
    assert.match(direct.text, /row-level security/);
    assert.ok(Number((await q(`SELECT count(*) FROM mcp_audit_log`))[0].count) > before);
  });
  await check("making someone admin in the database does NOT let them in", async () => {
    const sql = `UPDATE users SET role = 'admin' WHERE user_id = '${people.eve.id}'`;
    const r = await call("execute", { sql, commit: true, confirm_token: tokenIn((await dryRun(sql)).text) });
    assert.equal(r.isError, false, r.text);
    const s = await signIn(authorizeUrl(auth.info.client_id, auth.redirectUrl, pkce().challenge), people.eve);
    assert.equal(s.res.status, 403);
  });
  await check("pointing Dave's account at another Apple ID does NOT let that Apple ID in", async () => {
    const sql = `UPDATE users SET apple_sub = '${people.eve.sub}-x' WHERE user_id = '${people.dave.id}'`;
    const r = await call("execute", { sql, commit: true, confirm_token: tokenIn((await dryRun(sql)).text) });
    assert.equal(r.isError, false, r.text);
    const fresh = () => authorizeUrl(auth.info.client_id, auth.redirectUrl, pkce().challenge);
    assert.equal((await signIn(fresh(), { sub: `${people.eve.sub}-x` })).res.status, 403, "attacker's Apple ID refused");
    assert.equal((await signIn(fresh(), people.dave)).res.status, 303, "Dave's own Apple ID still works");
    await q(`UPDATE users SET apple_sub = $2 WHERE user_id = $1`, [people.dave.id, people.dave.sub]);
  });

  console.log("mcp-check: audit trail");
  await check("every statement is logged with who and per-table changes; commits are marked", async () => {
    const rows = await q(
      `SELECT tool, statement, commit_requested, committed, row_count, changes, error, finished_at
         FROM mcp_audit_log WHERE user_id = $1 AND tool IN ('query', 'execute') ORDER BY created_at`,
      [people.dave.id],
    );
    assert.ok(rows.length >= 30, `${rows.length} rows`);
    assert.ok(rows.every((r) => r.finished_at), "every row finished");
    const committed = rows.filter((r) => r.committed && r.statement === upd);
    assert.equal(committed.length, 1);
    assert.deepEqual(committed[0].changes, [{ table: "users", inserted: 0, updated: 1, deleted: 0 }]);
    assert.ok(rows.some((r) => r.statement === "SELECT 1; SELECT 2" && /multiple commands/.test(r.error)));
    assert.ok(rows.some((r) => r.commit_requested && !r.committed && /not what the dry run showed/.test(r.error ?? "")));
  });
  await check("sign-ins and refusals are in the same protected log", async () => {
    const tools = (await q(`SELECT tool, count(*)::int AS n FROM mcp_audit_log WHERE created_at >= $1
      AND tool LIKE 'sign_in%' GROUP BY tool`, [runStart])).reduce((m, r) => ({ ...m, [r.tool]: r.n }), {});
    assert.ok(tools.sign_in >= 2 && tools.sign_in_denied >= 2, JSON.stringify(tools));
  });
  await check("audit_log tool shows it by username, with head AND tail of long statements", async () => {
    const padded = `UPDATE users SET bio = bio /* ${"z".repeat(3000)} */ WHERE user_id = 'tail-marker-${people.dave.id}'`;
    await dryRun(padded);
    const r = await call("audit_log", { writes_only: true, limit: 5 });
    assert.equal(r.isError, false, r.text);
    const rows = JSON.parse(r.text);
    assert.equal(rows.length, 5);
    assert.ok(rows.every((x) => x.tool === "execute" && x.who === people.dave.username));
    assert.ok(rows[0].statement.includes("tail-marker-"), "the end of a padded statement is visible");
  });

  console.log("mcp-check: sign-in attacks");
  const dc = auth.info.client_id;
  const fresh = () => authorizeUrl(dc, auth.redirectUrl, pkce().challenge);
  await check("no cookie (a link opened in someone else's browser) → refused", async () => {
    const a = await openAuthorize(fresh());
    const res = await postCallback({ request: a.request, idToken: await appleIdToken(people.dave.sub, a.nonce) });
    assert.equal(res.status, 400);
  });
  await check("another browser's cookie → refused", async () => {
    const a = await openAuthorize(fresh());
    const b = await openAuthorize(fresh());
    const forged = `mcp_signin_${a.request.slice(0, 16)}=${b.cookie.split("=")[1]}`;
    const res = await postCallback({ request: a.request, idToken: await appleIdToken(people.dave.sub, a.nonce), cookie: forged });
    assert.equal(res.status, 400);
  });
  await check("a dashboard id_token (wrong nonce) → refused", async () => {
    const a = await openAuthorize(fresh());
    const res = await postCallback({ request: a.request, idToken: await appleIdToken(people.dave.sub, "dashboard"), cookie: a.cookie });
    assert.equal(res.status, 401);
  });
  await check("an id_token for another Apple app, from another issuer, or 20 minutes old → refused", async () => {
    for (const o of [{ aud: "com.other.app" }, { iss: "https://evil.example" }, { iat: Math.floor(Date.now() / 1000) - 1200 }]) {
      const a = await openAuthorize(fresh());
      const res = await postCallback({ request: a.request, idToken: await appleIdToken(people.dave.sub, a.nonce, o), cookie: a.cookie });
      assert.equal(res.status, 401, JSON.stringify(o));
    }
  });
  await check("an id_token signed by anyone but Apple → refused", async () => {
    const a = await openAuthorize(fresh());
    const { privateKey: other } = await generateKeyPair("RS256");
    const forged = await new SignJWT({ nonce: a.nonce }).setProtectedHeader({ alg: "RS256", kid: "check" })
      .setIssuer("https://appleid.apple.com").setAudience(SERVICES_ID).setSubject(people.dave.sub)
      .setIssuedAt().setExpirationTime("5m").sign(other);
    assert.equal((await postCallback({ request: a.request, idToken: forged, cookie: a.cookie })).status, 401);
  });
  await check("allowlisted but not admin → refused; unknown Apple ID → refused", async () => {
    assert.equal((await signIn(fresh(), people.mal)).res.status, 403);
    assert.equal((await signIn(fresh(), { sub: "001234.nobody.0000" })).res.status, 403);
  });
  await check("a sign-in cannot be replayed", async () => {
    const s = await signIn(fresh(), people.rob);
    assert.equal(s.res.status, 303);
    const again = await postCallback({ request: s.request, idToken: await appleIdToken(people.rob.sub, s.nonce), cookie: s.cookie });
    assert.equal(again.status, 400);
  });
  await check("authorize for an unregistered redirect or another resource → refused", async () => {
    const bad = await fetch(authorizeUrl(dc, "http://localhost:1/other", pkce().challenge), { redirect: "manual" });
    assert.equal(bad.status, 400);
    const other = await fetch(authorizeUrl(dc, auth.redirectUrl, pkce().challenge, { resource: "https://elsewhere.example/mcp" }), { redirect: "manual" });
    assert.equal(other.status, 302);
    assert.equal(new URL(other.headers.get("location")).searchParams.get("error"), "invalid_target");
  });

  console.log("mcp-check: token endpoint");
  async function codeFor(person, clientId = dc, redirect = auth.redirectUrl) {
    const p = pkce();
    const s = await signIn(authorizeUrl(clientId, redirect, p.challenge), person);
    assert.equal(s.res.status, 303, await s.res.text());
    return { ...p, code: new URL(s.res.headers.get("location")).searchParams.get("code") };
  }
  await check("wrong PKCE verifier → invalid_grant", async () => {
    const c = await codeFor(people.rob);
    const r = await token({ grant_type: "authorization_code", code: c.code, code_verifier: pkce().verifier, client_id: dc });
    assert.equal(r.body.error, "invalid_grant");
  });
  await check("a code redeemed by a different client → invalid_grant", async () => {
    const c = await codeFor(people.rob);
    const r = await token({ grant_type: "authorization_code", code: c.code, code_verifier: c.verifier, client_id: otherClient });
    assert.equal(r.body.error, "invalid_grant");
  });
  await check("claude.ai: the pre-registered client works only with its secret", async () => {
    const CA = "https://claude.ai/api/mcp/auth_callback";
    const p = pkce();
    const a = await openAuthorize(authorizeUrl("mad-claude-ai", CA, p.challenge));
    assert.equal(a.page.searchParams.get("to"), "claude.ai");
    const res = await postCallback({ request: a.request, idToken: await appleIdToken(people.rob.sub, a.nonce), cookie: a.cookie });
    const loc = res.headers.get("location");
    assert.ok(loc.startsWith(`${CA}?code=`), loc);
    const code = new URL(loc).searchParams.get("code");
    const base = { grant_type: "authorization_code", code, code_verifier: p.verifier, client_id: "mad-claude-ai" };
    assert.equal((await token(base)).body.error, "invalid_client", "no secret");
    assert.equal((await token({ ...base, client_secret: "wrong" })).body.error, "invalid_client", "wrong secret");
    const ok = await token({ ...base, client_secret: CLAUDE_AI_SECRET });
    assert.equal(ok.status, 200, JSON.stringify(ok.body));
    // …and with the secret in an HTTP Basic header instead (claude.ai doesn't document which it uses).
    const basic = await fetch(`${BASE}/token`, {
      method: "POST",
      headers: {
        "content-type": "application/x-www-form-urlencoded",
        authorization: `Basic ${Buffer.from(`mad-claude-ai:${CLAUDE_AI_SECRET}`).toString("base64")}`,
      },
      body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: ok.body.refresh_token }),
    });
    assert.equal(basic.status, 200, await basic.text());
    const wrongBasic = await fetch(`${BASE}/token`, {
      method: "POST",
      headers: {
        "content-type": "application/x-www-form-urlencoded",
        authorization: `Basic ${Buffer.from("mad-claude-ai:wrong").toString("base64")}`,
      },
      body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: ok.body.refresh_token }),
    });
    assert.equal((await wrongBasic.json()).error, "invalid_client");
  });

  console.log("mcp-check: tokens over time");
  const c = await codeFor(people.rob);
  const first = await token({ grant_type: "authorization_code", code: c.code, code_verifier: c.verifier, client_id: dc, redirect_uri: auth.redirectUrl });
  await check("rob signs in too", async () => {
    assert.equal(first.status, 200, JSON.stringify(first.body));
    assert.equal((await rawCall(first.body.access_token, "query", { sql: "select 1" })).status, 200);
  });
  let second;
  await check("two sessions refreshing the same token at the same instant both succeed", async () => {
    const [a, b] = await Promise.all([
      token({ grant_type: "refresh_token", refresh_token: first.body.refresh_token, client_id: dc }),
      token({ grant_type: "refresh_token", refresh_token: first.body.refresh_token, client_id: dc }),
    ]);
    assert.equal(a.status, 200, JSON.stringify(a.body));
    assert.equal(b.status, 200, JSON.stringify(b.body));
    second = a;
    assert.notEqual(second.body.refresh_token, first.body.refresh_token);
    assert.equal((await rawCall(a.body.access_token, "query", { sql: "select 1" })).status, 200);
    assert.equal((await rawCall(b.body.access_token, "query", { sql: "select 1" })).status, 200);
  });
  await check("a refresh token is bound to its client", async () => {
    const r = await token({ grant_type: "refresh_token", refresh_token: second.body.refresh_token, client_id: otherClient });
    assert.equal(r.body.error, "invalid_grant");
  });
  await check("reuse after the grace window revokes the whole sign-in, and is audited", async () => {
    await q(`UPDATE mcp_oauth_tokens SET used_at = now() - interval '2 minutes' WHERE used_at IS NOT NULL`);
    const r = await token({ grant_type: "refresh_token", refresh_token: first.body.refresh_token, client_id: dc });
    assert.equal(r.body.error, "invalid_grant");
    assert.equal((await rawCall(second.body.access_token, "query", { sql: "select 1" })).status, 401);
    assert.equal((await token({ grant_type: "refresh_token", refresh_token: second.body.refresh_token, client_id: dc })).body.error, "invalid_grant");
    assert.equal((await q(`SELECT count(*)::int AS n FROM mcp_audit_log WHERE tool = 'refresh_reuse' AND user_id = $1`, [people.rob.id]))[0].n, 1);
  });
  await check("revoking either token ends the sign-in", async () => {
    const c2 = await codeFor(people.rob);
    const t = await token({ grant_type: "authorization_code", code: c2.code, code_verifier: c2.verifier, client_id: dc });
    const res = await fetch(`${BASE}/revoke`, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ token: t.body.refresh_token, client_id: dc }),
    });
    assert.equal(res.status, 200);
    assert.equal((await rawCall(t.body.access_token, "query", { sql: "select 1" })).status, 401);
  });
  await check("an expired access token → 401; a sign-in past 30 days → refresh refused", async () => {
    const c3 = await codeFor(people.rob);
    const t = await token({ grant_type: "authorization_code", code: c3.code, code_verifier: c3.verifier, client_id: dc });
    const grant = (await q(`SELECT g.grant_id, g.expires_at - g.created_at AS life FROM mcp_oauth_grants g
      JOIN mcp_oauth_tokens t USING (grant_id) WHERE t.token_hash = $1`,
      [crypto.createHash("sha256").update(t.body.access_token).digest("hex")]))[0];
    assert.equal(grant.life.days, 30);
    await q(`UPDATE mcp_oauth_tokens SET expires_at = now() - interval '1 second' WHERE grant_id = $1 AND kind = 'access'`, [grant.grant_id]);
    assert.equal((await rawCall(t.body.access_token, "query", { sql: "select 1" })).status, 401);
    await q(`UPDATE mcp_oauth_grants SET expires_at = now() - interval '1 second' WHERE grant_id = $1`, [grant.grant_id]);
    assert.equal((await token({ grant_type: "refresh_token", refresh_token: t.body.refresh_token, client_id: dc })).body.error, "invalid_grant");
  });
  await check("losing admin locks out an existing session on the next call", async () => {
    await q(`UPDATE users SET role = 'user' WHERE user_id = $1`, [people.dave.id]);
    const r = await call("query", { sql: "select 1" }).catch((e) => ({ thrown: e }));
    assert.ok(r.thrown || r.isError, "call refused");
    await q(`UPDATE users SET role = 'admin' WHERE user_id = $1`, [people.dave.id]);
  });

  console.log("mcp-check: misconfiguration fails closed");
  const refusedFor = async (writeUrl) => {
    await closeMcpPools();
    configureDatabase(urlAs(RO), writeUrl);
    try {
      return await checkRoleBoundary("write");
    } finally {
      await closeMcpPools();
    }
  };
  await check("an mcp_* table without row-level security → both roles refused", async () => {
    await q(`ALTER TABLE mcp_oauth_tokens DISABLE ROW LEVEL SECURITY`);
    try {
      await closeMcpPools();
      configureDatabase(urlAs(RO), urlAs(RW));
      for (const kind of ["read", "write"]) {
        assert.match(String(await checkRoleBoundary(kind)), /1 mcp_\* table\(s\) lack row-level security/, kind);
      }
    } finally {
      await q(`ALTER TABLE mcp_oauth_tokens ENABLE ROW LEVEL SECURITY`);
      await closeMcpPools();
    }
  });
  await check("any role membership beyond pg_read_all_data is refused (pg_write_all_data, pg_signal_backend…)", async () => {
    await q(`DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'mcp_check_broad') THEN CREATE ROLE mcp_check_broad LOGIN; END IF; END $$`);
    await q(`ALTER ROLE mcp_check_broad PASSWORD '${PW}'`);
    await q(`GRANT CONNECT ON DATABASE "${DB}" TO mcp_check_broad`);
    await q(`GRANT pg_read_all_data TO mcp_check_broad`);
    assert.equal(await refusedFor(urlAs("mcp_check_broad")), null, "plain pg_read_all_data passes");
    for (const extra of ["pg_signal_backend", "pg_write_all_data", "pg_read_server_files"]) {
      await q(`GRANT ${extra} TO mcp_check_broad`);
      assert.match(String(await refusedFor(urlAs("mcp_check_broad"))), new RegExp(`member of .*${extra}`), extra);
      await q(`REVOKE ${extra} FROM mcp_check_broad`);
    }
    await q(`ALTER ROLE mcp_check_broad REPLICATION`);
    assert.match(String(await refusedFor(urlAs("mcp_check_broad"))), /replicate/);
  });
  await check("a superuser behind the write URL → every tool refuses, nothing runs", async () => {
    await closeMcpPools();
    const app2 = express();
    app2.use(express.json());
    const s2 = http.createServer(app2);
    await new Promise((resolve) => s2.listen(0, "127.0.0.1", resolve));
    const base2 = `http://127.0.0.1:${s2.address().port}`;
    // Not byte-identical to DATABASE_URL, so only the live role check can catch it.
    const sneaky = new URL(process.env.DATABASE_URL);
    sneaky.searchParams.set("application_name", "sneaky");
    mountMcpConnector(app2, { env: { ...env, MCP_BASE_URL: base2, MCP_DATABASE_URL_RW: sneaky.href }, appleKeys });
    const cid = (await (await register(["http://localhost:1/cb"], base2)).json()).client_id;
    const p = pkce();
    const s = await signIn(authorizeUrl(cid, "http://localhost:1/cb", p.challenge, {}, base2), people.dave, base2);
    const code = new URL(s.res.headers.get("location")).searchParams.get("code");
    const t = await token({ grant_type: "authorization_code", code, code_verifier: p.verifier, client_id: cid }, base2);
    const r = await rawCall(t.body.access_token, "execute",
      { sql: `UPDATE users SET bio = 'superuser' WHERE user_id = '${people.dave.id}'` }, base2);
    assert.equal(r.body.result.isError, true);
    assert.match(r.body.result.content[0].text, /Connector misconfigured .*superuser/);
    assert.equal(await bio(people.dave), "mcp-check");
    s2.close();
  });
} finally {
  await closeMcpPools().catch(() => {});
  await q(`DELETE FROM mcp_audit_log WHERE created_at >= $1`, [runStart]).catch(() => {});
  // Grants and tokens go with the users (ON DELETE CASCADE); the rest by time.
  await q(`DELETE FROM mcp_oauth_clients WHERE created_at >= $1`, [runStart]).catch(() => {});
  await q(`DELETE FROM mcp_oauth_requests WHERE expires_at >= $1`, [runStart]).catch(() => {});
  await q(`DELETE FROM mcp_oauth_codes WHERE expires_at >= $1`, [runStart]).catch(() => {});
  await q(`DELETE FROM users WHERE user_id = ANY($1)`, [ourUsers]).catch(() => {});
  await dropRoles();
  server.close();
  await admin.end();
  await PostgresService.getInstance().close?.();
}

console.log(failures ? `mcp-check: ${failures} FAILED` : "mcp-check: all passed");
process.exit(failures ? 1 : 0);
