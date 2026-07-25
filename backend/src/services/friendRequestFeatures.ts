import { CLIENT_FEATURES, userSupports } from "./clientFeatures.js";

/**
 * Rollout gates for the friend-request visibility work.
 *
 * Both of these used to be opt-in env flags, held off until the matching app
 * build shipped. That was the wrong shape: it made "safe to enable" a
 * judgement call about App Store adoption, and it could never become fully
 * safe, because a user who simply stops updating stays on the old build
 * forever.
 *
 * Safety is now per device — the app declares what it can handle when it
 * registers its push token (see clientFeatures.ts), and a device that never
 * declared anything never receives the client-dependent payloads. That makes
 * both features safe to ship enabled, and leaves the env vars as kill
 * switches for the "turn it off right now" case, matching
 * STREAK_FEATURES_DISABLED.
 */

/**
 * Kill switch for the parts of the friend_request push that only a capable
 * client can handle: the APNs `badge` count and the FRIEND_REQUEST category
 * (Accept/Decline actions).
 *
 * Off by default. Per-device capability already keeps these away from builds
 * that would mishandle them; set this only to stop them reaching every client
 * at once.
 */
export function friendRequestClientV2Disabled(): boolean {
  return process.env.FRIEND_REQUEST_CLIENT_V2_DISABLED === "true";
}

/**
 * Whether the badge + category may be sent to THIS recipient. False for a
 * client that predates the capability, whatever the env says.
 */
export async function friendRequestClientV2EnabledFor(
  userId: string,
): Promise<boolean> {
  if (friendRequestClientV2Disabled()) return false;
  return userSupports(userId, CLIENT_FEATURES.friendRequestV2);
}

/**
 * Kill switch for the once-per-week "N people are waiting to be your friend"
 * reminder.
 *
 * The reminder is additionally restricted to capable clients inside
 * friendRequestReminderService's candidate query — App Review 4.5.4 requires
 * push to be user-controllable, and the server-synced opt-out toggle only
 * exists in the build that declares `friend_request_v2`. A client without
 * that toggle must never receive this push.
 */
export function friendRequestRemindersDisabled(): boolean {
  return process.env.FRIEND_REQUEST_REMINDERS_DISABLED === "true";
}
