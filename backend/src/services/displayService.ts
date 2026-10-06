import crypto from "node:crypto";
import { PostgresService } from "./DbService.js";
import { getPublicStats } from "./publicStatsService.js";
import { START_OF_TODAY_ET_SQL, TODAY_ET_DATE_SQL } from "./dailyResetTime.js";
import { LIVE_PRESENCE_WINDOW_SECONDS } from "./liveTrackingService.js";
import { DAILY_GOAL_TOLERANCE, getTodayMiles, getTodayStats } from "./workoutService.js";
import { effectiveStreakSql, fetchTodayCoverage } from "./streakFeatureCore.js";
import { localNowSql } from "./dailyResetTime.js";
import { MIN_PLAUSIBLE_MILE_SECONDS } from "./mileTime.js";
import { ownedFlameyItems, servedFlameyLook } from "./flameyService.js";
import { postCommentMatchSql } from "./posts/postSql.js";

const db = PostgresService.getInstance();

/**
 * Desk display ("Mile A Day counter") feed.
 *
 * SECURITY MODEL — read this before adding a field.
 *  - A display key is a bearer secret for ONE user, minted by an admin and
 *    shown once. Only its SHA-256 is stored. It authenticates exactly one
 *    route (GET /display/feed); it is never a JWT and never reaches the
 *    authenticated API or /admin.
 *  - The feed is an explicit WHITELIST. Community numbers are global COUNTS
 *    and SUMS only — no ids, names, emails or per-user rows. The "me" block
 *    is the key owner's own data, the same things their own app shows them.
 *  - Friend names (who's out running, who nudged/hyped you) go through the
 *    same privacy rules the app applies to the owner: accepted friendship,
 *    the friend's share_live_presence opt-out, and blocks in BOTH directions.
 *    Only a username is ever returned — no user_id, real name or photo.
 *  - Nothing here writes user data. The only write is the key's own
 *    last_used_at stamp, throttled.
 */

export const DISPLAY_KEY_PREFIX = "madk_";
const KEY_BYTES = 32; // 256-bit secret
// Short enough that Admin -> Displays can call a board offline after 10 min.
const LAST_USED_STAMP_MS = 2 * 60 * 1000;
const FINISHED_WINDOW_MINUTES = 30;
const COMMUNITY_TTL_MS = 30_000;
const ALERT_WINDOW_HOURS = 24;
const MAX_ALERTS = 5;
const MAX_FRIENDS_RUNNING = 3;
const MAX_FRIENDS_FINISHED = 3;
const MAX_AT_RISK_NAMES = 3;
const AT_RISK_MIN_STREAK = 3; // same floor as the admin "at risk" panel
const HEATMAP_DAYS = 64;       // one per pixel column of the panel
const MESSAGE_TTL_HOURS = 24;
const MAX_MESSAGES = 3;
// "<friend> got their mile in!": the same announcements the owner's phone
// gets (so audience and block rules already applied), from the last hour.
const FRIEND_MILE_WINDOW_MINUTES = 60;
const MAX_FRIEND_MILES = 3;
export const MESSAGE_MAX_CHARS = 48;
const MEDAL_WINDOW_HOURS = 48;
const MAX_MEDALS = 3;
// Comments on posts the owner is tagged in (a friend's collab or buddy-walk
// post): the last day's, newest first.
const COMMENT_WINDOW_HOURS = 24;
const MAX_COMMENTS = 3;
/** Flamey's Closet slots the desk can draw (the rest stay off the wire). */
const DESK_FLAMEY_SLOTS = ["color", "head", "eyes", "costume"] as const;
// App Store reviews (founder mode): Apple's public customer-reviews feed.
const APP_STORE_ID = process.env.APP_STORE_ID || "6746970905";
const REVIEWS_TTL_MS = 15 * 60 * 1000;
const MAX_REVIEWS = 3;

export function hashDisplayKey(key: string): string {
  return crypto.createHash("sha256").update(key, "utf8").digest("hex");
}

/** A well-formed key: prefix + 43 base64url chars. Anything else is rejected
 *  before it touches the database. */
export function isWellFormedKey(key: string): boolean {
  return /^madk_[A-Za-z0-9_-]{43}$/.test(key);
}

// ─── Key management (admin only) ───────────────────────────────────────────

export interface DisplayKeyRow {
  id: string;
  username: string | null;
  label: string;
  key_prefix: string;
  created_at: string;
  last_used_at: string | null;
  revoked_at: string | null;
}

export async function createDisplayKey(
  userId: string,
  label: string,
  createdBy: string | null,
): Promise<{ key: string; row: DisplayKeyRow }> {
  const key = DISPLAY_KEY_PREFIX + crypto.randomBytes(KEY_BYTES).toString("base64url");
  const [row] = await db.query<DisplayKeyRow>(
    `WITH ins AS (
       INSERT INTO display_keys (user_id, key_hash, key_prefix, label, created_by)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, user_id, label, key_prefix, created_at, last_used_at, revoked_at
     )
     SELECT ins.id, u.username, ins.label, ins.key_prefix,
            ins.created_at::text, ins.last_used_at::text, ins.revoked_at::text
       FROM ins JOIN users u ON u.user_id = ins.user_id`,
    [userId, hashDisplayKey(key), key.slice(0, 9), label.slice(0, 60), createdBy],
  );
  return { key, row };
}

export async function listDisplayKeys(): Promise<DisplayKeyRow[]> {
  // Never selects key_hash.
  return db.query<DisplayKeyRow>(
    `SELECT k.id, u.username, k.label, k.key_prefix, k.created_at::text,
            k.last_used_at::text, k.revoked_at::text
       FROM display_keys k JOIN users u ON u.user_id = k.user_id
      ORDER BY k.revoked_at IS NOT NULL, k.created_at DESC
      LIMIT 200`,
  );
}

export async function revokeDisplayKey(id: string): Promise<boolean> {
  const rows = await db.query(
    `UPDATE display_keys SET revoked_at = NOW()
      WHERE id = $1 AND revoked_at IS NULL
      RETURNING id`,
    [id],
  );
  return rows.length > 0;
}

/** userId for a live (unrevoked) key whose owner still exists, else null. */
export async function resolveDisplayKey(key: string): Promise<string | null> {
  return (await resolveDisplayKeyRow(key))?.userId ?? null;
}

