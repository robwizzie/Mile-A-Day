/**
 * Account deletion check — Apple token revocation and what deletion clears.
 *
 * Every failure here is silent: a token never revoked, or a log row left behind
 * after "delete my account", answers 200 like a success. Apple is stubbed at
 * `fetch`, so the real controllers run against a real database. Pinned:
 *   - sign-in stores the refresh token encrypted, and refuses another account's
 *   - Apple down or misconfigured never fails a sign-in or a deletion
 *   - a failed revocation queues without a user id and the sweep finishes it
 *   - retries are bounded, and waiting on config doesn't use them up
 *   - an account with no stored token: not_available alone, revoked with a code
 *   - the response stays all strings (shipped clients decode [String: String])
 *   - deletion clears the logs by id, Apple id and email; other people's stay
 *   - a failed sign-in logs no email
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/apple-revocation-check.mjs
 */
import crypto from "node:crypto";
import { SignJWT, exportJWK, exportPKCS8, generateKeyPair, decodeJwt, decodeProtectedHeader } from "jose";

const { privateKey, publicKey } = await generateKeyPair("ES256", { extractable: true });
const rsa = await generateKeyPair("RS256", { extractable: true });
const CLIENT = "org.example.apple-check";

process.env.APP_JWT_SECRET ||= "apple-check-secret";
process.env.APPLE_CLIENT_ID = CLIENT;
const CONFIG = {
  APPLE_TEAM_ID: "TEAM123456",
  APPLE_SIGNIN_KEY_ID: "KEY1234567",
  APPLE_SIGNIN_KEY: await exportPKCS8(privateKey),
  APPLE_TOKEN_ENCRYPTION_KEY: crypto.randomBytes(32).toString("base64"),
};
const configure = (on) => {
  for (const [k, v] of Object.entries(CONFIG)) {
    if (on) process.env[k] = v;
    else delete process.env[k];
  }
};
configure(true);

const { PostgresService } = await import("../dist/services/DbService.js");
const { signIn } = await import("../dist/controllers/authController.js");
const { deleteUser } = await import("../dist/controllers/usersController.js");
const { sweepAppleRevocations, MAX_REVOCATION_ATTEMPTS } = await import(
  "../dist/services/appleSignInTokenService.js"
);

const db = PostgresService.getInstance();
let failures = 0;
function check(label, actual, expected) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(`${ok ? "ok  " : "FAIL"}  ${label} → ${actual} (expected ${expected})`);
}

// ── Apple ────────────────────────────────────────────────────────────────
const jwk = { ...(await exportJWK(rsa.publicKey)), kid: "apple-check", alg: "RS256", use: "sig" };
const apple = { down: false, revokeStatus: 200, revokeError: null, tokenSub: null, calls: [] };
const realFetch = globalThis.fetch;
const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

globalThis.fetch = async (url, init) => {
  const u = String(url);
  if (!u.startsWith("https://appleid.apple.com")) return realFetch(url, init);
  if (u.endsWith("/auth/keys")) return json({ keys: [jwk] });
  if (apple.down) throw new TypeError("fetch failed");
  const form = Object.fromEntries(new URLSearchParams(init.body));
  apple.calls.push({ path: new URL(u).pathname, form });
  if (u.endsWith("/auth/token")) {
    if (form.code === "bad-code") return json({ error: "invalid_grant" }, 400);
    const id_token = await new SignJWT({})
      .setProtectedHeader({ alg: "RS256" })
      .setSubject(apple.tokenSub)
      .sign(rsa.privateKey);
    return json({ refresh_token: `apple-refresh-${form.code}`, id_token });
  }
  if (apple.revokeStatus === 200) return new Response("", { status: 200 });
  return json({ error: apple.revokeError }, apple.revokeStatus);
};

const identityToken = (sub, email) =>
  new SignJWT({ email })
    .setProtectedHeader({ alg: "RS256", kid: "apple-check" })
    .setIssuer("https://appleid.apple.com")
    .setAudience(CLIENT)
    .setSubject(sub)
    .setIssuedAt()
    .setExpirationTime("5m")
    .sign(rsa.privateKey);

// ── Harness ──────────────────────────────────────────────────────────────
function call(handler, req) {
  return new Promise((resolve, reject) => {
    const res = {
      statusCode: 200,
      status(c) { this.statusCode = c; return this; },
      json(body) { resolve({ status: this.statusCode, body }); return this; },
      send(body) { resolve({ status: this.statusCode, body }); return this; },
    };
    Promise.resolve(
      handler({ headers: {}, ip: "127.0.0.1", query: {}, params: {}, ...req }, res),
    ).catch(reject);
  });
}
const del = (userId, body) => call(deleteUser, { params: { userId }, body });
const sign = (sub, email, code = "code-1") =>
  identityToken(sub, email).then((identity_token) =>
    call(signIn, { body: { user_id: sub, identity_token, authorization_code: code, email } }),
  );
