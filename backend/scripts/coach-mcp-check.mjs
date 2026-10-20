// Coach MCP check (src/coachMcp): Run Plans for Claude, any Mile A Day+ member.
// The whole sign-in and every guard, against a real Postgres, driven by the
// MCP SDK's own OAuth client — the same discovery → registration → PKCE →
// token path Claude takes — THROUGH a stand-in for the website's proxy built
// from website/next.config.mjs's own rewrite table, so the public URLs in the
// metadata, the rewrites and the backend routes are checked together.
//
// Only Apple is faked: id_tokens are signed with a local key and verified
// against it through the `appleKeys` test seam. The DB connector (src/mcp) is
// mounted on the same app, as in server.ts, to prove the two never accept each
// other's tokens (its database roles are not needed for that and not created).
//
// Usage: npm run build && DATABASE_URL=... node scripts/coach-mcp-check.mjs
import assert from "node:assert/strict";
import crypto from "node:crypto";
import http from "node:http";
import express from "express";
import pg from "pg";
import { generateKeyPair, exportJWK, SignJWT, createLocalJWKSet } from "jose";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";
import { UnauthorizedError } from "@modelcontextprotocol/sdk/client/auth.js";

// Dozens of sign-ins from one address in a few seconds.
process.env.RATE_LIMITS_DISABLED = "1";

const { mountCoachMcp } = await import("../dist/coachMcp/index.js");
const { loadCoachMcpConfig } = await import("../dist/coachMcp/config.js");
const { mountMcpConnector } = await import("../dist/mcp/index.js");
const { closeMcpPools } = await import("../dist/mcp/dbTools.js");
const { coachConnectionStatus, revokeCoachTokens } = await import("../dist/services/runPlans/coachConnection.js");
const S = await import("../dist/services/runPlans/runPlanService.js");
const { FOUNDING_CUTOFF } = await import("../dist/services/plusCatalog.js");
const { PostgresService } = await import("../dist/services/DbService.js");
const { coachMcpRewrites } = await import("../../website/next.config.mjs");

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

const TODAY = new Date().toISOString().slice(0, 10);
const addDays = (d, n) => new Date(Date.parse(d + "T00:00:00Z") + n * 86_400_000).toISOString().slice(0, 10);
const sha = (s) => crypto.createHash("sha256").update(s).digest("hex");

// ---------------------------------------------------------------------------
// People: pat + quinn are Plus runners with plans; fran has no Plus; adm is
// an admin on the DB connector's allowlist (and Plus, so a refusal of adm's
// DB token at the coach is about the audience, not entitlement).
// ---------------------------------------------------------------------------
const uid = () => crypto.randomBytes(16).toString("hex");
const people = { pat: { id: uid() }, quinn: { id: uid() }, fran: { id: uid() }, adm: { id: uid(), role: "admin" } };
for (const [name, p] of Object.entries(people)) {
  p.sub = `001234.${crypto.randomBytes(16).toString("hex")}.${name}`;
  await q(
    `INSERT INTO users (user_id, apple_sub, email, username, role, first_name) VALUES ($1, $2, $3, $4, $5, 'C')`,
    [p.id, p.sub, `${p.id}@example.com`, `coach_${name}_${p.id.slice(0, 6)}`, p.role ?? "user"],
  );
}
const ourUsers = Object.values(people).map((p) => p.id);
// After FOUNDING_CUTOFF, or they'd be Founding Runners (Plus for life).
const afterCutoff = new Date(Date.parse(FOUNDING_CUTOFF) + 86_400_000).toISOString();
await q(`UPDATE users SET created_at = GREATEST(now(), $2::timestamptz) WHERE user_id = ANY($1)`, [ourUsers, afterCutoff]);
for (const p of [people.pat, people.quinn, people.adm]) {
  await q(
    `INSERT INTO plus_purchases (original_transaction_id, user_id, product_id, transaction_id, kind,
                                 ownership, environment, purchased_at)
     VALUES ($1, $2, 'mad.plus.lifetime', $1, 'lifetime', 'PURCHASED', 'Sandbox', now())`,
    [`coach-${p.id}`, p.id],
  );
}
const setPlus = (p, on) =>
  q(`UPDATE plus_purchases SET revoked_at = ${on ? "NULL" : "now()"} WHERE user_id = $1`, [p.id]);

let wseq = 0;
async function workout(p, date, miles, paceS) {
  const id = `coach-${p.id.slice(0, 6)}-${++wseq}`;
  await q(
    `INSERT INTO workouts (workout_id, user_id, distance, local_date, date, timezone_offset,
                           workout_type, device_end_date, calories, total_duration)
     VALUES ($1, $2, $3, $4::date, $4::date, 0, 'running', $4::date + time '12:00', 100, $5)`,
    [id, p.id, miles, date, miles * paceS],
  );
  for (let i = 0; i < Math.floor(miles); i++) {
    await q(
      `INSERT INTO workout_splits (workout_id, split_number, split_duration, split_distance, split_pace)
       VALUES ($1, $2, $3, 1, $3)`,
      [id, i + 1, paceS],
    );
  }
  return id;
}
const runIds = { pat: [], quinn: [] };
for (let i = 1; i <= 12; i++) {
  runIds.pat.push(await workout(people.pat, addDays(TODAY, -i), i % 4 === 0 ? 4 : 2, 540));
  runIds.quinn.push(await workout(people.quinn, addDays(TODAY, -i), 3, 600));
}
for (const p of [people.pat, people.quinn]) {
  await S.createPlan(p.id, { goals: [{ type: "faster_mile", target_seconds: 450 }], effort: 2, run_daily_mile: false }, TODAY);
}
await S.recordCheckin(people.pat.id, TODAY, { feeling: "normal", message: "pat-note" });
await S.recordCheckin(people.quinn.id, TODAY, { feeling: "normal", message: "quinn-secret" });
const runStart = (await q(`SELECT now() AS t`))[0].t;

