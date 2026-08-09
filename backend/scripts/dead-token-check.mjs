/**
 * Device-token pruning check.
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
 *
 * No DB, no network — the function is pure.
 *
 * Usage: node scripts/dead-token-check.mjs
 */
import assert from "node:assert/strict";
import { isDeadToken } from "../dist/services/pushNotificationService.js";

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

console.log("dead-token-check: OK");
