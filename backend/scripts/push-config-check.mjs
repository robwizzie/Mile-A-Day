/**
 * Push configuration + device-token pruning checks.
 *
 * Both halves guard failures that only reproduce in production, where there's
 * no shell to inspect anything and every guess costs a deploy.
 *
 * No DB, no network — both functions are pure.
 *
 * Usage: node scripts/push-config-check.mjs
 */
import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import jwt from "jsonwebtoken";
import {
  isCapExempt,
  isDeadToken,
  toPem,
} from "../dist/services/pushNotificationService.js";

/* ── Part 1: APNS_KEY normalization ───────────────────────────────────
 *
 * `toPem` has to accept every shape an env var arrives in when it's pasted
 * into a hosting dashboard. It once stripped whitespace BEFORE the PEM armour,
 * so the space-containing markers stopped matching and a full `.p8` paste got
 * re-wrapped with its own armour nested inside. jsonwebtoken reported that as
 * "secretOrPrivateKey must be an asymmetric key when using ES256", which sent
 * a whole APNs key rotation down the wrong path for a day.
 *
 * Signing for real is the assertion — a string that merely LOOKS like PEM is
 * exactly what shipped last time.
 */
const { privateKey } = generateKeyPairSync("ec", {
  namedCurve: "prime256v1", // same curve as an Apple .p8
  privateKeyEncoding: { type: "pkcs8", format: "pem" },
});
const bodyOnly = privateKey.replace(/-----[^-]+-----/g, "").trim();

for (const [shape, value] of [
  ["whole .p8 file, real newlines", privateKey],
  ["base64 body only", bodyOnly],
  ["literal \\n escapes", privateKey.replace(/\n/g, "\\n")],
  ["body with stray indentation", `  ${bodyOnly.replace(/\n/g, "\n\t")}  `],
  ["trailing newline + spaces", `${privateKey}\n  `],
]) {
  assert.doesNotThrow(
    () =>
      jwt.sign({}, toPem(value), {
        algorithm: "ES256",
        keyid: "ABC1234567",
        issuer: "TEAM123456",
        expiresIn: "1h",
      }),
    `APNS_KEY pasted as "${shape}" must produce a signable ES256 key`,
  );
}

/* ── Part 2: device-token pruning ─────────────────────────────────────
 *
 * `isDeadToken` decides whether an APNs rejection deletes a row from
 * device_tokens. Get it wrong in the permissive direction and a server-side
 * misconfig silently wipes real users' push tokens — permanently, since the
 * only thing that puts them back is the user opening the app. That already
 * nearly happened: a production-restricted APNs key made every send to the
 * sandbox host fail, and had those failures been 400s under a status-code-only
 * rule, every dev token would have been deleted on the first fan-out.
 *
 * So the rule is reason-string-based, and these assertions pin it: the two
 * shapes that mean "this token is dead" prune, and every shape that means
 * "the SERVER is misconfigured" must survive.
 */

const r = (reason) => JSON.stringify({ reason });

// --- Prunes: APNs is talking about this specific token -----------------
assert.equal(
  isDeadToken(410, r("Unregistered")),
  true,
  "410 Unregistered: app was uninstalled, token is dead",
);
assert.equal(
  isDeadToken(400, r("BadDeviceToken")),
  true,
  "400 BadDeviceToken on the token's own environment host: dead token",
);
// 410 is definitive on its own — APNs has sent an empty body here before.
assert.equal(isDeadToken(410, ""), true, "410 prunes without a parsable body");

// --- Survives: APNs is talking about the SERVER ------------------------
// This is the one that matters. Each of these is a config error that affects
// EVERY token at once, so pruning on it deletes the whole table.
for (const [status, reason] of [
  [403, "BadEnvironmentKeyInToken"], // key restricted to one environment
  [403, "InvalidProviderToken"], // wrong/revoked .p8
  [403, "ExpiredProviderToken"], // JWT older than 60 min
  [401, "MissingProviderToken"], // no auth header
  [400, "DeviceTokenNotForTopic"], // APNS_BUNDLE_ID mismatch
  [400, "BadTopic"], // malformed apns-topic
  [400, "MissingTopic"],
  [429, "TooManyRequests"],
  [500, "InternalServerError"],
  [503, "ServiceUnavailable"],
]) {
  assert.equal(
    isDeadToken(status, r(reason)),
    false,
    `${status} ${reason} is a server-side fault — must NOT prune the token`,
  );
}

// --- Survives: we can't tell ------------------------------------------
// Absence of evidence is not evidence of a dead token.
assert.equal(isDeadToken(400, ""), false, "400 with no body: unknown, keep");
assert.equal(
  isDeadToken(400, "<html>502 Bad Gateway</html>"),
  false,
  "400 with a non-JSON body (proxy/CDN error page): unknown, keep",
);
assert.equal(
  isDeadToken(400, r("SomeFutureReason")),
  false,
  "unrecognised reason: keep — new APNs reasons default to safe",
);
assert.equal(
  isDeadToken(400, "null"),
  false,
  "body parses to null: must not throw on property access",
);
assert.equal(isDeadToken(200, r("BadDeviceToken")), false, "200 never prunes");

/* ── Part 3: which types the daily cap applies to ─────────────────────
 *
 * `isCapExempt` gates two things that have to agree: whether the 18/day cap
 * throttles a push, AND whether that push consumes the budget. Exempting a
 * type without the second half means a busy day of hypes silently starves the
 * reminders the cap exists to ration; exempting too much means no cap at all.
 *
 * So both directions are pinned. The person-to-person types must stay exempt —
 * they're unlimited as a product and bounded by SEND-side limits instead
 * (HYPE_DAILY_ABUSE_CEILING, nudges' 1-per-friend-per-24h).
 */
for (const type of [
  "mention",
  "coauthor_invite",
  "hype_received",
  "friend_nudge",
]) {
  assert.equal(
    isCapExempt(type),
    true,
    `${type} is one person addressing another — the daily cap must not eat it`,
  );
}

// The chatter the cap exists for. If these ever go exempt, there is no cap.
for (const type of [
  "friend_activity",
  "friend_post",
  "daily_reminder",
  "badge_earned",
  "friend_badge_earned",
  "friend_personal_best",
  "friend_challenge_completed",
  "lead_change",
  "competition_milestone",
  "friend_request_reminder",
]) {
  assert.equal(
    isCapExempt(type),
    false,
    `${type} is automated chatter — it must stay under the daily cap`,
  );
}

console.log("push-config-check: OK");
