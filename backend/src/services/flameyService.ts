import { PostgresService } from "./DbService.js";
import { areFriends } from "./friendshipService.js";
import { effectiveStreakSql } from "./streakFeatureCore.js";
import { HOLIDAYS, holidayKeyFromBadgeId, type HolidayKey } from "./holidays.js";
import {
  FLAMEY_CATALOG,
  FLAMEY_CATALOG_VERSION,
  FLAMEY_SLOTS,
  isFlameySlot,
  ownedFlameyItemIds,
  type FlameySlot,
} from "./flameyCatalog.js";

const db = PostgresService.getInstance();

/**
 * Flamey (the flame mascot) lives on the app's "Fun" dashboard only. The
 * server learns which dashboard a device draws from `users.dashboard_style`
 * (PATCH /users/:id); NULL is a build that predates the field and is treated
 * exactly like 'modern' by every Flamey gate.
 */
export const DASHBOARD_STYLES = new Set(["fun", "modern"]);

export function isFunStyle(style: unknown): boolean {
  return style === "fun";
}

export type FlameyBlock =
  | { enabled: false }
  | {
      enabled: true;
      longest_streak: number;
      holiday_keys: HolidayKey[];
      signup_date: string;
      /** Flamey's Closet look, re-validated for ownership; null = auto. */
      look: FlameyLook | null;
      /**
       * Every catalog item they own (catalog order) — additive, so a
       * viewer's phone resolves their AUTO slots against what they really
       * own rather than guessing from `holiday_keys` + `longest_streak`.
       * Same gate as `look`: friends and self only.
       */
      owned_item_ids: string[];
    };

/**
 * The additive `flamey` block on `GET /users/:id`.
 *
 * Enabled only when the TARGET draws the Fun dashboard AND the viewer may see
 * what it carries: `holiday_keys` are medals, and medals are friends-only
 * (`GET /users/:id/badges` 403s a stranger) — so a stranger gets
 * `{enabled:false}`, never a block with the medals scrubbed out (which would
 * read as "has none"). Self always sees their own.
 *
 * Everything is read from stored columns + the user's badge rows — no
 * history walk per read: `longest_streak` is the ratcheted column, raised to
 * the live effective streak (the column reads 0 until its own backfill lands).
 */
export async function flameyBlockFor(
  viewerId: string | undefined,
  targetUserId: string,
): Promise<FlameyBlock> {
  const rows = await db.query<{
    dashboard_style: string | null;
    longest_streak: number;
    signup_date: string;
    flamey_look: unknown;
  }>(
    `SELECT u.dashboard_style, u.flamey_look,
	        GREATEST(u.longest_streak, (${effectiveStreakSql("u")}))::int AS longest_streak,
	        to_char(((u.created_at AT TIME ZONE 'UTC') + (COALESCE(
	            (SELECT ns.timezone_offset_minutes FROM notification_settings ns WHERE ns.user_id = u.user_id),
	            (SELECT w.timezone_offset FROM workouts w WHERE w.user_id = u.user_id ORDER BY w.device_end_date DESC LIMIT 1),
	            0) || ' minutes')::interval)::date, 'YYYY-MM-DD') AS signup_date
	   FROM users u WHERE u.user_id = $1`,
    [targetUserId],
  );
  const row = rows[0];
  if (!row || !isFunStyle(row.dashboard_style)) return { enabled: false };
  if (!viewerId || !(await areFriends(viewerId, targetUserId))) {
    return { enabled: false };
  }

  // Every badge row: the holiday keys and the closet's ownership read ONE set.
  const badgeRows = await db.query<{ badge_id: string }>(
    `SELECT badge_id FROM user_badges WHERE user_id = $1`,
    [targetUserId],
  );
  const owned = ownedFlameyItemIds(badgeRows.map((r) => r.badge_id));
  const held = new Set(
    badgeRows
      .map((r) => holidayKeyFromBadgeId(r.badge_id))
      .filter((k): k is HolidayKey => k !== null),
  );
  return {
    enabled: true,
    longest_streak: Number(row.longest_streak) || 0,
    // Catalog (calendar) order, so the client can lay them out as-is.
    holiday_keys: HOLIDAYS.map((h) => h.key).filter((k) => held.has(k)),
    signup_date: row.signup_date,
    look: servedFlameyLook(row.flamey_look, owned),
    owned_item_ids: [...owned],
  };
}