/** The key's owner and the key (box) id, or null. Stamps last_used_at. */
export async function resolveDisplayKeyRow(key: string): Promise<{ userId: string; keyId: string } | null> {
  if (!isWellFormedKey(key)) return null;
  const rows = await db.query<{ id: string; user_id: string; stale: boolean }>(
    `SELECT k.id, k.user_id,
            (k.last_used_at IS NULL OR k.last_used_at < NOW() - ($2 || ' milliseconds')::interval) AS stale
       FROM display_keys k JOIN users u ON u.user_id = k.user_id
      WHERE k.key_hash = $1 AND k.revoked_at IS NULL`,
    [hashDisplayKey(key), String(LAST_USED_STAMP_MS)],
  );
  if (!rows.length) return null;
  if (rows[0].stale) {
    // Best effort; a failed stamp never fails the request.
    db.query(`UPDATE display_keys SET last_used_at = NOW() WHERE id = $1`, [rows[0].id])
      .catch(() => undefined);
  }
  return { userId: rows[0].user_id, keyId: rows[0].id };
}

// ─── Desk-to-desk messages (admin writes, the recipient's display reads) ───

/** Emoji the panel can draw as an icon, mapped to a token it understands. */
const EMOJI_TOKENS: [RegExp, string][] = [
  [/\u{1F525}/gu, "\u0001"],                                               // fire
  [/(\u2764|\u2665|\u{1F496}|\u{1F497}|\u{1F493}|\u{1F495}|\u{1F9E1})\uFE0F?/gu, "\u0002"], // heart
  [/\u{1F44F}[\u{1F3FB}-\u{1F3FF}]?/gu, "\u0003"],                        // clap
  [/\u{1F3C3}[\u{1F3FB}-\u{1F3FF}]?(\u200D[\u2640\u2642]\uFE0F?)?/gu, "\u0004"], // runner
];
const TOKEN_NAMES = ["", "[FIRE]", "[HEART]", "[CLAP]", "[RUN]"];

/**
 * Turn what an admin typed into something the panel can draw: upper case,
 * the panel font's characters only, four emoji as icon tokens, single
 * spaces, at most MESSAGE_MAX_CHARS. Returns null if nothing is left.
 */
