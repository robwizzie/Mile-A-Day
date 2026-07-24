/**
 * Rollout gates for the friend-request visibility work.
 *
 * Both default to OFF (opt-in), unlike STREAK_FEATURES_DISABLED which is a
 * kill switch. That direction is deliberate: the server deploys well ahead of
 * an App Store release, and both features below misbehave — visibly, on a live
 * install — if they reach a client that predates the matching app build.
 */

/**
 * Gates the parts of the friend_request push that only a new client can handle:
 * the APNs `badge` count and the FRIEND_REQUEST category (Accept/Decline
 * actions).
 *
 * MUST stay off until the app build carrying the badge-clearing hook is
 * shipped AND broadly adopted. An older build has no code that ever clears an
 * app icon badge, so a server-set badge becomes a permanently stuck red dot the
 * user cannot dismiss — there is no way to walk that back from the server for a
 * user who has stopped opening the app.
 *
 * The category half is harmless on old clients (an unknown category id just
 * renders a plain notification), but it shares the flag so that flipping one
 * switch at release time turns on the whole client-dependent set.
 */
export function friendRequestClientV2Enabled(): boolean {
  return process.env.FRIEND_REQUEST_CLIENT_V2 === "true";
}

/**
 * Gates the once-per-week "N people are waiting to be your friend" reminder.
 *
 * MUST stay off until the app build carrying the opt-out toggle is shipped.
 * App Review guideline 4.5.4 requires push notifications to be user-
 * controllable, and the existing "Friend requests" switch in Notification
 * Settings is client-side only — it suppresses the in-app banner, not the push.
 * Enabling this cron before a real, server-synced toggle exists would ship a
 * notification users cannot turn off.
 */
export function friendRequestRemindersEnabled(): boolean {
  return process.env.FRIEND_REQUEST_REMINDERS === "true";
}
