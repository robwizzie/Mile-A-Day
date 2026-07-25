import { PostgresService } from "./DbService.js";

const db = PostgresService.getInstance();

/**
 * Per-device capability negotiation.
 *
 * The recurring sharp edge here is timing: merging to main deploys the API
 * immediately, while the matching app build sits in App Review for days and
 * then rolls out to users over weeks — and some users never update at all. A
 * deploy-wide env flag can only ever answer "is the new build out?", which is
 * the wrong question. The right one is "can THIS device handle this?", and
 * only the device can answer it.
 *
 * So the app declares what it supports when it registers its push token
 * (`POST /devices/register`, `client_features`), and the server sends
 * client-dependent payloads only to devices that asked for them. Anything
 * registered before this existed reports an empty set and is treated as
 * legacy forever, which is the safe direction.
 *
 * Adding a capability: add a string here, send it from the app build that
 * implements it, and gate the server behavior on `userSupports`. Never reuse
 * a string with different meaning — old installs keep sending the old one.
 */
export const CLIENT_FEATURES = {
  /**
   * The build handles the friend-request push end to end: it clears its own
   * app-icon badge (at launch, on foreground, and as the pending count
   * changes) and registers the FRIEND_REQUEST category so Accept/Decline
   * actions render and route.
   *
   * The badge is the half that must never reach an older build. Those builds
   * contain no code that clears a badge, so a server-set count becomes a red
   * dot the user cannot dismiss — and cannot be walked back from the server
   * for someone who has stopped opening the app.
   */
  friendRequestV2: "friend_request_v2",
} as const;

export type ClientFeature =
  (typeof CLIENT_FEATURES)[keyof typeof CLIENT_FEATURES];

const KNOWN_FEATURES = new Set<string>(Object.values(CLIENT_FEATURES));

/**
 * Sanitize the `client_features` field of a registration body. Unknown
 * strings are dropped rather than stored: the column is read back into SQL
 * predicates, and an unbounded client-controlled string set is a footgun with
 * no upside. Non-arrays and junk degrade to "legacy client".
 */
export function normalizeClientFeatures(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  const features = new Set<string>();
  for (const value of raw) {
    if (typeof value === "string" && KNOWN_FEATURES.has(value)) {
      features.add(value);
    }
  }
  return [...features];
}

/**
 * Does this user have at least one registered device that can handle
 * `feature`? "At least one" is deliberate — a user with an updated phone and
 * a stale iPad should get the new experience on the phone, and per-device
 * fan-out already happens inside sendPush.
 */
export async function userSupports(
  userId: string,
  feature: ClientFeature,
): Promise<boolean> {
  const rows = await db.query<{ supported: boolean }>(
    `SELECT EXISTS (
			SELECT 1 FROM device_tokens
			WHERE user_id = $1 AND $2 = ANY(client_features)
		) AS supported`,
    [userId, feature],
  );
  return rows[0]?.supported === true;
}

/**
 * The same check as an inlinable SQL predicate, for cron queries that pick
 * recipients in bulk instead of one at a time.
 *
 * `userColumn` is a column expression from the caller's own query (e.g.
 * `f.friend_id`) and `feature` is one of the constants above — both are
 * compile-time values, never request input.
 */
export function supportsClientFeatureSql(
  userColumn: string,
  feature: ClientFeature,
): string {
  return `EXISTS (
		SELECT 1 FROM device_tokens dt
		WHERE dt.user_id = ${userColumn}
			AND '${feature}' = ANY(dt.client_features)
	)`;
}
