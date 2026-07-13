/**
 * Pure daily-challenge rotation logic, shared between the per-user selection
 * in dailyChallengeService and the batch Head-to-Head matchmaker in
 * h2hMatchupService. Both MUST walk the rotation identically — a drift here
 * would pair users into duels they can't see (their card shows a different
 * challenge). Keep this module free of DB access.
 */

export interface ChallengeRow {
  challenge_key: string;
  title: string;
  description_template: string;
  icon: string;
  gradient_start: string;
  gradient_end: string;
  type: "pace" | "distance" | "time" | "activity" | "steps" | "social";
}

/** Social challenges need friends; they're skipped for users with none. */
export const SOCIAL_CHALLENGE_KEYS = new Set([
  "hype_squad",
  "share_journey",
  "head_to_head",
  "wingman",
]);

/**
 * Challenges that require the social feed (photo posts). The feed UI is not in
 * the live App Store build yet — and even once it ships, users lingering on
 * older versions won't have it, and there is no app-version signal on API
 * calls. A user provably has the feature once their client has touched a
 * feed-only endpoint: any `posts` row (the feed build auto-posts each
 * completed mile) or UGC-terms acceptance (only reachable from the composer).
 * No signal → the challenge is never offered. Self-heals as users update.
 */
export const FEED_CHALLENGE_KEYS = new Set(["share_journey"]);

export function dayOfYear(ymd: string): number {
  const [y, m, d] = ymd.split("-").map((n) => parseInt(n, 10));
  const start = Date.UTC(y, 0, 1);
  const curr = Date.UTC(y, m - 1, d);
  return Math.floor((curr - start) / 86400000) + 1;
}

/**
 * The base pick is deterministic by date (so friends on the same day tend to
 * share a challenge); an ineligible pick deterministically advances to the
 * next eligible challenge in the rotation. Falls back to the base pick if
 * nothing is eligible (shouldn't happen).
 */
export async function walkRotation(
  rows: ChallengeRow[],
  localDate: string,
  isEligible: (row: ChallengeRow) => Promise<boolean> | boolean,
): Promise<ChallengeRow> {
  const baseIdx = dayOfYear(localDate) % rows.length;
  for (let i = 0; i < rows.length; i++) {
    const candidate = rows[(baseIdx + i) % rows.length];
    if (await isEligible(candidate)) return candidate;
  }
  return rows[baseIdx];
}

/**
 * Deterministic per-day score for an UNDIRECTED friendship edge: identical no
 * matter which side computes it, so both members of a pair independently
 * derive the same matching. Plain 32-bit string hash — distribution only, not
 * cryptographic.
 */
export function edgeScore(
  userA: string,
  userB: string,
  localDate: string,
): number {
  const [lo, hi] = userA < userB ? [userA, userB] : [userB, userA];
  const seedStr = `${lo}|${hi}|${localDate}`;
  let hash = 0;
  for (let i = 0; i < seedStr.length; i++) {
    hash = (hash * 31 + seedStr.charCodeAt(i)) >>> 0;
  }
  return hash;
}