const settle = async (test) => {
  for (let i = 0; i < 100 && !(await test()); i++) await new Promise((r) => setTimeout(r, 10));
};

const count = async (sql, params = []) => Number((await db.query(`SELECT count(*)::int AS n FROM ${sql}`, params))[0].n);
const SUBS = ["apl-sub-a", "apl-sub-b", "apl-sub-c", "apl-sub-d", "apl-sub-e"];
const EMAILS = SUBS.map((s) => `${s}@apple-check.test`);
const OTHER = "apl-bystander";
const pending = () => count("apple_token_revocations WHERE client_id = $1", [CLIENT]);
const tokenRow = async (userId) =>
  (await db.query("SELECT * FROM apple_sign_in_tokens WHERE user_id = $1", [userId]))[0];
const seed = async (id, sub) =>
  db.query("INSERT INTO users (user_id, email, apple_sub) VALUES ($1, $2, $3)", [id, `${sub}@apple-check.test`, sub]);

async function cleanup() {
  const rows = await db.query("SELECT user_id FROM users WHERE apple_sub = ANY($1) OR user_id = $2", [SUBS, OTHER]);
  const ids = rows.map((r) => r.user_id);
  await db.query("DELETE FROM apple_token_revocations WHERE client_id = $1", [CLIENT]);
  await db.query("DELETE FROM error_log WHERE user_id = ANY($1::text[]) OR context->>'email' = ANY($2) OR message LIKE 'Apple %'", [[...ids, ...SUBS], EMAILS]);
  for (const t of ["feature_events", "weekly_recap_log", "refresh_tokens"]) await db.query(`DELETE FROM ${t} WHERE user_id = ANY($1::text[])`, [ids]);
  for (const t of ["friend_request_log", "photo_ask_log"]) await db.query(`DELETE FROM ${t} WHERE sender_id = ANY($1::text[]) OR target_id = ANY($1::text[])`, [ids]);
  await db.query("DELETE FROM hype_notify_log WHERE sender_id = ANY($1::text[]) OR recipient_id = ANY($1::text[])", [ids]);
  await db.query("DELETE FROM close_friends WHERE user_id = ANY($1::text[]) OR close_friend_id = ANY($1::text[])", [ids]);
  await db.query("DELETE FROM users WHERE user_id = ANY($1::text[])", [ids]);
}