export function sanitizeDisplayText(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  let t = raw.normalize("NFC");
  for (const [re, tok] of EMOJI_TOKENS) t = t.replace(re, ` ${tok} `);
  t = t.toUpperCase().replace(/[^A-Z0-9 .,!?'\-+#:/%&\u0001-\u0004]/g, "");
  t = t.replace(/\s+/g, " ").trim().slice(0, MESSAGE_MAX_CHARS).trim();
  if (!t.replace(/[\u0001-\u0004 ]/g, "").length && !/[\u0001-\u0004]/.test(t)) return null;
  return t.replace(/[\u0001-\u0004]/g, (c) => TOKEN_NAMES[c.charCodeAt(0)]);
}

export interface DisplayMessageRow {
  id: string;
  to_username: string | null;
  from_username: string | null;
  body: string;
  created_at: string;
  expires_at: string;
}

export async function createDisplayMessage(
  toUserId: string,
  fromUserId: string | null,
  body: string,
): Promise<DisplayMessageRow> {
  const rows = await db.query<DisplayMessageRow>(
    `WITH ins AS (
       INSERT INTO display_messages (to_user_id, from_user_id, body, expires_at)
       VALUES ($1, $2, $3, NOW() + INTERVAL '${MESSAGE_TTL_HOURS} hours')
       RETURNING id, to_user_id, from_user_id, body, created_at, expires_at
     )
     SELECT ins.id, tu.username AS to_username, fu.username AS from_username, ins.body,
            ins.created_at::text, ins.expires_at::text
       FROM ins
       JOIN users tu ON tu.user_id = ins.to_user_id
       LEFT JOIN users fu ON fu.user_id = ins.from_user_id`,
    [toUserId, fromUserId, body],
  );
  return rows[0];
}

export async function listDisplayMessages(): Promise<DisplayMessageRow[]> {
  return db.query<DisplayMessageRow>(
    `SELECT m.id, tu.username AS to_username, fu.username AS from_username, m.body,
            m.created_at::text, m.expires_at::text
       FROM display_messages m
       JOIN users tu ON tu.user_id = m.to_user_id
       LEFT JOIN users fu ON fu.user_id = m.from_user_id
      ORDER BY m.created_at DESC
      LIMIT 30`,
  );
}

// ─── The desk remote (Admin -> Desks, on a phone) ──────────────────────────
// One page for every box (display key): pick a box, set its style and
// mascot, start its stat show, message another box, read its messages,
// see the live data it's showing and a log of what happened on it. Changes
// reach a box through its own feed (it polls every ~15 s); boxes themselves
// still never write anything. Nothing here can fake an event: nudges, hypes,
// runs, medals and the rest only ever come from real activity.

/** Board style / mascot ids, in the board's own order (mad/app.py). */
export const DESK_STYLES = ["CLASSIC", "SPOTLIGHT", "ARCADE", "BIG", "CAMPFIRE", "RACE", "CLOCK"] as const;
export const DESK_MASCOTS = ["RUNNER", "FLAMEY"] as const;
const COMMAND_WINDOW_SECONDS = 180;   // a box acts on a tap from the last 3 min
const MAX_COMMANDS_PER_10_MIN = 30;
const DESK_HISTORY_DAYS = 14;
const ACTIVITY_DAYS = 7;
const ONLINE_MS = 10 * 60 * 1000;     // last_used_at is stamped at most every 2 min

export interface DeskSettings { style: number | null; mascot: number | null; rev: number }

export interface DeskBox {
  id: string;
  label: string;
  username: string | null;
  last_seen: string | null;
  online: boolean;
}

function boxRow(r: { id: string; label: string; username: string | null; last_used_at: string | null }): DeskBox {
  return {
    id: r.id,
    label: r.label,
    username: r.username,
    last_seen: r.last_used_at,
    online: r.last_used_at != null && Date.now() - Date.parse(r.last_used_at) < ONLINE_MS,
  };
}

/** Every active box (key), oldest first. Never the hash. */
export async function listDeskBoxes(): Promise<DeskBox[]> {
  const rows = await db.query<{ id: string; label: string; username: string | null; last_used_at: string | null }>(
    `SELECT k.id, k.label, u.username, k.last_used_at::text
       FROM display_keys k JOIN users u ON u.user_id = k.user_id
      WHERE k.revoked_at IS NULL
      ORDER BY k.created_at`,
  );
  return rows.map(boxRow);
}

async function boxOwner(boxId: string): Promise<{ userId: string; box: DeskBox } | null> {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(boxId)) return null;
  const rows = await db.query<{ id: string; user_id: string; label: string; username: string | null; last_used_at: string | null }>(
    `SELECT k.id, k.user_id, k.label, u.username, k.last_used_at::text
       FROM display_keys k JOIN users u ON u.user_id = k.user_id
      WHERE k.id = $1 AND k.revoked_at IS NULL`, [boxId]);
  return rows[0] ? { userId: rows[0].user_id, box: boxRow(rows[0]) } : null;
}

export async function getBoxSettings(keyId: string): Promise<DeskSettings | null> {
  const rows = await db.query<DeskSettings>(
    `SELECT style, mascot, rev FROM desk_box_settings WHERE key_id = $1`, [keyId]);
  return rows[0] ?? null;
}

/** Set a box's style and/or mascot (null leaves it). Bumps `rev`, logs it.
 *  Returns null for an unknown/revoked box. */
export async function setBoxSettings(
  boxId: string, style: number | null, mascot: number | null,
): Promise<DeskSettings | null> {
  const owner = await boxOwner(boxId);
  if (!owner) return null;
  const rows = await db.query<DeskSettings>(
    `INSERT INTO desk_box_settings (key_id, style, mascot, rev, updated_at)
     VALUES ($1, $2, $3, 1, NOW())
     ON CONFLICT (key_id) DO UPDATE
       SET style = COALESCE($2, desk_box_settings.style),
           mascot = COALESCE($3, desk_box_settings.mascot),
           rev = desk_box_settings.rev + 1,
           updated_at = NOW()
     RETURNING style, mascot, rev`,
    [boxId, style, mascot],
  );
  const s = rows[0];
  const detail = [s.style != null ? DESK_STYLES[s.style] : null, s.mascot != null ? DESK_MASCOTS[s.mascot] : null]
    .filter(Boolean).join(" / ");
  await db.query(
    `INSERT INTO desk_commands (user_id, key_id, kind, detail) VALUES ($1, $2, 'set', $3)`,
    [owner.userId, boxId, detail],
  );
  return s;
}

/** "Run the stat show now" on a box (real numbers only). False = rate-limited,
 *  null = unknown box. */
export async function queueBoxShow(boxId: string): Promise<boolean | null> {
  const owner = await boxOwner(boxId);
  if (!owner) return null;
  const recent = await db.query<{ n: number }>(
    `SELECT COUNT(*)::int AS n FROM desk_commands
      WHERE key_id = $1 AND created_at > NOW() - INTERVAL '10 minutes'`, [boxId]);
  if ((recent[0]?.n ?? 0) >= MAX_COMMANDS_PER_10_MIN) return false;
  await db.query(`DELETE FROM desk_commands WHERE key_id = $1 AND created_at < NOW() - INTERVAL '30 days'`, [boxId]);
  await db.query(`INSERT INTO desk_commands (user_id, key_id, kind) VALUES ($1, $2, 'show')`, [owner.userId, boxId]);
  return true;
}

/** A desk message from one box's owner to another box's owner. */
export async function sendBoxMessage(fromBoxId: string, toBoxId: string, text: string) {
  const [from, to] = await Promise.all([boxOwner(fromBoxId), boxOwner(toBoxId)]);
  if (!from || !to) return null;
  return createDisplayMessage(to.userId, from.userId, text);
}

export interface DeskActivity { at: string; kind: string; text: string }

/** What happened on a box lately, newest first: real events only (from the
 *  same sources its feed uses), plus changes made from the remote. */
async function boxActivity(boxId: string, userId: string): Promise<DeskActivity[]> {
  const days = `INTERVAL '${ACTIVITY_DAYS} days'`;
  const blocked = (col: string) => `NOT EXISTS (
            SELECT 1 FROM user_blocks b
             WHERE (b.blocker_id = $1 AND b.blocked_id = ${col})
                OR (b.blocker_id = ${col} AND b.blocked_id = $1))`;
  const rows = await db.query<DeskActivity>(
    `SELECT to_char(t AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS at, kind, text FROM (
       SELECT n.created_at AS t, CASE n.type WHEN 'friend_nudge' THEN 'nudge' ELSE 'hype' END AS kind,
              CASE n.type WHEN 'friend_nudge' THEN 'Nudge from @' ELSE 'Hype from @' END
                || COALESCE(su.username, 'a friend') AS text
         FROM in_app_notifications n
         LEFT JOIN users su ON su.user_id = (n.data->>'user_id')
        WHERE n.user_id = $1 AND n.type IN ('friend_nudge', 'hype_received')
          AND n.created_at > NOW() - ${days}
          AND (n.data->>'user_id') IS DISTINCT FROM $1
          AND ${blocked("(n.data->>'user_id')")}
       UNION ALL
       SELECT m.created_at, CASE WHEN m.to_user_id = $1 THEN 'message_in' ELSE 'message_out' END,
              CASE WHEN m.to_user_id = $1 THEN 'Message from @' || COALESCE(fu.username, 'Mile A Day')
                   ELSE 'Message to @' || COALESCE(tu.username, '?') END || ': ' || m.body
         FROM display_messages m
         LEFT JOIN users fu ON fu.user_id = m.from_user_id
         LEFT JOIN users tu ON tu.user_id = m.to_user_id
        WHERE (m.to_user_id = $1 OR m.from_user_id = $1) AND m.created_at > NOW() - ${days}
       UNION ALL
       SELECT n.created_at, 'friend_mile', '@' || su.username || ' got their mile in · ' || n.body
         FROM in_app_notifications n
         JOIN users su ON su.user_id = (n.data->>'user_id')
        WHERE n.user_id = $1 AND n.type = 'friend_activity' AND n.data->>'kind' = 'mile_completed'
          AND n.created_at > NOW() - ${days}
          AND ${blocked("su.user_id")}
       UNION ALL
       SELECT ub.earned_at, 'medal', 'New medal: ' || b.name
         FROM user_badges ub JOIN badges b ON b.badge_id = ub.badge_id
        WHERE ub.user_id = $1 AND ub.earned_at > NOW() - ${days}
       UNION ALL
       SELECT w.device_end_date, 'run',
              'You logged ' || to_char(w.distance, 'FM990.00') || ' mi'
         FROM workouts w
        WHERE w.user_id = $1 AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
          AND w.device_end_date > NOW() - ${days}
       UNION ALL
       SELECT s.ended_at, 'friend_run',
              '@' || u.username || ' finished ' || to_char(s.distance_miles, 'FM990.00') || ' mi'
         FROM friendships f
         JOIN live_tracking_sessions s ON s.user_id = f.friend_id AND s.ended_at IS NOT NULL
          AND s.ended_at > NOW() - ${days}
         JOIN users u ON u.user_id = f.friend_id
         LEFT JOIN notification_settings ns ON ns.user_id = f.friend_id
        WHERE f.user_id = $1 AND f.status = 'accepted' AND u.username IS NOT NULL
          AND COALESCE(ns.share_live_presence, TRUE) = TRUE
          AND ${blocked("f.friend_id")}
       UNION ALL
       SELECT c.created_at, 'remote',
              CASE c.kind WHEN 'set' THEN 'Changed from the remote: ' || COALESCE(c.detail, '')
                          ELSE 'Stat show started from the remote' END
         FROM desk_commands c
        WHERE c.key_id = $2 AND c.created_at > NOW() - ${days}
     ) a
     ORDER BY t DESC NULLS LAST
     LIMIT 60`,
    [userId, boxId],
  );
  return rows;
}

/** Everything the remote shows for one box. Null for an unknown box. */
export async function getDeskBox(boxId: string) {
  const owner = await boxOwner(boxId);
  if (!owner) return null;
  const userId = owner.userId;
  const [settings, messages, others, feed, activity] = await Promise.all([
    getBoxSettings(boxId),
    db.query<{ id: string; direction: "in" | "out"; who: string; text: string; at: string }>(
      `SELECT encode(sha256(m.id::text::bytea), 'hex') AS id,
              CASE WHEN m.to_user_id = $1 THEN 'in' ELSE 'out' END AS direction,
              CASE WHEN m.to_user_id = $1 THEN COALESCE(fu.username, 'MILE A DAY')
                   ELSE COALESCE(tu.username, '?') END AS who,
              m.body AS text,
              to_char(m.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS at
         FROM display_messages m
         LEFT JOIN users tu ON tu.user_id = m.to_user_id
         LEFT JOIN users fu ON fu.user_id = m.from_user_id
        WHERE (m.to_user_id = $1 OR m.from_user_id = $1)
          AND m.created_at > NOW() - INTERVAL '${DESK_HISTORY_DAYS} days'
        ORDER BY m.created_at DESC
        LIMIT 50`, [userId]),
    listDeskBoxes(),
    getDisplayFeed(userId, boxId),
    boxActivity(boxId, userId),
  ]);
  return {
    box: owner.box,
    styles: DESK_STYLES,
    mascots: DESK_MASCOTS,
    settings: settings ?? { style: null, mascot: null, rev: 0 },
    messages: messages.map((m) => ({ ...m, id: m.id.slice(0, 16) })),
    // Message another box (not one owned by this box's owner).
    recipients: others.filter((b) => b.id !== boxId && b.username && b.username !== owner.box.username),
    activity,
    // The same data the box itself gets: the page draws its real screen.
    live: feed,
  };
}

// ─── App Store reviews (founder mode, admins' desks only) ──────────────────

export interface DeskReview { id: string; stars: number; title: string }

/** Parse Apple's public customer-reviews JSON into desk-safe rows: an opaque
 *  id, the star rating and the title cleaned for the panel. No author name,
 *  no body. Tolerates the feed's quirks (a lone entry is an object, older
 *  feeds lead with the app's own metadata entry). */
export function parseAppReviews(json: unknown): DeskReview[] {
  const feed = (json as any)?.feed;
  let entries = feed?.entry ?? [];
  if (!Array.isArray(entries)) entries = [entries];
  const out: DeskReview[] = [];
  for (const e of entries) {
    const stars = Number(e?.["im:rating"]?.label);
    const rawId = String(e?.id?.label ?? "");
    if (!rawId || !(stars >= 1 && stars <= 5)) continue;
    const title = sanitizeDisplayText(String(e?.title?.label ?? "")) ?? "";
    out.push({
      id: crypto.createHash("sha256").update(`review:${rawId}`).digest("hex").slice(0, 16),
      stars: Math.round(stars),
      title,
    });
    if (out.length >= MAX_REVIEWS) break;
  }
  return out;
}

type ReviewSource = () => Promise<unknown>;
let reviewSource: ReviewSource = async () => {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 8000);
  try {
    const res = await fetch(
      `https://itunes.apple.com/us/rss/customerreviews/id=${APP_STORE_ID}/sortby=mostrecent/json`,
      { signal: ctrl.signal, headers: { accept: "application/json" } },
    );
    if (!res.ok) throw new Error(`reviews ${res.status}`);
    return await res.json();
  } finally {
    clearTimeout(timer);
  }
};
let reviewsCache: { data: DeskReview[]; at: number } | null = null;

