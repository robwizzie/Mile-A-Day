// HTTP rate-limit check. The failures worth pinning here are not "abuse got
// through" but the two that hurt real users silently:
//   - one bucket for everyone (a proxy/Cloudflare address used as the key), and
//   - a 429 from /auth/refresh, which signs every shipped build out — so the
//     refresh bucket must be separate from sign-in and far more generous.
// Drives the REAL limiter middleware over a stub app on an ephemeral port
// (the limiters never touch the DB), then asserts the real routers carry them.
//
// Usage: npm run build && node scripts/rate-limit-check.mjs
import assert from "node:assert/strict";
import express from "express";

process.env.TRUST_PROXY_HOPS = "1";
delete process.env.RATE_LIMITS_DISABLED;

const rl = await import("../dist/middleware/rateLimit.js");
const {
  configureTrustProxy,
  signInLimiter,
  sessionLimiter,
  uploadLimiter,
  postCreateLimiter,
  commentLimiter,
  reportLimiter,
  globalUserLimiter,
  RATE_LIMIT_SPECS,
} = rl;

const SIGNIN_MAX = RATE_LIMIT_SPECS.signin.max;
const SESSION_MAX = RATE_LIMIT_SPECS.session.max;
const UPLOAD_MAX = RATE_LIMIT_SPECS.upload.max;

// ---------------------------------------------------------------------------
// Stub app: same trust-proxy setup as server.ts, the auth middleware replaced
// by a header so a test can be any user.
// ---------------------------------------------------------------------------
const app = express();
assert.equal(configureTrustProxy(app), 1, "TRUST_PROXY_HOPS=1 is honoured");
app.use((req, _res, next) => {
  const u = req.headers["x-test-user"];
  if (u) req.userId = String(u);
  next();
});
const ok = (_req, res) => res.json({ ok: true });
app.post("/signin", signInLimiter, ok);
app.post("/refresh", sessionLimiter, ok);
app.post("/upload", uploadLimiter, ok);

const server = await new Promise((resolve) => {
  const s = app.listen(0, "127.0.0.1", () => resolve(s));
});
const base = `http://127.0.0.1:${server.address().port}`;

/** `xff` is what the (simulated) reverse proxy appended; `cf` is CF-Connecting-IP. */
async function hit(path, { xff, cf, user } = {}) {
  const headers = { "content-type": "application/json" };
  if (xff) headers["x-forwarded-for"] = xff;
  if (cf) headers["cf-connecting-ip"] = cf;
  if (user) headers["x-test-user"] = user;
  const res = await fetch(base + path, { method: "POST", headers, body: "{}" });
  const body = await res.json().catch(() => null);
  return { status: res.status, headers: res.headers, body };
}

async function burst(n, path, opts) {
  const statuses = [];
  for (let i = 0; i < n; i++) statuses.push((await hit(path, opts)).status);
  return statuses;
}

let failures = 0;
async function section(name, fn) {
  try {
    await fn();
    console.log(`  ok  ${name}`);
  } catch (err) {
    failures++;
    console.error(`  FAIL ${name}\n       ${err?.message ?? err}`);
  }
}

console.log("rate-limit-check");

// 1. Sign-in trips after N per client IP, with the documented 429 shape.
const CLIENT_A = "203.0.113.5";
await section(`sign-in allows ${SIGNIN_MAX}, then 429s`, async () => {
  const statuses = await burst(SIGNIN_MAX, "/signin", { xff: CLIENT_A });
  assert.ok(statuses.every((s) => s === 200), `first ${SIGNIN_MAX}: ${statuses}`);
  const blocked = await hit("/signin", { xff: CLIENT_A });
  assert.equal(blocked.status, 429);
  // Shipped clients show `error` to the user: it must be a sentence.
  assert.equal(typeof blocked.body.error, "string");
  assert.ok(blocked.body.error.length > 10 && !/_/.test(blocked.body.error));
  assert.equal(blocked.body.code, "rate_limited");
  // STRING-valued throughout: some client paths decode [String: String].
  for (const [k, v] of Object.entries(blocked.body)) {
    assert.equal(typeof v, "string", `${k} must be a string`);
  }
  assert.match(blocked.body.retry_after_seconds, /^\d+$/);
  assert.ok(Number(blocked.body.retry_after_seconds) > 0);
  assert.match(blocked.headers.get("retry-after") ?? "", /^\d+$/);
  assert.equal(blocked.headers.get("ratelimit-limit"), String(SIGNIN_MAX));
  assert.equal(blocked.headers.get("ratelimit-remaining"), "0");
});