/** Both sides draw Flamey — the gate for a Flamey poke. */
export async function bothUseFun(a: string, b: string): Promise<boolean> {
  const rows = await db.query<{ n: number }>(
    `SELECT COUNT(*)::int AS n FROM users
	  WHERE user_id = ANY($1::text[]) AND dashboard_style = 'fun'`,
    [[a, b]],
  );
  return (rows[0]?.n ?? 0) === 2;
}

// ─── Flamey's Closet ────────────────────────────────────────────────

/** `{ <slot>: <itemId> | null }` — absent slot = auto, null = bare. */
export type FlameyLook = Partial<Record<FlameySlot, string | null>>;

/** Items this user owns right now, from their badge rows. */
export async function ownedFlameyItems(userId: string): Promise<Set<string>> {
  const rows = await db.query<{ badge_id: string }>(
    `SELECT badge_id FROM user_badges WHERE user_id = $1`,
    [userId],
  );
  return ownedFlameyItemIds(rows.map((r) => r.badge_id));
}

export type LookParse =
  | { ok: true; look: FlameyLook | null }
  | { ok: false; detail: string };

/**
 * Validate a client-sent look against the catalog AND the owner's items.
 * Rejects (never silently drops) at WRITE: an unknown slot, an unknown item,
 * an item in the wrong slot, or one the user doesn't own — `detail` is
 * `<slot>:<item>`. An empty object normalizes to null (all auto).
 */
export function parseFlameyLook(input: unknown, owned: Set<string>): LookParse {
  if (input === null) return { ok: true, look: null };
  if (typeof input !== "object" || Array.isArray(input)) {
    return { ok: false, detail: "look:not_an_object" };
  }
  const look: FlameyLook = {};
  for (const [slot, value] of Object.entries(input as Record<string, unknown>)) {
    const detail = `${slot}:${value === null ? "null" : String(value)}`;
    if (!isFlameySlot(slot)) return { ok: false, detail };
    if (value === null) {
      look[slot] = null;
      continue;
    }
    if (typeof value !== "string") return { ok: false, detail };
    const item = FLAMEY_CATALOG.get(value);
    if (!item || item.slot !== slot || !owned.has(value)) {
      return { ok: false, detail };
    }
    look[slot] = value;
  }
  return { ok: true, look: canonicalLook(look) };
}

/** Catalog slot order, empty ⇒ null, so stored and served forms are canonical. */
function canonicalLook(look: FlameyLook): FlameyLook | null {
  const out: FlameyLook = {};
  for (const slot of FLAMEY_SLOTS) {
    if (slot in look) out[slot] = look[slot] ?? null;
  }
  return Object.keys(out).length ? out : null;
}

/**
 * The look as SERVED. A stored item the user no longer owns (a medal revoked
 * with a deleted workout) or one retired from the catalog is DROPPED — that
 * slot reads auto again. The row is never rewritten: earn the medal back and
 * the choice returns on its own.
 */
export function servedFlameyLook(stored: unknown, owned: Set<string>): FlameyLook | null {
  if (!stored || typeof stored !== "object" || Array.isArray(stored)) return null;
  const src = stored as Record<string, unknown>;
  const look: FlameyLook = {};
  for (const slot of FLAMEY_SLOTS) {
    if (!(slot in src)) continue;
    const value = src[slot];
    if (value === null) {
      look[slot] = null;
    } else if (typeof value === "string") {
      const item = FLAMEY_CATALOG.get(value);
      if (item && item.slot === slot && owned.has(value)) look[slot] = value;
    }
  }
  return canonicalLook(look);
}

export interface FlameyCloset {
  look: FlameyLook | null;
  owned_item_ids: string[];
  catalog_version: string;
}

/** Self-only closet read; null for an unknown user. */
export async function getFlameyCloset(userId: string): Promise<FlameyCloset | null> {
  const rows = await db.query<{ flamey_look: unknown }>(
    `SELECT flamey_look FROM users WHERE user_id = $1`,
    [userId],
  );
  if (!rows.length) return null;
  const owned = await ownedFlameyItems(userId);
  return {
    look: servedFlameyLook(rows[0].flamey_look, owned),
    owned_item_ids: [...owned],
    catalog_version: FLAMEY_CATALOG_VERSION,
  };
}

/** Writes an already-validated look (null = auto). False for an unknown user. */
export async function saveFlameyLook(
  userId: string,
  look: FlameyLook | null,
): Promise<boolean> {
  const rows = await db.query(
    `UPDATE users SET flamey_look = $2::jsonb WHERE user_id = $1 RETURNING user_id`,
    [userId, look === null ? null : JSON.stringify(look)],
  );
  return rows.length > 0;
}