/** Tests swap the network source for a fixture. */
export function setReviewSourceForTests(src: ReviewSource) {
  reviewSource = src;
  reviewsCache = null;
}

async function latestReviews(): Promise<DeskReview[]> {
  if (reviewsCache && Date.now() - reviewsCache.at < REVIEWS_TTL_MS) return reviewsCache.data;
  try {
    const data = parseAppReviews(await reviewSource());
    reviewsCache = { data, at: Date.now() };
    return data;
  } catch {
    // Apple's feed is down or slow: keep what we had, try again next time.
    reviewsCache = { data: reviewsCache?.data ?? [], at: Date.now() - REVIEWS_TTL_MS + 60_000 };
    return reviewsCache.data;
  }
}

// ─── Community block (aggregates only, cached) ─────────────────────────────

export interface DisplayCommunity {
  total_users: number;
  total_miles: number;
  miles_today: number;
  active_7d: number;
  longest_streak: number;
  total_hypes: number;
  photos_shared: number;
  out_running_now: number;
  tokens_spent_today: number;
  badges_today: number;
  new_friends_today: number;
  hypes_today: number;
  nudges_today: number;
  miles_yesterday_same_time: number;
}

let communityCache: { data: DisplayCommunity; at: number } | null = null;
async function getCommunity(): Promise<DisplayCommunity> {
  if (communityCache && Date.now() - communityCache.at < COMMUNITY_TTL_MS) {
    return communityCache.data;
  }
  const pub = await getPublicStats();
  const [row] = await db.query<Record<string, number>>(`
    SELECT
      -- Out on a tracked mile right now, counted the way the app decides
      -- presence (fresh heartbeat, not ended) and only among people who
      -- share their live presence.
      (SELECT COUNT(*) FROM live_tracking_sessions s
         LEFT JOIN notification_settings ns ON ns.user_id = s.user_id
        WHERE s.ended_at IS NULL
          AND s.last_seen_at > NOW() - INTERVAL '${LIVE_PRESENCE_WINDOW_SECONDS} seconds'
          AND COALESCE(ns.share_live_presence, TRUE) = TRUE)::int AS out_running_now,
      (SELECT COUNT(*) FROM streak_coverage
        WHERE created_at >= ${START_OF_TODAY_ET_SQL})::int AS tokens_spent_today,
      (SELECT COUNT(*) FROM user_badges
        WHERE earned_at >= ${START_OF_TODAY_ET_SQL})::int AS badges_today,
      -- A friendship is two rows; accepting keeps the request's old
      -- created_at and inserts the reverse row now, so count PAIRS that
      -- gained any row today.
      (SELECT COUNT(DISTINCT LEAST(user_id, friend_id) || ':' || GREATEST(user_id, friend_id))
         FROM friendships
        WHERE status = 'accepted' AND created_at >= ${START_OF_TODAY_ET_SQL})::int AS new_friends_today,
      (SELECT COUNT(*) FROM hype_log
        WHERE created_at >= ${START_OF_TODAY_ET_SQL})::int AS hypes_today,
      ((SELECT COUNT(*) FROM nudge_log WHERE created_at >= ${START_OF_TODAY_ET_SQL}) +
       (SELECT COUNT(*) FROM friend_nudge_log WHERE created_at >= ${START_OF_TODAY_ET_SQL}))::int AS nudges_today,
      -- Yesterday's miles logged by this time of day (for the race screen).
      (SELECT COALESCE(SUM(distance), 0) FROM workouts
        WHERE local_date = ${TODAY_ET_DATE_SQL} - 1
          AND device_end_date <= NOW() - INTERVAL '1 day'
          AND deleted_at IS NULL AND exclusion_reason IS NULL)::float AS miles_yesterday_same_time
  `);
  const data: DisplayCommunity = {
    total_users: pub.total_users,
    total_miles: pub.total_miles,
    miles_today: pub.miles_today,
    active_7d: pub.active_7d,
    longest_streak: pub.longest_streak,
    total_hypes: pub.total_hypes,
    photos_shared: pub.photos_shared,
    out_running_now: row?.out_running_now ?? 0,
    tokens_spent_today: row?.tokens_spent_today ?? 0,
    badges_today: row?.badges_today ?? 0,
    new_friends_today: row?.new_friends_today ?? 0,
    hypes_today: row?.hypes_today ?? 0,
    nudges_today: row?.nudges_today ?? 0,
    miles_yesterday_same_time: Math.round((row?.miles_yesterday_same_time ?? 0) * 10) / 10,
  };
  communityCache = { data, at: Date.now() };
  return data;
}