// ---------------------------------------------------------------------------
// Fake Apple.
// ---------------------------------------------------------------------------
const { publicKey, privateKey } = await generateKeyPair("RS256");
const appleKeys = createLocalJWKSet({ keys: [{ ...(await exportJWK(publicKey)), kid: "check", alg: "RS256" }] });
const SERVICES_ID = "org.robertwiscount.Mile-A-Day.web";
function appleIdToken(sub, nonce, key = privateKey) {
  return new SignJWT({ nonce })
    .setProtectedHeader({ alg: "RS256", kid: "check" })
    .setIssuer("https://appleid.apple.com")
    .setAudience(SERVICES_ID)
    .setSubject(sub)
    .setIssuedAt()
    .setExpirationTime("10m")
    .sign(key);
}

// ---------------------------------------------------------------------------
// The backend (same order as server.ts: json → DB connector → coach → app),
// and the "website": a proxy that knows only next.config.mjs's rewrites.
// ---------------------------------------------------------------------------
const listen = async (handler) => {
  const s = http.createServer(handler);
  await new Promise((resolve) => s.listen(0, "127.0.0.1", resolve));
  return { s, base: `http://127.0.0.1:${s.address().port}` };
};
const app = express();
app.set("trust proxy", 1);
app.use(express.json({ limit: "2mb" }));
const backend = await listen(app);
const BACKEND = backend.base;

let rewrites = [];
const website = await listen(async (req, res) => {
  const url = new URL(req.url, "http://x");
  const rule = rewrites.find((r) => r.source === url.pathname);
  if (!rule) {
    res.writeHead(404).end("website 404");
    return;
  }
  const chunks = [];
  for await (const c of req) chunks.push(c);
  const headers = { ...req.headers };
  for (const h of ["host", "connection", "content-length", "transfer-encoding"]) delete headers[h];
  const upstream = await fetch(rule.destination + url.search, {
    method: req.method,
    headers,
    body: ["GET", "HEAD"].includes(req.method) ? undefined : Buffer.concat(chunks),
    redirect: "manual",
  });
  const out = {};
  upstream.headers.forEach((v, k) => {
    if (!["content-encoding", "content-length", "transfer-encoding", "set-cookie", "connection"].includes(k)) out[k] = v;
  });
  const cookies = upstream.headers.getSetCookie();
  if (cookies.length) out["set-cookie"] = cookies;
  res.writeHead(upstream.status, out).end(Buffer.from(await upstream.arrayBuffer()));
});
const PUBLIC = website.base;
rewrites = coachMcpRewrites(BACKEND);

const COACH_SECRET = crypto.randomBytes(24).toString("hex");
const DB_SECRET = crypto.randomBytes(24).toString("hex");
const dbEnv = {
  MCP_ALLOWED_USERS: `${people.adm.id}:${people.adm.sub}`,
  // Never connected to in this check (no DB tool runs); just not DATABASE_URL.
  MCP_DATABASE_URL_RO: "postgres://mad_mcp_ro_absent@127.0.0.1:1/none",
  MCP_DATABASE_URL_RW: "postgres://mad_mcp_rw_absent@127.0.0.1:1/none",
  MCP_BASE_URL: BACKEND,
  MCP_CLAUDE_AI_CLIENT_SECRET: DB_SECRET,
  DATABASE_URL: process.env.DATABASE_URL,
};
const coachEnv = {
  COACH_MCP_ENABLED: "1",
  COACH_MCP_PUBLIC_URL: PUBLIC,
  COACH_MCP_CLAUDE_AI_CLIENT_SECRET: COACH_SECRET,
  MCP_BASE_URL: BACKEND,
  MCP_CLAUDE_AI_CLIENT_SECRET: DB_SECRET,
};
mountMcpConnector(app, { env: dbEnv, appleKeys });
const mounted = mountCoachMcp(app, { env: coachEnv, appleKeys });
app.use((_req, res) => res.status(418).json({ error: "fell through to the app" }));

// The two authorization servers' public endpoints.
const COACH = {
  base: PUBLIC, mcp: `${PUBLIC}/mcp`, callback: `${PUBLIC}/coach/oauth/apple/callback`, issuer: `${PUBLIC}/`,
  claudeAi: "mad-coach-claude-ai", secret: COACH_SECRET,
};
const DB = {
  base: BACKEND, mcp: `${BACKEND}/mcp`, callback: `${BACKEND}/oauth/apple/callback`, issuer: `${BACKEND}/`,
  claudeAi: "mad-claude-ai", secret: DB_SECRET,
};

