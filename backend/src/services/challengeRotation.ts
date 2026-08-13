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
 * Substitute challenge shown to FRIENDLESS users on a day their rotation walk
 * hits head_to_head: instead of silently rotating past the duel, the day
 * becomes "make your first friend" — the on-ramp into everything social.
 * Lives in the catalog with active = FALSE so it never enters the normal
 * rotation; selection substitutes it explicitly (see selectChallengeForUser).
 */
export const ADD_FRIEND_CHALLENGE_KEY = "add_friend";

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
 * A fixed Monday, so week indices are stable forever. 2024-01-01 was a Monday.
 * Anchoring to a real Monday (rather than, say, the epoch) means every
 * `week_start` divides evenly and the index never drifts by a day.
 */
const WEEK_EPOCH_UTC = Date.UTC(2024, 0, 1);

/**
 * Which week `weekStart` is, counting from a fixed Monday.
 *
 * The weekly counterpart to `dayOfYear`: it seeds the same deterministic walk,
 * so the whole app sees one theme per calendar week. Deliberately NOT
 * year-relative — a 52-week year doesn't divide evenly by a catalog of 12, and
 * restarting the count each January would make the rotation jump.
 */
export function weekOfEpoch(weekStartYmd: string): number {
  const [y, m, d] = weekStartYmd.split("-").map((n) => parseInt(n, 10));
  const curr = Date.UTC(y, m - 1, d);
  return Math.floor((curr - WEEK_EPOCH_UTC) / (86400000 * 7));
}

/**
 * The sequence the daily walk actually traverses: the catalog rows in
 * rotation_index order, with head_to_head occurring a SECOND time roughly
 * half a cycle away from the first. Head-to-Head is the catalog's favorite,
 * so it shows up twice per rotation instead of once — done here, in the one
 * sequence both the per-user selection and the batch matchmaker walk, rather
 * than as a second catalog row: a `head_to_head_2` key would flow into
 * completions and pushes that shipped builds route by the exact string.
 */
export function rotationSequence(rows: ChallengeRow[]): ChallengeRow[] {
  const first = rows.findIndex((r) => r.challenge_key === "head_to_head");
  // A catalog too small to repeat into (or with no h2h at all) walks as-is.
  if (first < 0 || rows.length < 4) return rows;
  const seq = [...rows];
  // Insert half a (post-insert) cycle before the first occurrence so the two
  // land as evenly spaced as an integer split allows.
  const cycle = rows.length + 1;
  const at = (first - Math.floor(cycle / 2) + cycle) % cycle;
  seq.splice(at, 0, rows[first]);
  return seq;
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
  return walkSequence(rotationSequence(rows), dayOfYear(localDate), isEligible);
}

/**
 * The rotation walk itself, over an already-built sequence and an explicit
 * seed.
 *
 * Extracted so the weekly challenge can reuse the eligibility-advancing walk
 * without inheriting the daily specifics — `rotationSequence`'s Head-to-Head
 * duplication and the day-of-year seed. `walkRotation` above still composes
 * exactly those two things, so the daily path is unchanged.
 */
export async function walkSequence<T>(
  seq: T[],
  seed: number,
  isEligible: (row: T) => Promise<boolean> | boolean,
): Promise<T> {
  // Guard the modulo: a negative seed (a week before the epoch) would index
  // backwards out of the array.
  const baseIdx = ((seed % seq.length) + seq.length) % seq.length;
  for (let i = 0; i < seq.length; i++) {
    const candidate = seq[(baseIdx + i) % seq.length];
    if (await isEligible(candidate)) return candidate;
  }
  return seq[baseIdx];
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
