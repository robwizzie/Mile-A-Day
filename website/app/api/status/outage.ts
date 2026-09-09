/**
 * MANUAL OUTAGE OVERRIDE.
 *
 * Flip `active` to true, write a message, commit, push. Vercel redeploys in
 * about a minute and every phone picks it up within 30 seconds — no App Store
 * release, and nothing that depends on the API server being alive.
 *
 * You usually do NOT need this: `/api/status` probes the API itself, so an app
 * that can't reach the server already tells the user the service is down. Use
 * this when you want to say something the probe can't know — how long it will
 * be, or that it's planned.
 *
 * Set `active` back to false when it's over. A stale outage banner over a
 * working app is worse than no banner: it teaches people to ignore it.
 */
export const MANUAL_OUTAGE: {
  active: boolean;
  title: string;
  message: string;
  /** ISO 8601, or null. Shown as "back by …" when present and in the future. */
  until: string | null;
} = {
  active: false,
  title: "Mile A Day is down",
  message:
    "We're working on it. Your walks are recorded on your phone and will sync as soon as we're back.",
  until: null,
};
