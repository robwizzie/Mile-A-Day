import { PostgresService } from "./DbService.js";

const db = PostgresService.getInstance();

/// Exported so the admin adoption panel imports the SAME string it charts —
/// a restated literal there would drift the first time a key changed (the
/// meter-constants rule in backend.md).
export const FLYOVER_PLAY_FEATURE = "flyover_play";

/// Features a client may record. An off-list value is DROPPED, not stored —
/// the table must stay a set of known, chartable signals, never a free-text
/// sink (the referral_detail lesson).
export const TRACKED_FEATURES = new Set([FLYOVER_PLAY_FEATURE]);

export async function recordFeatureEvent(
  userId: string,
  feature: string,
): Promise<boolean> {
  if (!TRACKED_FEATURES.has(feature)) return false;
  // One row per user/feature/DAY: the adoption panel only ever charts
  // users_ever/users_30d and event counts, and per-day granularity answers
  // those identically while capping growth at users × features × days —
  // a replay loop (or a broken client retrying) can't inflate the table.
  // Explicit ::text casts: a parameter used in both a bare SELECT list and a
  // varchar comparison gets two deduced types and Postgres refuses the
  // statement (42P08 "inconsistent types deduced").
  await db.query(
    `INSERT INTO feature_events (user_id, feature)
     SELECT $1::text, $2::text
     WHERE NOT EXISTS (
       SELECT 1 FROM feature_events
       WHERE user_id = $1::text AND feature = $2::text
         AND created_at >= date_trunc('day', now())
     )`,
    [userId, feature],
  );
  return true;
}