// ─── Owner block ───────────────────────────────────────────────────────────

export interface DisplayFeed {
  v: 1;
  community: DisplayCommunity;
  me: {
    username: string | null;
    mile_done: boolean;
    miles_today: number;
    streak: number;
    running_now: boolean;
    local_time: string;          // "HH:MM:SS" in the owner's timezone
    minutes_to_midnight: number; // until the owner's local day ends
    year_ago_miles: number | null; // their own miles on this date last year
    local_date: string;          // "YYYY-MM-DD" in the owner's timezone (seasonal looks)
    live_miles: number | null;   // their own live session distance while running_now
    longest_run: number | null;  // their longest single run, all time
    fastest_mile_month: number | null; // their fastest full-mile split this local month, seconds
    /** Their own last 64 local days, oldest first: miles that day, or -1 for
     *  a day with no mile that a streak token covered. */
    days: number[];
    /** Their own Flamey's Closet look, slots the desk draws: item ids only. */
    flamey: Partial<Record<(typeof DESK_FLAMEY_SLOTS)[number], string>> | null;
    /** Medals they earned in the last 48 h (newest first). */
    medals: { id: string; name: string; age_s: number }[];
  };
  /** New comments (last 24 h, newest first) on posts the owner is tagged in:
   *  someone else's post where they are an accepted coauthor. Commenter by
   *  username only; text cleaned to the panel's characters. The owner can
   *  read every one of these on the post itself. */
  comments: { id: string; from: string; text: string; age_s: number }[];
  /** Friends who got their mile in (the owner's own "got their mile in!"
   *  notifications, last hour): their day so far. */
  friends_miles: { id: string; name: string; miles: number; seconds: number; best_pace: number | null; age_s: number }[];
  /** This box's remote settings (style / mascot ids, rev bumps per change). */
  desk: DeskSettings | null;
  /** Remote taps for this box from the last 3 min: opaque id + "show". */
  commands: { id: string; kind: string }[];
  /** Founder mode: newest App Store reviews, only on admins' desks. */
  reviews: DeskReview[];
  /** Unexpired desk messages sent TO the owner (newest first). */
  messages: { id: string; from: string; text: string; age_s: number }[];
  friends_running: { name: string; miles: number }[];
  /** The owner's friends whose streak is at risk today (their own local day,
   *  the admin panel's rule). Friends already see each other's daily miles in
   *  the app; blocks in either direction are excluded. */
  friends_at_risk: { count: number; top: { name: string; streak: number }[] };
  /** Friends whose tracked session ended in the last 30 min (same rules). */
  friends_finished: { id: string; name: string; miles: number }[];
  alerts: { id: string; kind: "nudge" | "hype"; from: string; at: string }[];
}

