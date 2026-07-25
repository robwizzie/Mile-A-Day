/**
 * Rollout gate for Buddy Walks & Runs.
 *
 * Defaults to OFF (opt-in), matching friendRequestFeatures.ts rather than the
 * STREAK_FEATURES_DISABLED kill switch. That direction is deliberate: the
 * server deploys well ahead of an App Store release, and a live buddy session
 * is meaningless to a client that has no buddy UI to render it in.
 *
 * MUST stay off until the app build carrying the Buddy Walks screens is
 * shipped. There is a second, finer gate underneath this one —
 * `users.buddy_enrolled_at`, stamped only by POST /buddy/enroll, which only the
 * new build calls — so that even after this flag flips, an invite can never be
 * routed to a user still on an older install. This flag controls whether the
 * feature exists at all; the enrollment stamp controls who can be pulled into
 * it. Both are required: flipping this alone would let an enrolled user invite
 * a friend who would receive a push for a screen they do not have.
 */
export function buddySessionsEnabled(): boolean {
  return process.env.BUDDY_SESSIONS === "true";
}