async function main() {
  await cleanup();
  const uid = async (sub) => (await db.query("SELECT user_id FROM users WHERE apple_sub = $1", [sub]))[0]?.user_id;

  // ── Sign-in ────────────────────────────────────────────────────────────
  apple.tokenSub = SUBS[0];
  const first = await sign(SUBS[0], EMAILS[0], "code-a");
  check("sign-in succeeds", first.status, 200);
  const a = first.body.user.user_id;
  await settle(() => tokenRow(a));
  const stored = await tokenRow(a);
  check("refresh token stored", Boolean(stored), true);
  check("…encrypted", stored.encrypted_refresh_token.includes("apple-refresh"), false);
  check("…against the app's client id", stored.client_id, CLIENT);
  const secret = apple.calls[0].form.client_secret;
  check("client secret is ES256 with our key id", decodeProtectedHeader(secret).kid, CONFIG.APPLE_SIGNIN_KEY_ID);
  check("…issued by the team", decodeJwt(secret).iss, CONFIG.APPLE_TEAM_ID);
  check("…for the app", decodeJwt(secret).sub, CLIENT);
  check("…to Apple", decodeJwt(secret).aud, "https://appleid.apple.com");
  check("no token column reaches the user object", JSON.stringify(first.body).includes("apple-refresh"), false);

  apple.tokenSub = "someone-else";
  const foreign = await sign(SUBS[1], EMAILS[1], "code-foreign");
  const b = foreign.body.user.user_id;
  await settle(async () => (await count("error_log WHERE user_id = $1 AND message LIKE 'Apple code%'", [b])) > 0);
  check("another Apple account's code is not stored", Boolean(await tokenRow(b)), false);

  apple.down = true;
  check("Apple down: sign-in still succeeds", (await sign(SUBS[2], EMAILS[2])).status, 200);
  apple.down = false;
  configure(false);
  check("not configured: sign-in still succeeds", (await sign(SUBS[3], EMAILS[3])).status, 200);
  check("not configured: nothing stored", Boolean(await tokenRow(await uid(SUBS[3]))), false);
  configure(true);

  const failed = await call(signIn, {
    body: { user_id: SUBS[4], identity_token: "not-a-jwt", authorization_code: "x", email: EMAILS[4] },
  });
  check("bad identity token is refused", failed.status, 401);
  await settle(async () => (await count("error_log WHERE user_id = $1", [SUBS[4]])) > 0);
  const [logged] = await db.query("SELECT context FROM error_log WHERE user_id = $1", [SUBS[4]]);
  check("failed sign-in logs no email", JSON.stringify(logged.context).includes("@"), false);
  check("…and says whether one was sent", logged.context.has_email, true);

  // ── Deletion clears the logs ───────────────────────────────────────────
  await seed(OTHER, "apl-bystander-sub");
  const pairs = [[a, OTHER], [OTHER, a]];
  for (const [s, t] of pairs) {
    await db.query("INSERT INTO friend_request_log (sender_id, target_id) VALUES ($1, $2)", [s, t]);
    await db.query("INSERT INTO photo_ask_log (sender_id, target_id) VALUES ($1, $2)", [s, t]);
    await db.query("INSERT INTO hype_notify_log (sender_id, recipient_id, context_type, context_id) VALUES ($1, $2, 'post', 'apl')", [s, t]);
    await db.query("INSERT INTO close_friends (user_id, close_friend_id) VALUES ($1, $2)", [s, t]);
  }
  for (const u of [a, OTHER]) {
    await db.query("INSERT INTO feature_events (user_id, feature) VALUES ($1, 'apl')", [u]);
    await db.query("INSERT INTO weekly_recap_log (user_id, week_start) VALUES ($1, '2026-01-05')", [u]);
    await db.query("INSERT INTO error_log (category, user_id, message) VALUES ('api', $1, 'x')", [u]);
  }
  // The shape failed sign-ins left before this: Apple id + raw email.
  await db.query(`INSERT INTO error_log (category, user_id, message, context) VALUES ('auth', $1, 'old', $2)`, [SUBS[0], { email: EMAILS[0] }]);
  await db.query(`INSERT INTO error_log (category, user_id, message, context) VALUES ('auth', NULL, 'old', $1)`, [{ email: EMAILS[0] }]);
  await db.query(`INSERT INTO error_log (category, user_id, message, context) VALUES ('auth', NULL, 'blank', $1)`, [{ email: "" }]);

  // ── Apple down at deletion ─────────────────────────────────────────────
  apple.down = true;
  const down = await del(a);
  check("Apple down: deletion succeeds", down.status, 200);
  check("…reports pending", down.body.apple_revocation, "pending");
  check("…the account is gone", await count("users WHERE user_id = $1", [a]), 0);
  check("…the token left the account", Boolean(await tokenRow(a)), false);
  check("…and is queued", await pending(), 1);
  check("queue row has no user id column", "user_id" in (await db.query("SELECT * FROM apple_token_revocations WHERE client_id = $1", [CLIENT]))[0], false);

  for (const [t, where] of [
    ["friend_request_log", "sender_id = $1 OR target_id = $1"],
    ["photo_ask_log", "sender_id = $1 OR target_id = $1"],
    ["hype_notify_log", "sender_id = $1 OR recipient_id = $1"],
    ["close_friends", "user_id = $1 OR close_friend_id = $1"],
    ["feature_events", "user_id = $1"],
    ["weekly_recap_log", "user_id = $1"],
    ["error_log", "user_id = $1"],
  ]) check(`${t} cleared`, await count(`${t} WHERE ${where}`, [a]), 0);
  check("error_log cleared by Apple id", await count("error_log WHERE user_id = $1", [SUBS[0]]), 0);
  check("error_log cleared by email", await count("error_log WHERE context->>'email' = $1", [EMAILS[0]]), 0);
  check("a blank email matches nobody", await count("error_log WHERE message = 'blank'"), 1);
  await db.query("DELETE FROM error_log WHERE message = 'blank'");
  check("bystander keeps their rows", await count("error_log WHERE user_id = $1", [OTHER]) + await count("feature_events WHERE user_id = $1", [OTHER]) + await count("weekly_recap_log WHERE user_id = $1", [OTHER]), 3);

  // ── The sweep ──────────────────────────────────────────────────────────
  await sweepAppleRevocations();
  check("not due yet: left alone", (await db.query("SELECT attempts FROM apple_token_revocations WHERE client_id = $1", [CLIENT]))[0].attempts, 1);
  await db.query("UPDATE apple_token_revocations SET next_attempt_at = now() - interval '1 minute' WHERE client_id = $1", [CLIENT]);
  configure(false);
  await sweepAppleRevocations();
  check("not configured: attempts not spent", (await db.query("SELECT attempts FROM apple_token_revocations WHERE client_id = $1", [CLIENT]))[0].attempts, 1);
  configure(true);
  apple.down = false;
  apple.calls = [];
  await sweepAppleRevocations();
  check("sweep revokes the queued token", await pending(), 0);
  const revoke = apple.calls.find((c) => c.path === "/auth/revoke")?.form ?? {};
  check("…the decrypted refresh token", revoke.token, "apple-refresh-code-a");
  check("…hinted as a refresh token", revoke.token_type_hint, "refresh_token");
  check("…for the client it was issued to", revoke.client_id, CLIENT);

  // ── Apple answers at deletion ──────────────────────────────────────────
  apple.tokenSub = SUBS[0];
  const again = await sign(SUBS[0], EMAILS[0], "code-b");
  await settle(() => tokenRow(again.body.user.user_id));
  const ok = await del(again.body.user.user_id);
  check("Apple up: revoked at once", ok.body.apple_revocation, "revoked");
  check("…nothing left queued", await pending(), 0);

  // ── Accounts with no stored token ──────────────────────────────────────
  await seed("apl-legacy-1", SUBS[4]);
  const legacy = await del("apl-legacy-1");
  check("no token, no code: still deleted", legacy.status, 200);
  check("…reported as not_available", legacy.body.apple_revocation, "not_available");
  check("…response stays all strings", Object.values(legacy.body).every((v) => typeof v === "string"), true);

  await seed("apl-legacy-2", SUBS[4]);
  apple.tokenSub = SUBS[4];
  check("fresh code at deletion: revoked", (await del("apl-legacy-2", { authorization_code: "late" })).body.apple_revocation, "revoked");

  await seed("apl-legacy-3", SUBS[4]);
  apple.tokenSub = "someone-else";
  const wrong = await del("apl-legacy-3", { authorization_code: "late" });
  check("another account's code: still deleted", wrong.status, 200);
  check("…revokes nothing", wrong.body.apple_revocation, "not_available");

  await seed("apl-legacy-4", SUBS[4]);
  apple.tokenSub = SUBS[4];
  const badCode = await del("apl-legacy-4", { authorization_code: "bad-code" });
  check("rejected code: still deleted", badCode.status, 200);
  check("…reported as not_available", badCode.body.apple_revocation, "not_available");

  // ── Apple refusing ─────────────────────────────────────────────────────
  const withToken = async (id, code) => {
    await seed(id, SUBS[4]);
    return del(id, { authorization_code: code });
  };
  apple.revokeStatus = 400;
  apple.revokeError = "invalid_grant";
  check("invalid_grant ends the retries", (await withToken("apl-dead", "dead")).body.apple_revocation, "revoked");
  check("…nothing left queued", await pending(), 0);

  apple.revokeStatus = 500;
  apple.revokeError = "server_error";
  check("5xx stays pending", (await withToken("apl-retry", "retry")).body.apple_revocation, "pending");
  await db.query(`UPDATE apple_token_revocations SET attempts = $2 - 1, next_attempt_at = now() - interval '1 minute' WHERE client_id = $1`, [CLIENT, MAX_REVOCATION_ATTEMPTS]);
  await sweepAppleRevocations();
  check("the last failed attempt drops the token", await pending(), 0);
  check("…and says so", await count("error_log WHERE message = 'Apple token revocation abandoned'"), 1);
  apple.revokeStatus = 200;

  // ── The tables ─────────────────────────────────────────────────────────
  const rls = await db.query(`SELECT relname FROM pg_class WHERE relname IN ('apple_sign_in_tokens', 'apple_token_revocations') AND relrowsecurity`);
  check("both token tables have RLS on", rls.length, 2);
  const cols = await db.query(`SELECT 1 FROM information_schema.columns WHERE table_name = 'users' AND column_name LIKE '%refresh%'`);
  check("no token column on users", cols.length, 0);

  await cleanup();
}

try {
  await main();
} catch (err) {
  failures++;
  console.error("FAIL  threw:", err);
  await cleanup().catch(() => {});
}
await db.close();
globalThis.fetch = realFetch;
console.log(failures ? `\n${failures} check(s) failed` : "\nall checks passed");
process.exit(failures ? 1 : 0);