export async function getDisplayFeed(userId: string, keyId?: string): Promise<DisplayFeed> {
  const [community, meRows, todayMiles, coverage, friends, alerts, finished, atRisk, days, messages,
         closetRows, owned, medals, roleRows, comments, desk, commands, friendMiles] = await Promise.all([
    getCommunity(),
    db.query<{
      username: string | null;
      streak: number;
      running_now: boolean;
      local_time: string;
      minutes_to_midnight: number;
      year_ago_miles: number | null;
      local_date: string;
      live_miles: number | null;
      longest_run: number | null;
      fastest_mile_month: number | null;
    }>(
      `WITH tz AS (
         SELECT COALESCE((SELECT timezone_offset FROM workouts
                           WHERE user_id = $1 ORDER BY device_end_date DESC LIMIT 1), 0) AS off
       ), loc AS (
         SELECT (NOW() AT TIME ZONE 'UTC') + (tz.off || ' minutes')::interval AS t FROM tz
       )
       SELECT u.username,
              (${effectiveStreakSql("u")})::int AS streak,
              EXISTS (SELECT 1 FROM live_tracking_sessions s
                       WHERE s.user_id = u.user_id AND s.ended_at IS NULL
                         AND s.last_seen_at > NOW() - INTERVAL '${LIVE_PRESENCE_WINDOW_SECONDS} seconds') AS running_now,
              to_char(loc.t, 'HH24:MI:SS') AS local_time,
              (EXTRACT(EPOCH FROM (date_trunc('day', loc.t) + INTERVAL '1 day' - loc.t)) / 60)::int AS minutes_to_midnight,
              (SELECT SUM(w.distance)::float FROM workouts w
                WHERE w.user_id = u.user_id
                  AND w.local_date = (loc.t - INTERVAL '1 year')::date
                  AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL) AS year_ago_miles,
              to_char(loc.t, 'YYYY-MM-DD') AS local_date,
              (SELECT s.distance_miles::float FROM live_tracking_sessions s
                WHERE s.user_id = u.user_id AND s.ended_at IS NULL
                  AND s.last_seen_at > NOW() - INTERVAL '${LIVE_PRESENCE_WINDOW_SECONDS} seconds') AS live_miles,
              (SELECT MAX(w.distance)::float FROM workouts w
                WHERE w.user_id = u.user_id AND w.workout_type = 'running'
                  AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL) AS longest_run,
              (SELECT MIN(ws.split_pace)::float FROM workout_splits ws
                 JOIN workouts w ON w.workout_id = ws.workout_id
                WHERE w.user_id = u.user_id AND w.workout_type = 'running'
                  AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
                  AND w.local_date >= date_trunc('month', loc.t)::date
                  AND ws.split_distance >= 0.999
                  AND ws.split_pace >= ${MIN_PLAUSIBLE_MILE_SECONDS}) AS fastest_mile_month
         FROM users u, loc
        WHERE u.user_id = $1`,
      [userId],
    ),
    getTodayMiles(userId),
    fetchTodayCoverage([userId]),
    db.query<{ name: string; miles: number }>(
      `SELECT u.username AS name, ROUND(s.distance_miles::numeric, 1)::float AS miles
         FROM friendships f
         JOIN live_tracking_sessions s
           ON s.user_id = f.friend_id
          AND s.ended_at IS NULL
          AND s.last_seen_at > NOW() - INTERVAL '${LIVE_PRESENCE_WINDOW_SECONDS} seconds'
         JOIN users u ON u.user_id = f.friend_id
         LEFT JOIN notification_settings ns ON ns.user_id = f.friend_id
        WHERE f.user_id = $1
          AND f.status = 'accepted'
          AND u.username IS NOT NULL
          AND COALESCE(ns.share_live_presence, TRUE) = TRUE
          AND NOT EXISTS (
            SELECT 1 FROM user_blocks b
             WHERE (b.blocker_id = $1 AND b.blocked_id = f.friend_id)
                OR (b.blocker_id = f.friend_id AND b.blocked_id = $1))
        ORDER BY s.started_at DESC
        LIMIT ${MAX_FRIENDS_RUNNING}`,
      [userId],
    ),
    // The owner's own inbox: nudges and hypes sent TO them. Read-only (the
    // display never marks anything read). Sender shown by username only.
    db.query<{ id: string; kind: "nudge" | "hype"; from: string; at: string }>(
      `SELECT encode(sha256(n.id::text::bytea), 'hex') AS id,
              CASE n.type WHEN 'friend_nudge' THEN 'nudge' ELSE 'hype' END AS kind,
              COALESCE(su.username, 'A FRIEND') AS "from",
              to_char(n.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS at
         FROM in_app_notifications n
         LEFT JOIN users su ON su.user_id = (n.data->>'user_id')
        WHERE n.user_id = $1
          AND n.type IN ('friend_nudge', 'hype_received')
          AND n.created_at > NOW() - INTERVAL '${ALERT_WINDOW_HOURS} hours'
          AND (n.data->>'user_id') IS DISTINCT FROM $1
          AND NOT EXISTS (
            SELECT 1 FROM user_blocks b
             WHERE (b.blocker_id = $1 AND b.blocked_id = (n.data->>'user_id'))
                OR (b.blocker_id = (n.data->>'user_id') AND b.blocked_id = $1))
        ORDER BY n.created_at DESC
        LIMIT ${MAX_ALERTS}`,
      [userId],
    ),
    // Friends who just FINISHED a tracked session: identical friendship,
    // presence opt-out and block rules to friends_running above.
    db.query<{ id: string; name: string; miles: number }>(
      `SELECT encode(sha256((s.session_id::text || s.ended_at::text)::bytea), 'hex') AS id,
              u.username AS name, ROUND(s.distance_miles::numeric, 1)::float AS miles
         FROM friendships f
         JOIN live_tracking_sessions s
           ON s.user_id = f.friend_id
          AND s.ended_at IS NOT NULL
          AND s.ended_at > NOW() - INTERVAL '${FINISHED_WINDOW_MINUTES} minutes'
         JOIN users u ON u.user_id = f.friend_id
         LEFT JOIN notification_settings ns ON ns.user_id = f.friend_id
        WHERE f.user_id = $1
          AND f.status = 'accepted'
          AND u.username IS NOT NULL
          AND COALESCE(ns.share_live_presence, TRUE) = TRUE
          AND NOT EXISTS (
            SELECT 1 FROM user_blocks b
             WHERE (b.blocker_id = $1 AND b.blocked_id = f.friend_id)
                OR (b.blocker_id = f.friend_id AND b.blocked_id = $1))
        ORDER BY s.ended_at DESC
        LIMIT ${MAX_FRIENDS_FINISHED}`,
      [userId],
    ),
    db.query<{ name: string; streak: number }>(
      `WITH c AS (
         SELECT u.user_id, u.username, u.current_streak,
                (${localNowSql("u.user_id")}) AS local_now
           FROM friendships f
           JOIN users u ON u.user_id = f.friend_id
          WHERE f.user_id = $1
            AND f.status = 'accepted'
            AND u.username IS NOT NULL
            AND u.current_streak >= ${AT_RISK_MIN_STREAK}
            AND NOT EXISTS (
              SELECT 1 FROM streak_pauses p
               WHERE p.user_id = u.user_id AND p.resumed_on IS NULL AND p.expired_at IS NULL)
            AND NOT EXISTS (
              SELECT 1 FROM user_blocks b
               WHERE (b.blocker_id = $1 AND b.blocked_id = f.friend_id)
                  OR (b.blocker_id = f.friend_id AND b.blocked_id = $1))
       )
       SELECT c.username AS name, c.current_streak::int AS streak
         FROM c
        WHERE COALESCE((SELECT SUM(w.distance) FROM workouts w
                         WHERE w.user_id = c.user_id
                           AND w.local_date = (c.local_now)::date
                           AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL), 0) < 0.95
        ORDER BY c.current_streak DESC`,
      [userId],
    ),
    // The owner's own last 64 local days (the streak heatmap).
    db.query<{ miles: number; covered: boolean }>(
      `WITH tz AS (
         SELECT COALESCE((SELECT timezone_offset FROM workouts
                           WHERE user_id = $1 ORDER BY device_end_date DESC LIMIT 1), 0) AS off
       ), today AS (
         SELECT ((NOW() AT TIME ZONE 'UTC') + (tz.off || ' minutes')::interval)::date AS d FROM tz
       ), days AS (
         SELECT generate_series(today.d - ${HEATMAP_DAYS - 1}, today.d, INTERVAL '1 day')::date AS day
           FROM today
       )
       SELECT COALESCE((SELECT SUM(w.distance) FROM workouts w
                         WHERE w.user_id = $1 AND w.local_date = days.day
                           AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL), 0)::float AS miles,
              EXISTS (SELECT 1 FROM streak_coverage sc
                       WHERE sc.user_id = $1 AND sc.local_date = days.day) AS covered
         FROM days
        ORDER BY days.day`,
      [userId],
    ),
    // Desk messages to the owner. Sender shown by username only.
    db.query<{ id: string; from: string | null; text: string; age_s: number }>(
      `SELECT encode(sha256(m.id::text::bytea), 'hex') AS id,
              fu.username AS "from", m.body AS text,
              EXTRACT(EPOCH FROM (NOW() - m.created_at))::int AS age_s
         FROM display_messages m
         LEFT JOIN users fu ON fu.user_id = m.from_user_id
        WHERE m.to_user_id = $1 AND m.expires_at > NOW()
        ORDER BY m.created_at DESC
        LIMIT ${MAX_MESSAGES}`,
      [userId],
    ),
    db.query<{ flamey_look: unknown }>(`SELECT flamey_look FROM users WHERE user_id = $1`, [userId]),
    ownedFlameyItems(userId),
    // The owner's own newest medals (a badge's display name only).
    db.query<{ id: string; name: string; age_s: number }>(
      `SELECT encode(sha256(('medal:' || ub.id::text)::bytea), 'hex') AS id, b.name,
              EXTRACT(EPOCH FROM (NOW() - ub.earned_at))::int AS age_s
         FROM user_badges ub
         JOIN badges b ON b.badge_id = ub.badge_id
        WHERE ub.user_id = $1 AND ub.earned_at > NOW() - INTERVAL '${MEDAL_WINDOW_HOURS} hours'
        ORDER BY ub.earned_at DESC
        LIMIT ${MAX_MEDALS}`,
      [userId],
    ),
    db.query<{ role: string | null }>(`SELECT role FROM users WHERE user_id = $1`, [userId]),
    // Comments on posts the owner is tagged in. Same thread rule as the app
    // (postCommentMatchSql: the post, its workout, every leg of a buddy
    // walk); never their own comments; blocks either way hide a comment,
    // exactly as in the thread.
    db.query<{ id: string; from: string | null; text: string; age_s: number }>(
      `WITH tagged AS (
         SELECT p.post_id, p.workout_id, p.buddy_session_id
           FROM posts p
          WHERE p.deleted_at IS NULL AND p.user_id <> $1
            AND ((p.coauthor_user_id = $1 AND p.coauthor_status = 'accepted')
                 OR EXISTS (SELECT 1 FROM post_coauthors pca
                             WHERE pca.post_id = p.post_id AND pca.user_id = $1
                               AND pca.status = 'accepted'))
       ), hits AS (
         SELECT DISTINCT ON (c.comment_id) c.comment_id, c.user_id, c.content, c.created_at
           FROM tagged t
           JOIN post_comments c ON ${postCommentMatchSql("c", "t")}
          WHERE c.deleted_at IS NULL
            AND c.user_id <> $1
            AND c.created_at > NOW() - INTERVAL '${COMMENT_WINDOW_HOURS} hours'
            AND NOT EXISTS (
              SELECT 1 FROM user_blocks b
               WHERE (b.blocker_id = $1 AND b.blocked_id = c.user_id)
                  OR (b.blocker_id = c.user_id AND b.blocked_id = $1))
          ORDER BY c.comment_id
       )
       SELECT encode(sha256(('comment:' || h.comment_id::text)::bytea), 'hex') AS id,
              u.username AS "from", h.content AS text,
              EXTRACT(EPOCH FROM (NOW() - h.created_at))::int AS age_s
         FROM hits h
         JOIN users u ON u.user_id = h.user_id
        ORDER BY h.created_at DESC
        LIMIT ${MAX_COMMENTS}`,
      [userId],
    ),
    keyId ? getBoxSettings(keyId) : Promise.resolve(null),
    // Remote taps for THIS box (only "show": nothing else can be triggered).
    keyId
      ? db.query<{ id: string; kind: string }>(
          `SELECT encode(sha256(('cmd:' || id::text)::bytea), 'hex') AS id, kind
             FROM desk_commands
            WHERE key_id = $1 AND kind = 'show'
              AND created_at > NOW() - INTERVAL '${COMMAND_WINDOW_SECONDS} seconds'
            ORDER BY created_at DESC
            LIMIT 5`,
          [keyId],
        )
      : Promise.resolve([] as { id: string; kind: string }[]),
    // The owner's own "<friend> got their mile in!" announcements.
    db.query<{ id: string; sender: string; name: string; age_s: number }>(
      `SELECT encode(sha256(('mile:' || n.id::text)::bytea), 'hex') AS id,
              n.data->>'user_id' AS sender, su.username AS name,
              EXTRACT(EPOCH FROM (NOW() - n.created_at))::int AS age_s
         FROM in_app_notifications n
         JOIN users su ON su.user_id = (n.data->>'user_id')
        WHERE n.user_id = $1
          AND n.type = 'friend_activity'
          AND n.data->>'kind' = 'mile_completed'
          AND n.created_at > NOW() - INTERVAL '${FRIEND_MILE_WINDOW_MINUTES} minutes'
          AND (n.data->>'user_id') IS DISTINCT FROM $1
          AND su.username IS NOT NULL
          AND NOT EXISTS (
            SELECT 1 FROM user_blocks b
             WHERE (b.blocker_id = $1 AND b.blocked_id = su.user_id)
                OR (b.blocker_id = su.user_id AND b.blocked_id = $1))
        ORDER BY n.created_at DESC
        LIMIT ${MAX_FRIEND_MILES}`,
      [userId],
    ),
  ]);
  // Their day so far, the same numbers the notification shows.
  const friendStats = await Promise.all(friendMiles.map((f) => getTodayStats(f.sender).catch(() => null)));
  const isAdmin = roleRows[0]?.role === "admin";
  const reviews = isAdmin ? await latestReviews() : [];
  const look = servedFlameyLook(closetRows[0]?.flamey_look, owned);
  let flamey: Partial<Record<(typeof DESK_FLAMEY_SLOTS)[number], string>> | null = null;
  for (const slot of DESK_FLAMEY_SLOTS) {
    const item = look?.[slot];
    if (typeof item === "string") (flamey ??= {})[slot] = item;
  }

  const me = meRows[0];
  const miles = Number(todayMiles) || 0;
  const covered = Boolean(coverage[userId]);
  return {
    v: 1,
    community,
    me: {
      username: me?.username ?? null,
      mile_done: miles >= DAILY_GOAL_TOLERANCE || covered,
      miles_today: Math.round(miles * 100) / 100,
      streak: me?.streak ?? 0,
      running_now: Boolean(me?.running_now),
      local_time: me?.local_time ?? "00:00:00",
      minutes_to_midnight: me?.minutes_to_midnight ?? 0,
      year_ago_miles: me?.year_ago_miles == null ? null : Math.round(Number(me.year_ago_miles) * 100) / 100,
      local_date: me?.local_date ?? "1970-01-01",
      live_miles: me?.live_miles == null ? null : Math.round(Number(me.live_miles) * 100) / 100,
      longest_run: me?.longest_run == null ? null : Math.round(Number(me.longest_run) * 100) / 100,
      fastest_mile_month: me?.fastest_mile_month == null ? null : Math.round(Number(me.fastest_mile_month)),
      flamey,
      medals: medals.map((m) => ({
        id: m.id.slice(0, 16),
        name: sanitizeDisplayText(m.name) ?? "MEDAL",
        age_s: Math.max(0, Number(m.age_s) || 0),
      })),
      days: days.map((d) => {
        const mi = Number(d.miles) || 0;
        return mi < DAILY_GOAL_TOLERANCE && d.covered ? -1 : Math.round(mi * 10) / 10;
      }),
    },
    reviews,
    friends_miles: friendMiles.map((f, i) => ({
      id: f.id.slice(0, 16),
      name: f.name,
      miles: Math.round((friendStats[i]?.miles ?? 0) * 100) / 100,
      seconds: Math.round(friendStats[i]?.durationSeconds ?? 0),
      best_pace: friendStats[i]?.bestSplitPaceSecMi == null ? null : Math.round(friendStats[i]!.bestSplitPaceSecMi!),
      age_s: Math.max(0, Number(f.age_s) || 0),
    })),
    desk,
    commands: commands.map((c) => ({ id: c.id.slice(0, 16), kind: c.kind })),
    comments: comments.map((c) => ({
      id: c.id.slice(0, 16),
      from: c.from ?? "FRIEND",
      text: sanitizeDisplayText(c.text) ?? "",
      age_s: Math.max(0, Number(c.age_s) || 0),
    })).filter((c) => c.text),
    messages: messages.map((m) => ({
      id: m.id.slice(0, 16),
      from: m.from ?? "MILE A DAY",
      text: m.text,
      age_s: Math.max(0, Number(m.age_s) || 0),
    })),
    friends_running: friends.map((f) => ({ name: f.name, miles: Number(f.miles) || 0 })),
    friends_at_risk: {
      count: atRisk.length,
      top: atRisk.slice(0, MAX_AT_RISK_NAMES).map((r) => ({ name: r.name, streak: Number(r.streak) || 0 })),
    },
    friends_finished: finished.map((f) => ({ id: f.id.slice(0, 16), name: f.name, miles: Number(f.miles) || 0 })),
    alerts: alerts.map((a) => ({ id: a.id.slice(0, 16), kind: a.kind, from: a.from, at: a.at })),
  };
}
