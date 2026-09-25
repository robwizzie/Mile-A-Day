import { PostgresService } from "./DbService.js";
import { areFriends } from "./friendshipService.js";
import { effectiveStreakSql } from "./streakFeatureCore.js";
import { HOLIDAYS, holidayKeyFromBadgeId, type HolidayKey } from "./holidays.js";
import { parseDisplayName, type NameRejection } from "./nameModeration.js";
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
      /** Flamey's name (null = "Flamey"). Same gate as the rest of the block. */
      name: string | null;
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
    flamey_name: string | null;
  }>(
    `SELECT u.dashboard_style, u.flamey_look, u.flamey_name,
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
    name: row.flamey_name ?? null,
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
  /** Flamey's name (null = "Flamey"). Additive. */
  name: string | null;
  /** Saved outfits, in the user's order. Additive. */
  outfits: FlameyOutfit[];
}

/** Self-only closet read; null for an unknown user. */
export async function getFlameyCloset(userId: string): Promise<FlameyCloset | null> {
  const rows = await db.query<{ flamey_look: unknown; flamey_name: string | null }>(
    `SELECT flamey_look, flamey_name FROM users WHERE user_id = $1`,
    [userId],
  );
  if (!rows.length) return null;
  const owned = await ownedFlameyItems(userId);
  return {
    look: servedFlameyLook(rows[0].flamey_look, owned),
    owned_item_ids: [...owned],
    catalog_version: FLAMEY_CATALOG_VERSION,
    name: rows[0].flamey_name ?? null,
    outfits: await readFlameyOutfits(userId, owned),
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

// ─── Flamey's name ──────────────────────────────────────────────────

/** Max length of Flamey's name, in grapheme clusters (what a person counts). */
export const FLAMEY_NAME_MAX = 20;

export type FlameyNameParse =
  | { ok: true; name: string | null }
  | { ok: false; reason: NameRejection };

/**
 * `null` resets to the default ("Flamey", never stored). Anything else is a
 * user-typed name friends will read — validated and moderated by
 * `parseDisplayName` (nameModeration.ts).
 */
export function parseFlameyName(input: unknown): FlameyNameParse {
  if (input === null) return { ok: true, name: null };
  return parseDisplayName(input, FLAMEY_NAME_MAX);
}

/** False for an unknown user. */
export async function saveFlameyName(userId: string, name: string | null): Promise<boolean> {
  const rows = await db.query(
    `UPDATE users SET flamey_name = $2 WHERE user_id = $1 RETURNING user_id`,
    [userId, name],
  );
  return rows.length > 0;
}

// ─── Saved outfits ──────────────────────────────────────────────────

export const FLAMEY_OUTFITS_MAX = 5;
export const FLAMEY_OUTFIT_NAME_MAX = 24;

export interface FlameyOutfit {
  id: string;
  name: string;
  /** Re-validated for ownership at read, like `flamey_look`; null = basic. */
  look: FlameyLook | null;
  /** ISO-8601 UTC, whole seconds (`YYYY-MM-DDTHH:MM:SSZ`). */
  created_at: string;
  updated_at: string;
  /** True when every stored item is still owned; false when any was dropped. */
  owned_ok: boolean;
}

// Whole-second UTC ISO — never a raw timestamptz (fractional seconds break
// the app's decoder, see ios.md).
const isoSeconds = (col: string) =>
  `to_char(${col} AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')`;

/** How many slots a stored look names (explicit nulls = bare, still counted). */
function slotCount(look: unknown): number {
  if (!look || typeof look !== "object" || Array.isArray(look)) return 0;
  return Object.keys(look as Record<string, unknown>).filter((k) => isFlameySlot(k)).length;
}

/** The user's saved outfits, in order, each look re-validated against `owned`. */
export async function readFlameyOutfits(
  userId: string,
  owned?: Set<string>,
): Promise<FlameyOutfit[]> {
  const rows = await db.query<{
    id: string;
    name: string;
    look: unknown;
    created_at: string;
    updated_at: string;
  }>(
    `SELECT id::text AS id, name, look,
	        ${isoSeconds("created_at")} AS created_at,
	        ${isoSeconds("updated_at")} AS updated_at
	   FROM flamey_outfits WHERE user_id = $1
	  ORDER BY position ASC, created_at ASC`,
    [userId],
  );
  if (!rows.length) return [];
  const have = owned ?? (await ownedFlameyItems(userId));
  return rows.map((r) => {
    const look = servedFlameyLook(r.look, have);
    return {
      id: r.id,
      name: r.name,
      look,
      created_at: r.created_at,
      updated_at: r.updated_at,
      owned_ok: slotCount(look) === slotCount(r.look),
    };
  });
}

export interface OutfitInput {
  id: string | null;
  name: string;
  look: FlameyLook | null;
}

export type OutfitsParse =
  | { ok: true; outfits: OutfitInput[] }
  | { ok: false; body: Record<string, unknown> };

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Validate a PUT body's `outfits`. Rejects at WRITE like `flamey_look` does:
 * too many (`too_many_outfits`), a bad name (`invalid_outfit_name` + `reason`
 * + `index`), a bad look (`invalid_flamey_look` + `detail` + `index`). An
 * `id` that isn't a uuid (or repeats one) makes that entry new.
 */
export function parseFlameyOutfits(input: unknown, owned: Set<string>): OutfitsParse {
  const bad = (error: string, extra: Record<string, unknown> = {}): OutfitsParse => ({
    ok: false,
    body: { error, ...extra },
  });
  if (!Array.isArray(input)) return bad("invalid_outfits", { detail: "outfits:not_an_array" });
  if (input.length > FLAMEY_OUTFITS_MAX) return bad("too_many_outfits", { max: FLAMEY_OUTFITS_MAX });
  const out: OutfitInput[] = [];
  const seen = new Set<string>();
  for (let i = 0; i < input.length; i++) {
    const entry = input[i];
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      return bad("invalid_outfits", { detail: "outfit:not_an_object", index: i });
    }
    const e = entry as Record<string, unknown>;
    const name = parseDisplayName(e.name, FLAMEY_OUTFIT_NAME_MAX);
    if (!name.ok) return bad("invalid_outfit_name", { reason: name.reason, index: i });
    const look = parseFlameyLook(e.look === undefined ? null : e.look, owned);
    if (!look.ok) return bad("invalid_flamey_look", { detail: look.detail, index: i });
    let id = typeof e.id === "string" && UUID_RE.test(e.id) ? e.id.toLowerCase() : null;
    if (id && seen.has(id)) id = null;
    if (id) seen.add(id);
    out.push({ id, name: name.name, look: look.look });
  }
  return { ok: true, outfits: out };
}

/**
 * REPLACE the user's outfits with `outfits` (already validated), in one
 * transaction. An entry whose id is one of THIS user's stored outfits keeps
 * that id + `created_at` (`updated_at` moves only when its name or look
 * changed); anything else is inserted with a new id. Outfits left out are
 * deleted — they are the user's own presets and the list is theirs to shape.
 */
export async function replaceFlameyOutfits(userId: string, outfits: OutfitInput[]): Promise<void> {
  const client = await db.getClient();
  try {
    await client.query("BEGIN");
    // Two devices saving at once: one list wins whole, never an interleave.
    await client.query(`SELECT pg_advisory_xact_lock(hashtext('flamey_outfits:' || $1::text))`, [userId]);
    const existing = await client.query<{ id: string }>(
      `SELECT id::text AS id FROM flamey_outfits WHERE user_id = $1`,
      [userId],
    );
    const mine = new Set(existing.rows.map((r) => r.id));
    const keep = outfits.map((o) => (o.id && mine.has(o.id) ? o.id : null));
    await client.query(
      `DELETE FROM flamey_outfits WHERE user_id = $1 AND NOT (id::text = ANY($2::text[]))`,
      [userId, keep.filter((id): id is string => id !== null)],
    );
    for (let i = 0; i < outfits.length; i++) {
      const o = outfits[i];
      // A look of null (basic) is stored as {} — the column is NOT NULL and
      // servedFlameyLook reads {} back as null.
      const lookJson = o.look === null ? "{}" : JSON.stringify(o.look);
      if (keep[i]) {
        await client.query(
          `UPDATE flamey_outfits
	              SET position = $3::int, name = $4::text, look = $5::jsonb,
	                  updated_at = CASE WHEN name IS DISTINCT FROM $4::text OR look IS DISTINCT FROM $5::jsonb
	                                    THEN now() ELSE updated_at END
	            WHERE user_id = $1 AND id = $2::uuid`,
          [userId, keep[i], i, o.name, lookJson],
        );
      } else {
        await client.query(
          `INSERT INTO flamey_outfits (user_id, position, name, look) VALUES ($1, $2::int, $3::text, $4::jsonb)`,
          [userId, i, o.name, lookJson],
        );
      }
    }
    await client.query("COMMIT");
  } catch (err) {
    await client.query("ROLLBACK").catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}