await section("sign-in bucket is per client IP (another IP unaffected)", async () => {
  assert.equal((await hit("/signin", { xff: "198.51.100.7" })).status, 200);
});

// 2. Refresh is its OWN bucket and more generous. A shipped client that gets
// any non-200 from /auth/refresh signs the user out.
await section("refresh is separate from sign-in and more generous", async () => {
  assert.ok(
    SESSION_MAX >= 10 * SIGNIN_MAX,
    `session max ${SESSION_MAX} should dwarf sign-in max ${SIGNIN_MAX}`,
  );
  // Same IP that is locked out of sign-in right now:
  const statuses = await burst(SIGNIN_MAX * 3, "/refresh", { xff: CLIENT_A });
  assert.ok(statuses.every((s) => s === 200), `refresh from a signin-locked IP: ${statuses}`);
  const r = await hit("/refresh", { xff: CLIENT_A });
  assert.equal(r.headers.get("ratelimit-limit"), String(SESSION_MAX));
});

await section("refresh does eventually trip (bounded, not unlimited)", async () => {
  process.env.RATE_LIMIT_SESSION_MAX = "5";
  try {
    const statuses = await burst(6, "/refresh", { xff: "192.0.2.200" });
    assert.deepEqual(statuses, [200, 200, 200, 200, 200, 429]);
  } finally {
    delete process.env.RATE_LIMIT_SESSION_MAX;
  }
});

// 3. Upload limiter is per USER: B on the same address is unaffected by A.
await section(`upload is per user (A trips at ${UPLOAD_MAX}, B on same IP fine)`, async () => {
  const opts = { xff: "198.51.100.50", user: "rl-user-a" };
  const statuses = await burst(UPLOAD_MAX, "/upload", opts);
  assert.ok(statuses.every((s) => s === 200), `A's first ${UPLOAD_MAX}: ${statuses}`);
  assert.equal((await hit("/upload", opts)).status, 429, "A blocked");
  assert.equal(
    (await hit("/upload", { xff: "198.51.100.50", user: "rl-user-b" })).status,
    200,
    "B unaffected",
  );
  // A changing networks doesn't reset A's bucket (it's keyed on the user).
  assert.equal(
    (await hit("/upload", { xff: "192.0.2.77", user: "rl-user-a" })).status,
    429,
    "A still blocked from another IP",
  );
});

// 4. Degrade SAFELY: a private/loopback peer with no client header is our own
// proxy seen from the wrong hop — never a key, so never a global lock.
await section("private peer with no CF header is skipped, not pooled", async () => {
  const statuses = await burst(SIGNIN_MAX * 2, "/signin", { xff: "10.0.0.5" });
  assert.ok(statuses.every((s) => s === 200), `private peer: ${statuses}`);
  const r = await hit("/signin", { xff: "10.0.0.5" });
  assert.equal(r.headers.get("ratelimit-limit"), null, "skipped requests carry no headers");
  // The raw socket peer (loopback, no XFF at all) likewise.
  const direct = await burst(SIGNIN_MAX + 1, "/signin", {});
  assert.ok(direct.every((s) => s === 200), `loopback peer: ${direct}`);
});

// 5. Cloudflare in front: the edge IP is shared by everyone behind that PoP,
// so it is never a key; CF-Connecting-IP is.
const CF_EDGE = "173.245.48.1";
await section("behind Cloudflare, keyed on CF-Connecting-IP not the edge", async () => {
  const statuses = await burst(SIGNIN_MAX, "/signin", { xff: CF_EDGE, cf: "192.0.2.44" });
  assert.ok(statuses.every((s) => s === 200), statuses.join());
  assert.equal((await hit("/signin", { xff: CF_EDGE, cf: "192.0.2.44" })).status, 429);
  // A different user through the SAME edge node is unaffected.
  assert.equal((await hit("/signin", { xff: CF_EDGE, cf: "192.0.2.45" })).status, 200);
  // An edge request with no client header can't be attributed: skipped.
  const bare = await burst(SIGNIN_MAX + 1, "/signin", { xff: CF_EDGE });
  assert.ok(bare.every((s) => s === 200), `edge without CF header: ${bare}`);
});

await section("private proxy (e.g. cloudflared) forwarding CF-Connecting-IP is honoured", async () => {
  await burst(SIGNIN_MAX, "/signin", { xff: "172.18.0.3", cf: "192.0.2.60" });
  assert.equal((await hit("/signin", { xff: "172.18.0.3", cf: "192.0.2.60" })).status, 429);
});