// ---------------------------------------------------------------------------
// Helpers: a browser doing the sign-in, PKCE, raw calls.
// ---------------------------------------------------------------------------
const pkce = () => {
  const verifier = crypto.randomBytes(32).toString("base64url");
  return { verifier, challenge: crypto.createHash("sha256").update(verifier).digest("base64url") };
};
const authorizeUrl = (as, clientId, redirectUri, challenge, extra = {}) =>
  `${as.base}/authorize?${new URLSearchParams({
    response_type: "code", client_id: clientId, redirect_uri: redirectUri, code_challenge: challenge,
    code_challenge_method: "S256", state: "st-9", resource: as.mcp, ...extra,
  })}`;

async function openAuthorize(url) {
  const res = await fetch(url, { redirect: "manual" });
  assert.equal(res.status, 302, `authorize → ${res.status} ${await res.text().catch(() => "")}`);
  const page = new URL(res.headers.get("location"));
  const setCookies = res.headers.getSetCookie();
  return {
    page, setCookies,
    request: page.searchParams.get("request"),
    nonce: page.searchParams.get("nonce"),
    cookie: setCookies.map((c) => c.split(";")[0]).join("; "),
  };
}
async function postCallback(as, { request, idToken, cookie }) {
  const headers = { "content-type": "application/x-www-form-urlencoded" };
  if (cookie) headers.cookie = cookie;
  return fetch(as.callback, { method: "POST", redirect: "manual", headers, body: new URLSearchParams({ request, id_token: idToken }) });
}
async function signIn(as, url, person) {
  const a = await openAuthorize(url);
  const res = await postCallback(as, { request: a.request, idToken: await appleIdToken(person.sub, a.nonce), cookie: a.cookie });
  return { ...a, res };
}
async function token(as, body, headers = {}) {
  const res = await fetch(`${as.base}/token`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded", ...headers },
    body: new URLSearchParams(body),
  });
  return { status: res.status, body: await res.json().catch(() => ({})) };
}
async function register(as, redirect_uris) {
  return fetch(`${as.base}/register`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ client_name: "coach-check", redirect_uris, token_endpoint_auth_method: "none" }),
  });
}
async function rpc(mcpUrl, accessToken, method, params = {}) {
  const res = await fetch(mcpUrl, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      accept: "application/json, text/event-stream",
      authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
  });
  return { status: res.status, body: await res.json().catch(() => null), www: res.headers.get("www-authenticate") };
}
const tool = async (mcpUrl, t, name, args = {}) => {
  const r = await rpc(mcpUrl, t, "tools/call", { name, arguments: args });
  assert.equal(r.status, 200, `${name} → ${r.status}`);
  return { text: r.body.result.content[0].text, isError: r.body.result.isError === true };
};
/** Register a loopback client, sign `person` in, redeem the code. */
async function connect(as, person, redirect = "http://localhost:1/cb") {
  const clientId = (await (await register(as, [redirect])).json()).client_id;
  const p = pkce();
  const s = await signIn(as, authorizeUrl(as, clientId, redirect, p.challenge), person);
  assert.equal(s.res.status, 303, `sign-in → ${s.res.status} ${await s.res.text()}`);
  const code = new URL(s.res.headers.get("location")).searchParams.get("code");
  const t = await token(as, { grant_type: "authorization_code", code, code_verifier: p.verifier, client_id: clientId, redirect_uri: redirect });
  assert.equal(t.status, 200, JSON.stringify(t.body));
  return { clientId, ...t.body };
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
      client_name: "Claude Code (coach-check)",
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

try {
  console.log("coach-mcp-check: config");
  await check("mounts with COACH_MCP_ENABLED=1; issuer/resource are the PUBLIC (website) URLs", () => {
    assert.equal(mounted.enabled, true, mounted.reason);
    assert.equal(mounted.config.issuerUrl.href, `${PUBLIC}/`);
    assert.equal(mounted.config.resourceUrl.href, `${PUBLIC}/mcp`);
    assert.equal(mounted.config.signInPageUrl.href, `${PUBLIC}/connect/coach`);
  });
  await check("stays off unless enabled; refuses a short, shared or reused secret/issuer", () => {
    assert.equal(loadCoachMcpConfig({}).enabled, false);
    assert.equal(loadCoachMcpConfig({ ...coachEnv, COACH_MCP_ENABLED: "0" }).enabled, false);
    assert.equal(loadCoachMcpConfig({ ...coachEnv, COACH_MCP_CLAUDE_AI_CLIENT_SECRET: "short" }).enabled, false);
    assert.equal(loadCoachMcpConfig({ ...coachEnv, COACH_MCP_CLAUDE_AI_CLIENT_SECRET: DB_SECRET }).enabled, false);
    assert.equal(loadCoachMcpConfig({ ...coachEnv, COACH_MCP_PUBLIC_URL: BACKEND }).enabled, false);
    assert.equal(loadCoachMcpConfig({ ...coachEnv, COACH_MCP_PUBLIC_URL: `${PUBLIC}/x` }).enabled, false);
    const prod = loadCoachMcpConfig({ COACH_MCP_ENABLED: "1" });
    assert.equal(prod.config.resourceUrl.href, "https://mileaday.run/mcp");
    assert.equal(prod.config.signInPageUrl.href, "https://mileaday.run/connect/coach");
  });
  await check("the website's rewrites point at the backend's /coach/*", () => {
    const prod = Object.fromEntries(coachMcpRewrites("https://mad.mindgoblin.tech").map((r) => [r.source, r.destination]));
    assert.equal(prod["/mcp"], "https://mad.mindgoblin.tech/coach/mcp");
    assert.equal(prod["/.well-known/oauth-protected-resource/mcp"], "https://mad.mindgoblin.tech/coach/.well-known/oauth-protected-resource/mcp");
    for (const r of coachMcpRewrites("https://mad.mindgoblin.tech")) assert.match(r.destination, /^https:\/\/mad\.mindgoblin\.tech\/coach\//);
  });
  await check("every coach_* table has row-level security (the DB connector's roles read them as empty)", async () => {
    const rows = await q(`SELECT relname, relrowsecurity FROM pg_class
      WHERE relnamespace = 'public'::regnamespace AND relkind = 'r' AND relname LIKE 'coach\\_mcp\\_%' ORDER BY 1`);
    assert.equal(rows.length, 6);
    for (const r of rows) assert.equal(r.relrowsecurity, true, r.relname);
  });

  console.log("coach-mcp-check: discovery through the website's proxy");
  await check("unauthenticated /mcp → 401 pointing at the PUBLIC resource metadata", async () => {
    const r = await rpc(COACH.mcp, "nope", "tools/list");
    assert.equal(r.status, 401);
    assert.match(r.www, new RegExp(`resource_metadata="${PUBLIC}/.well-known/oauth-protected-resource/mcp"`));
  });
  await check("protected-resource metadata (path-specific and root): resource /mcp, issuer = website", async () => {
    for (const path of ["/.well-known/oauth-protected-resource/mcp", "/.well-known/oauth-protected-resource"]) {
      const m = await (await fetch(PUBLIC + path)).json();
      assert.equal(m.resource, COACH.mcp, path);
      assert.deepEqual(m.authorization_servers, [COACH.issuer], path);
    }
  });
  await check("authorization-server metadata: all endpoints on the website origin and all proxied", async () => {
    const m = await (await fetch(`${PUBLIC}/.well-known/oauth-authorization-server`)).json();
    assert.equal(m.issuer, COACH.issuer);
    assert.deepEqual(m.code_challenge_methods_supported, ["S256"]);
    for (const k of ["authorization_endpoint", "token_endpoint", "registration_endpoint", "revocation_endpoint"]) {
      const u = new URL(m[k]);
      assert.equal(u.origin, PUBLIC, k);
      assert.ok(rewrites.some((r) => r.source === u.pathname), `${k} ${u.pathname} has no website rewrite`);
    }
  });
  await check("the backend's root metadata is still the DB connector's (two distinct issuers)", async () => {
    const m = await (await fetch(`${BACKEND}/.well-known/oauth-authorization-server`)).json();
    assert.equal(m.issuer, DB.issuer);
    assert.notEqual(m.issuer, COACH.issuer);
  });

  console.log("coach-mcp-check: client registration");
  await check("only loopback (Claude Code) may self-register — not claude.ai, not anywhere else", async () => {
    for (const uris of [["https://evil.example/cb"], ["https://claude.ai/api/mcp/auth_callback"],
      ["http://localhost:1/cb", "https://evil.example/cb"], ["http://user:pw@localhost:1/cb"]]) {
      assert.equal((await register(COACH, uris)).status, 400, uris.join(","));
    }
    assert.equal((await register(COACH, ["http://127.0.0.1:9/callback"])).status, 201);
  });

  console.log("coach-mcp-check: full sign-in with the MCP SDK client (as Claude Code does it)");
  const auth = new MemoryAuthProvider("http://localhost:53682/callback");
  let client;
  await check("connect → 401 → discovery → registration → authorize URL on the website", async () => {
    const t = new StreamableHTTPClientTransport(new URL(COACH.mcp), { authProvider: auth });
    await assert.rejects(new Client({ name: "coach-check", version: "1" }).connect(t), UnauthorizedError);
    assert.ok(auth.info?.client_id, "registered");
    assert.equal(auth.authUrl.origin, PUBLIC);
    assert.equal(auth.authUrl.searchParams.get("resource"), COACH.mcp);
  });
  await check("authorize → /connect/coach + a same-site browser-binding cookie; sign-in → code", async () => {
    const a = await openAuthorize(auth.authUrl);
    assert.equal(a.page.origin + a.page.pathname, `${PUBLIC}/connect/coach`);
    assert.match(a.request, /^[A-Za-z0-9_-]{40,}$/);
    assert.match(a.nonce, /^[0-9a-f]{64}$/);
    assert.equal(a.page.searchParams.get("to"), "this computer");
    const c = a.setCookies.join(" | ");
    for (const attr of ["coach_signin_", "HttpOnly", "Secure", "SameSite=Lax", "Path=/coach/oauth/"]) assert.ok(c.includes(attr), attr);
    const res = await postCallback(COACH, { request: a.request, idToken: await appleIdToken(people.pat.sub, a.nonce), cookie: a.cookie });
    assert.equal(res.status, 303, await res.text());
    const back = new URL(res.headers.get("location"));
    assert.equal(back.origin + back.pathname, "http://localhost:53682/callback");
    assert.equal(back.searchParams.get("state"), auth.authUrl.searchParams.get("state"));
    auth.code = back.searchParams.get("code");
  });
  await check("finishAuth exchanges the code; the six coach tools, none taking a user", async () => {
    await new StreamableHTTPClientTransport(new URL(COACH.mcp), { authProvider: auth }).finishAuth(auth.code);
    assert.ok(auth.tokens()?.access_token && auth.tokens()?.refresh_token);
    client = new Client({ name: "coach-check", version: "1" });
    await client.connect(new StreamableHTTPClientTransport(new URL(COACH.mcp), { authProvider: auth }));
    const tools = (await client.listTools()).tools;
    assert.deepEqual(tools.map((t) => t.name).sort(),
      ["get_checkins", "get_plan", "get_profile", "get_runs", "list_proposals", "propose_change"]);
    for (const t of tools) {
      for (const k of Object.keys(t.inputSchema.properties ?? {})) assert.ok(!/user|sql|query/i.test(k), `${t.name}.${k}`);
    }
    assert.match(tools.find((t) => t.name === "propose_change").description, /swap_hard_today.*set_day/s);
  });
  await check("the code cannot be redeemed a second time", async () => {
    const r = await token(COACH, { grant_type: "authorization_code", code: auth.code, code_verifier: auth.verifier,
      client_id: auth.info.client_id, redirect_uri: auth.redirectUrl });
    assert.equal(r.body.error, "invalid_grant");
  });

  const call = async (name, args = {}) => {
    const r = await client.callTool({ name, arguments: args });
    return { text: r.content[0].text, isError: r.isError === true, json: r.isError ? null : JSON.parse(r.content[0].text) };
  };

  console.log("coach-mcp-check: tools see only the signed-in runner");
  await check("get_profile: pat's plan, goals and baseline", async () => {
    const r = await call("get_profile", { today: TODAY });
    assert.equal(r.isError, false, r.text);
    assert.equal(r.json.plan.goals[0].type, "faster_mile");
    assert.ok(r.json.fitness, "fitness");
  });
  await check("get_plan: overview with today + days; a range; today defaults from the workout timezone", async () => {
    const r = await call("get_plan", {});
    assert.equal(r.isError, false, r.text);
    assert.equal(r.json.today, TODAY);
    assert.ok(r.json.days.length >= 7);
    assert.equal(r.json.today_day.local_date, TODAY);
    const range = await call("get_plan", { from: TODAY, to: addDays(TODAY, 3), today: TODAY });
    assert.equal(range.isError, false, range.text);
    assert.deepEqual(range.json.days.map((d) => d.local_date), [0, 1, 2, 3].map((n) => addDays(TODAY, n)));
  });
  await check("a `today` that can't be the runner's local date is refused", async () => {
    const r = await call("get_plan", { today: addDays(TODAY, -10) });
    assert.equal(r.isError, true);
    assert.match(r.text, /today must be the runner's local date/);
  });
  await check("get_runs: pat's runs with splits, never quinn's", async () => {
    const r = await call("get_runs", { from: addDays(TODAY, -30), to: TODAY });
    assert.equal(r.isError, false, r.text);
    const ids = r.json.runs.map((x) => x.workout_id);
    assert.deepEqual(ids.slice().sort(), runIds.pat.slice().sort());
    assert.ok(r.json.runs.some((x) => x.splits.length >= 2), "splits");
    for (const id of runIds.quinn) assert.ok(!r.text.includes(id), id);
  });
  await check("get_checkins: pat's, never quinn's", async () => {
    const r = await call("get_checkins", {});
    assert.equal(r.isError, false, r.text);
    assert.ok(r.text.includes("pat-note"));
    assert.ok(!r.text.includes("quinn-secret"));
  });

  console.log("coach-mcp-check: propose_change");
  const tryPropose = async () => {
    for (const action of ["easier", "harder", "shorter", "rest_tomorrow"]) {
      const r = await call("propose_change", { today: TODAY, action, summary: `check ${action}`, rationale: "coach-mcp-check" });
      if (!r.isError) return { action, ...r };
    }
    throw new Error("no action was possible on the seeded plan");
  };
  await check("by default a proposal is PENDING (source claude), and listed", async () => {
    const r = await tryPropose();
    assert.equal(r.json.applied, false);
    assert.equal(r.json.proposal.status, "pending");
    assert.equal(r.json.proposal.source, "claude");
    assert.ok(r.json.proposal.changes.length >= 1);
    const l = await call("list_proposals", { source: "claude" });
    assert.ok(l.json.proposals.some((p) => p.id === r.json.proposal.id));
  });
  await check("an impossible change → error with the engine's cap_note (422)", async () => {
    const r = await call("propose_change", { today: TODAY, action: "move", params: { from: TODAY, to: TODAY },
      summary: "x", rationale: "y" });
    assert.equal(r.isError, true);
    assert.match(r.text, /action_not_possible \(422\): Move needs two different days/);
  });
  await check("with claude_auto_apply on, the proposal is APPLIED at once", async () => {
    await S.updatePlan(people.pat.id, { claude_auto_apply: true }, TODAY);
    const r = await tryPropose();
    assert.equal(r.json.applied, true, r.text);
    assert.equal(r.json.proposal.status, "applied");
    const changed = r.json.proposal.changes[0].local_date;
    const day = (await S.getPlanDays(people.pat.id, changed, changed, TODAY))[0];
    assert.equal(day.source, "claude");
  });
  await check("every tool call is in the coach audit log (ok and error)", async () => {
    const rows = await q(`SELECT tool, outcome FROM coach_mcp_audit_log WHERE user_id = $1 AND outcome <> 'event'`, [people.pat.id]);
    assert.ok(rows.length >= 10, `${rows.length} rows`);
    assert.ok(rows.some((r) => r.tool === "propose_change" && r.outcome === "error"));
    assert.ok(rows.some((r) => r.tool === "propose_change" && r.outcome === "ok"));
    const ev = await q(`SELECT count(*)::int AS n FROM coach_mcp_audit_log WHERE user_id = $1 AND tool = 'sign_in'`, [people.pat.id]);
    assert.ok(ev[0].n >= 1);
  });
  await check("the app sees Claude connected, with last_used_at", async () => {
    const st = await coachConnectionStatus(people.pat.id);
    assert.equal(st.connected, true);
    assert.match(st.last_used_at ?? "", /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
    assert.deepEqual(await coachConnectionStatus(people.quinn.id), { connected: false, last_used_at: null });
    assert.equal((await S.getCurrentPlan(people.pat.id, TODAY)).claude.connected, true);
  });

  console.log("coach-mcp-check: who may sign in");
  const fresh = async () => {
    const id = (await (await register(COACH, ["http://localhost:2/cb"])).json()).client_id;
    return authorizeUrl(COACH, id, "http://localhost:2/cb", pkce().challenge);
  };
  await check("no Mile A Day+ → refused at sign-in", async () => {
    const s = await signIn(COACH, await fresh(), people.fran);
    assert.equal(s.res.status, 403);
    assert.match(await s.res.text(), /Mile A Day\+ required/);
  });
  await check("an Apple ID with no Mile A Day account → refused", async () => {
    assert.equal((await signIn(COACH, await fresh(), { sub: "001234.nobody.0000" })).res.status, 403);
  });
  await check("no browser cookie / wrong nonce / foreign signature → refused, request consumed", async () => {
    const a = await openAuthorize(await fresh());
    assert.equal((await postCallback(COACH, { request: a.request, idToken: await appleIdToken(people.pat.sub, a.nonce) })).status, 400);
    const b = await openAuthorize(await fresh());
    assert.equal((await postCallback(COACH, { request: b.request, idToken: await appleIdToken(people.pat.sub, "0".repeat(64)), cookie: b.cookie })).status, 401);
    assert.equal((await postCallback(COACH, { request: b.request, idToken: await appleIdToken(people.pat.sub, b.nonce), cookie: b.cookie })).status, 400, "consumed");
    const c = await openAuthorize(await fresh());
    const { privateKey: other } = await generateKeyPair("RS256");
    assert.equal((await postCallback(COACH, { request: c.request, idToken: await appleIdToken(people.pat.sub, c.nonce, other), cookie: c.cookie })).status, 401);
  });
  await check("authorize for the DB connector's resource, or an unregistered redirect → refused", async () => {
    const id = (await (await register(COACH, ["http://localhost:3/cb"])).json()).client_id;
    const other = await fetch(authorizeUrl(COACH, id, "http://localhost:3/cb", pkce().challenge, { resource: DB.mcp }), { redirect: "manual" });
    assert.equal(new URL(other.headers.get("location")).searchParams.get("error"), "invalid_target");
    const bad = await fetch(authorizeUrl(COACH, id, "http://localhost:3/other", pkce().challenge), { redirect: "manual" });
    assert.equal(bad.status, 400);
  });
  await check("claude.ai: the pre-registered coach client works only with ITS secret (post or Basic)", async () => {
    const CA = "https://claude.ai/api/mcp/auth_callback";
    const p = pkce();
    const a = await openAuthorize(authorizeUrl(COACH, COACH.claudeAi, CA, p.challenge));
    assert.equal(a.page.searchParams.get("to"), "claude.ai");
    const res = await postCallback(COACH, { request: a.request, idToken: await appleIdToken(people.quinn.sub, a.nonce), cookie: a.cookie });
    const code = new URL(res.headers.get("location")).searchParams.get("code");
    const base = { grant_type: "authorization_code", code, code_verifier: p.verifier, client_id: COACH.claudeAi };
    assert.equal((await token(COACH, base)).body.error, "invalid_client", "no secret");
    assert.equal((await token(COACH, { ...base, client_secret: DB_SECRET })).body.error, "invalid_client", "the DB connector's secret");
    const ok = await token(COACH, { ...base, client_secret: COACH_SECRET });
    assert.equal(ok.status, 200, JSON.stringify(ok.body));
    const basic = await token(COACH, { grant_type: "refresh_token", refresh_token: ok.body.refresh_token },
      { authorization: `Basic ${Buffer.from(`${COACH.claudeAi}:${COACH_SECRET}`).toString("base64")}` });
    assert.equal(basic.status, 200, JSON.stringify(basic.body));
    // The DB connector's claude.ai client id means nothing here.
    const a2 = await fetch(authorizeUrl(COACH, DB.claudeAi, CA, p.challenge), { redirect: "manual" });
    assert.equal(a2.status, 400);
  });

  console.log("coach-mcp-check: tokens over time");
  const q1 = await connect(COACH, people.quinn);
  await check("quinn's own token sees only quinn", async () => {
    const r = await tool(COACH.mcp, q1.access_token, "get_checkins");
    assert.ok(r.text.includes("quinn-secret") && !r.text.includes("pat-note"));
  });
  let q2;
  await check("two sessions refreshing the same token at the same instant both succeed", async () => {
    const [a, b] = await Promise.all([
      token(COACH, { grant_type: "refresh_token", refresh_token: q1.refresh_token, client_id: q1.clientId }),
      token(COACH, { grant_type: "refresh_token", refresh_token: q1.refresh_token, client_id: q1.clientId }),
    ]);
    assert.equal(a.status, 200, JSON.stringify(a.body));
    assert.equal(b.status, 200, JSON.stringify(b.body));
    q2 = a.body;
  });
  await check("a refresh token is bound to its client", async () => {
    const r = await token(COACH, { grant_type: "refresh_token", refresh_token: q2.refresh_token, client_id: auth.info.client_id });
    assert.equal(r.body.error, "invalid_grant");
  });
  await check("reuse after the grace window revokes the whole sign-in, and is audited", async () => {
    await q(`UPDATE coach_mcp_oauth_tokens SET used_at = now() - interval '2 minutes' WHERE used_at IS NOT NULL`);
    const r = await token(COACH, { grant_type: "refresh_token", refresh_token: q1.refresh_token, client_id: q1.clientId });
    assert.equal(r.body.error, "invalid_grant");
    assert.equal((await rpc(COACH.mcp, q2.access_token, "tools/list")).status, 401);
    assert.equal((await q(`SELECT count(*)::int AS n FROM coach_mcp_audit_log WHERE tool = 'refresh_reuse' AND user_id = $1`, [people.quinn.id]))[0].n, 1);
  });
  await check("revoking a token at /revoke ends that sign-in", async () => {
    const t = await connect(COACH, people.quinn);
    const res = await fetch(`${COACH.base}/revoke`, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ token: t.refresh_token, client_id: t.clientId }),
    });
    assert.equal(res.status, 200);
    assert.equal((await rpc(COACH.mcp, t.access_token, "tools/list")).status, 401);
  });
  await check("an expired access token → 401", async () => {
    const t = await connect(COACH, people.quinn);
    await q(`UPDATE coach_mcp_oauth_tokens SET expires_at = now() - interval '1 second' WHERE token_hash = $1`, [sha(t.access_token)]);
    assert.equal((await rpc(COACH.mcp, t.access_token, "tools/list")).status, 401);
  });

  console.log("coach-mcp-check: Mile A Day+ lapses");
  await check("lapse → every request refused, refresh refused AND the sign-in revoked; renewing doesn't revive it", async () => {
    await revokeCoachTokens(people.quinn.id); // only this sign-in left, so `connected` is about it
    const t = await connect(COACH, people.quinn);
    assert.equal((await rpc(COACH.mcp, t.access_token, "tools/list")).status, 200);
    assert.equal((await coachConnectionStatus(people.quinn.id)).connected, true);
    await setPlus(people.quinn, false);
    try {
      assert.equal((await rpc(COACH.mcp, t.access_token, "tools/list")).status, 401);
      const r = await token(COACH, { grant_type: "refresh_token", refresh_token: t.refresh_token, client_id: t.clientId });
      assert.equal(r.body.error, "invalid_grant");
      assert.equal((await coachConnectionStatus(people.quinn.id)).connected, false);
      assert.equal((await q(`SELECT count(*)::int AS n FROM coach_mcp_audit_log WHERE tool = 'plus_lapsed' AND user_id = $1`, [people.quinn.id]))[0].n, 1);
    } finally {
      await setPlus(people.quinn, true);
    }
    assert.equal((await rpc(COACH.mcp, t.access_token, "tools/list")).status, 401);
  });
  await check("lapse between sign-in and code redemption → no tokens", async () => {
    const clientId = (await (await register(COACH, ["http://localhost:4/cb"])).json()).client_id;
    const p = pkce();
    const s = await signIn(COACH, authorizeUrl(COACH, clientId, "http://localhost:4/cb", p.challenge), people.quinn);
    const code = new URL(s.res.headers.get("location")).searchParams.get("code");
    await setPlus(people.quinn, false);
    try {
      const r = await token(COACH, { grant_type: "authorization_code", code, code_verifier: p.verifier, client_id: clientId });
      assert.equal(r.body.error, "invalid_grant");
    } finally {
      await setPlus(people.quinn, true);
    }
  });

  console.log("coach-mcp-check: the two connectors never accept each other's tokens");
  const dbTok = await connect(DB, people.adm);
  const coachTok = await connect(COACH, people.adm);
  await check("both tokens are good where they belong", async () => {
    const d = await rpc(DB.mcp, dbTok.access_token, "tools/list");
    assert.equal(d.status, 200);
    assert.ok(d.body.result.tools.some((t) => t.name === "query"));
    const c = await rpc(COACH.mcp, coachTok.access_token, "tools/list");
    assert.equal(c.status, 200);
    assert.ok(!c.body.result.tools.some((t) => t.name === "query"));
  });
  await check("a coach token never opens /mcp DB tools", async () => {
    const r = await rpc(DB.mcp, coachTok.access_token, "tools/call", { name: "query", arguments: { sql: "select 1" } });
    assert.equal(r.status, 401);
    assert.equal((await rpc(DB.mcp, coachTok.access_token, "tools/list")).status, 401);
  });
  await check("a DB connector token never opens coach tools (via the website or the backend directly)", async () => {
    for (const url of [COACH.mcp, `${BACKEND}/coach/mcp`]) {
      assert.equal((await rpc(url, dbTok.access_token, "tools/call", { name: "get_runs", arguments: {} })).status, 401, url);
    }
  });
  await check("refresh tokens don't cross either: each token endpoint refuses the other's", async () => {
    for (const [as, t] of [[DB, coachTok], [COACH, dbTok]]) {
      const r = await token(as, { grant_type: "refresh_token", refresh_token: t.refresh_token, client_id: t.clientId });
      assert.ok(r.status >= 400 && !r.body.access_token, `${as.base}: ${r.status} ${JSON.stringify(r.body)}`);
    }
  });
  await check("an Apple sign-in parked at one connector can't be finished at the other", async () => {
    const id = (await (await register(COACH, ["http://localhost:5/cb"])).json()).client_id;
    const a = await openAuthorize(authorizeUrl(COACH, id, "http://localhost:5/cb", pkce().challenge));
    const r = await postCallback(DB, { request: a.request, idToken: await appleIdToken(people.adm.sub, a.nonce), cookie: a.cookie });
    assert.equal(r.status, 400);
  });

  console.log("coach-mcp-check: revoke from the app");
  await check("revokeCoachTokens ends every sign-in at once; last_used_at stays for the app", async () => {
    const extra = await connect(COACH, people.pat);
    const n = await revokeCoachTokens(people.pat.id);
    assert.ok(n >= 2, `${n} revoked`);
    assert.equal((await rpc(COACH.mcp, extra.access_token, "tools/list")).status, 401);
    const r = await client.callTool({ name: "get_plan", arguments: {} }).catch((e) => ({ thrown: e }));
    assert.ok(r.thrown || r.isError, "SDK client refused");
    const st = await coachConnectionStatus(people.pat.id);
    assert.equal(st.connected, false);
    assert.ok(st.last_used_at);
    assert.equal((await S.getCurrentPlan(people.pat.id, TODAY)).claude.connected, false);
    assert.equal(await revokeCoachTokens(people.pat.id), 0);
    // And the DB connector's sign-ins are not the coach's to revoke.
    assert.equal((await rpc(DB.mcp, dbTok.access_token, "tools/list")).status, 200);
  });
} finally {
  await closeMcpPools().catch(() => {});
  await q(`DELETE FROM coach_mcp_audit_log WHERE user_id = ANY($1) OR created_at >= $2`, [ourUsers, runStart]).catch(() => {});
  await q(`DELETE FROM mcp_audit_log WHERE created_at >= $1`, [runStart]).catch(() => {});
  await q(`DELETE FROM coach_mcp_oauth_clients WHERE created_at >= $1`, [runStart]).catch(() => {});
  await q(`DELETE FROM mcp_oauth_clients WHERE created_at >= $1`, [runStart]).catch(() => {});
  await q(`DELETE FROM coach_mcp_oauth_requests WHERE expires_at >= $1`, [runStart]).catch(() => {});
  await q(`DELETE FROM coach_mcp_oauth_codes WHERE user_id = ANY($1)`, [ourUsers]).catch(() => {});
  await q(`DELETE FROM mcp_oauth_requests WHERE expires_at >= $1`, [runStart]).catch(() => {});
  await q(`DELETE FROM mcp_oauth_codes WHERE user_id = ANY($1)`, [ourUsers]).catch(() => {});
  await q(`DELETE FROM run_plans WHERE user_id = ANY($1)`, [ourUsers]).catch((e) => console.log(`  (cleanup: ${e.message})`));
  await q(`DELETE FROM plus_purchases WHERE user_id = ANY($1)`, [ourUsers]).catch(() => {});
  await q(`DELETE FROM workouts WHERE user_id = ANY($1)`, [ourUsers]).catch(() => {});
  // Grants and tokens go with the users (ON DELETE CASCADE).
  await q(`DELETE FROM users WHERE user_id = ANY($1)`, [ourUsers]).catch((e) => console.log(`  (cleanup: ${e.message})`));
  backend.s.close();
  website.s.close();
  await admin.end();
  await PostgresService.getInstance().close?.();
}

console.log(failures ? `coach-mcp-check: ${failures} FAILED` : "coach-mcp-check: all passed");
process.exit(failures ? 1 : 0);