// 6. Spoofing: a request that reached the origin directly (peer is a public,
// non-Cloudflare address) cannot choose its bucket with headers.
await section("direct-to-origin can't rotate buckets via CF-Connecting-IP", async () => {
  const peer = "203.0.113.99";
  for (let i = 0; i < SIGNIN_MAX; i++) {
    assert.equal((await hit("/signin", { xff: peer, cf: `192.0.2.${i + 1}` })).status, 200);
  }
  assert.equal((await hit("/signin", { xff: peer, cf: "192.0.2.250" })).status, 429);
});

await section("client-written X-Forwarded-For entries are not trusted (hop count)", async () => {
  // The proxy APPENDS the real peer; everything left of it is client-written.
  const peer = "203.0.113.77";
  for (let i = 0; i < SIGNIN_MAX; i++) {
    assert.equal((await hit("/signin", { xff: `1.2.3.${i}, ${peer}` })).status, 200);
  }
  assert.equal((await hit("/signin", { xff: `9.9.9.9, ${peer}` })).status, 429);
});

// 7. Kill switch: read per request, no restart needed.
await section("RATE_LIMITS_DISABLED=1 disables every limiter", async () => {
  assert.equal((await hit("/signin", { xff: CLIENT_A })).status, 429, "precondition");
  process.env.RATE_LIMITS_DISABLED = "1";
  try {
    assert.equal((await hit("/signin", { xff: CLIENT_A })).status, 200);
    assert.equal(
      (await hit("/upload", { xff: "198.51.100.50", user: "rl-user-a" })).status,
      200,
    );
  } finally {
    delete process.env.RATE_LIMITS_DISABLED;
  }
  assert.equal((await hit("/signin", { xff: CLIENT_A })).status, 429, "re-enabled");
});

server.close();

// 8. Wiring: the real routers carry the limiters on the right routes, in
// front of multer (a rejected upload must not be buffered first).
function routeHandles(router, method, path) {
  const layer = router.stack.find(
    (l) => l.route && l.route.path === path && l.route.methods?.[method],
  );
  assert.ok(layer, `route ${method.toUpperCase()} ${path} exists`);
  return layer.route.stack.map((l) => l.handle);
}
function assertLimited(router, method, path, limiter, label) {
  const handles = routeHandles(router, method, path);
  const i = handles.indexOf(limiter);
  assert.ok(i >= 0, `${method.toUpperCase()} ${path} carries the ${label} limiter`);
  return { handles, i };
}

await section("real routes carry their limiters", async () => {
  const { default: authRoutes } = await import("../dist/routes/authRoutes.js");
  assertLimited(authRoutes, "post", "/signin", signInLimiter, "sign-in");
  assertLimited(authRoutes, "post", "/refresh", sessionLimiter, "session");
  assertLimited(authRoutes, "post", "/logout", sessionLimiter, "session");
  assert.ok(
    !routeHandles(authRoutes, "post", "/refresh").includes(signInLimiter),
    "refresh must not share the sign-in bucket",
  );

  const { adminAuthRouter } = await import("../dist/routes/adminRoutes.js");
  assertLimited(adminAuthRouter, "post", "/apple", signInLimiter, "sign-in");

  const { default: posts } = await import("../dist/routes/postsRoutes.js");
  const media = assertLimited(posts, "post", "/media", uploadLimiter, "upload");
  assert.equal(media.i, 0, "upload limiter runs before multer");
  assertLimited(posts, "post", "/", postCreateLimiter, "post-create");
  assertLimited(posts, "put", "/:postId/crew-photo", postCreateLimiter, "post-create");
  assertLimited(posts, "post", "/:postId/comments", commentLimiter, "comment");
  assertLimited(posts, "post", "/workouts/:workoutId/comments", commentLimiter, "comment");
  assertLimited(posts, "post", "/:postId/report", reportLimiter, "report");
  assertLimited(posts, "post", "/comments/:commentId/report", reportLimiter, "report");

  const { default: users } = await import("../dist/routes/usersRoutes.js");
  for (const p of ["/:userId/profile-image/upload", "/:userId/banner/upload"]) {
    const { handles, i } = assertLimited(users, "post", p, uploadLimiter, "upload");
    assert.equal(i, handles.length - 3, `${p}: limiter sits right before multer`);
  }

  // The backstop must sit far above a first-run import (50-workout batches
  // back to back) — a user's own history import must never trip it.
  assert.ok(RATE_LIMIT_SPECS.global.max >= 1000, "global backstop is generous");
  assert.equal(typeof globalUserLimiter, "function");
});

if (failures > 0) {
  console.error(`rate-limit-check: ${failures} section(s) failed`);
  process.exit(1);
}
console.log("rate-limit-check: all sections passed");
process.exit(0);
