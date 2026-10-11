import webpush from "web-push";
import { PostgresService } from "./DbService.js";

const db = PostgresService.getInstance();

/**
 * Web push for the desk remote: the admin panel added to a founder's home
 * screen. Notifications the iOS app doesn't already send — desk doodles and
 * messages, new users, "I'd buy one" signups, App Store reviews, record
 * signup days, the Versus lead changing hands, a desk going offline.
 *
 * Privacy:
 *  - A subscription is always the subscriber's own (the admin session's
 *    user); listing or changing one only ever touches your own rows.
 *  - Endpoints must be a real browser push service (HTTPS, known hosts), so
 *    the server never posts anywhere else on anyone's behalf.
 *  - Payloads are end-to-end encrypted by the Web Push protocol and hold only
 *    what the panel already shows that person.
 *
 * Needs VAPID_PUBLIC_KEY + VAPID_PRIVATE_KEY (npx web-push generate-vapid-keys)
 * and optionally VAPID_SUBJECT; without them everything here is a no-op.
 */

export const DESK_PUSH_KINDS = [
  "doodle", "message", "new_user", "user_milestone", "interest", "review", "record", "lead", "box_offline",
] as const;
export type DeskPushKind = (typeof DESK_PUSH_KINDS)[number] | "test";
/** On for a new phone unless it opts out (offline alerts are opt-in). */
export const DEFAULT_KINDS: DeskPushKind[] = DESK_PUSH_KINDS.filter((k) => k !== "box_offline");

const PUSH_HOSTS = [
  /(^|\.)push\.apple\.com$/,
  /^fcm\.googleapis\.com$/,
  /^android\.googleapis\.com$/,
  /^updates\.push\.services\.mozilla\.com$/,
  /^push\.services\.mozilla\.com$/,
  /(^|\.)notify\.windows\.com$/,
];
const MAX_FAILURES = 10;

export interface PushPayload { title: string; body: string; url?: string; tag?: string }
export interface WebPushSubscription { endpoint: string; keys: { p256dh: string; auth: string } }

type Sender = (sub: WebPushSubscription, payload: string) => Promise<void>;
let sender: Sender | null = null;
let vapidReady = false;

export function pushConfigured(): boolean {
  return Boolean(process.env.VAPID_PUBLIC_KEY && process.env.VAPID_PRIVATE_KEY) || sender !== null;
}

export function vapidPublicKey(): string | null {
  return process.env.VAPID_PUBLIC_KEY || null;
}

/** Tests: capture pushes instead of sending them. */
export function setPushSenderForTests(fn: Sender | null) {
  sender = fn;
}

async function deliver(sub: WebPushSubscription, payload: string) {
  if (sender) return sender(sub, payload);
  if (!vapidReady) {
    webpush.setVapidDetails(process.env.VAPID_SUBJECT || "mailto:support@mileaday.run",
      process.env.VAPID_PUBLIC_KEY!, process.env.VAPID_PRIVATE_KEY!);
    vapidReady = true;
  }
  await webpush.sendNotification(sub, payload, { TTL: 6 * 3600, urgency: "normal" });
}

/** A browser push subscription we're willing to post to, cleaned; else null. */
export function cleanSubscription(raw: unknown): WebPushSubscription | null {
  const s = raw as any;
  const endpoint = typeof s?.endpoint === "string" ? s.endpoint : "";
  const p256dh = typeof s?.keys?.p256dh === "string" ? s.keys.p256dh : "";
  const auth = typeof s?.keys?.auth === "string" ? s.keys.auth : "";
  if (endpoint.length > 1024 || !/^[A-Za-z0-9_-]{80,100}={0,2}$/.test(p256dh) || !/^[A-Za-z0-9_-]{16,32}={0,2}$/.test(auth)) {
    return null;
  }
  let url: URL;
  try {
    url = new URL(endpoint);
  } catch {
    return null;
  }
  if (url.protocol !== "https:" || url.port || url.username || url.password) return null;
  if (!PUSH_HOSTS.some((re) => re.test(url.hostname))) return null;
  return { endpoint: url.toString(), keys: { p256dh, auth } };
}

export function cleanKinds(raw: unknown): DeskPushKind[] | null {
  if (!Array.isArray(raw) || raw.length > DESK_PUSH_KINDS.length) return null;
  const out = [...new Set(raw)].filter((k): k is DeskPushKind => (DESK_PUSH_KINDS as readonly unknown[]).includes(k));
  return out.length === new Set(raw).size ? out : null;
}

/** Subscribe this browser for `userId` (a browser belongs to whoever subscribed last). */
export async function saveSubscription(userId: string, sub: WebPushSubscription, kinds: DeskPushKind[]) {
  await db.query(
    `INSERT INTO desk_push_subscriptions (user_id, endpoint, p256dh, auth, kinds)
     VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (endpoint) DO UPDATE SET user_id = EXCLUDED.user_id, p256dh = EXCLUDED.p256dh,
       auth = EXCLUDED.auth, kinds = EXCLUDED.kinds, failures = 0`,
    [userId, sub.endpoint, sub.keys.p256dh, sub.keys.auth, kinds],
  );
}

export async function setKinds(userId: string, endpoint: string, kinds: DeskPushKind[]): Promise<boolean> {
  const rows = await db.query(
    `UPDATE desk_push_subscriptions SET kinds = $3 WHERE user_id = $1 AND endpoint = $2 RETURNING id`,
    [userId, endpoint, kinds],
  );
  return rows.length > 0;
}

export async function removeSubscription(userId: string, endpoint: string): Promise<boolean> {
  const rows = await db.query(
    `DELETE FROM desk_push_subscriptions WHERE user_id = $1 AND endpoint = $2 RETURNING id`, [userId, endpoint]);
  return rows.length > 0;
}

/** Your own phones: which push service, what they get. No keys. */
export async function listSubscriptions(userId: string) {
  const rows = await db.query<{ id: string; endpoint: string; kinds: string[]; created_at: string; last_ok_at: string | null }>(
    `SELECT id, endpoint, kinds, created_at::text, last_ok_at::text
       FROM desk_push_subscriptions WHERE user_id = $1 ORDER BY created_at DESC`, [userId]);
  return rows.map((r) => ({
    id: r.id,
    endpoint: r.endpoint,
    service: new URL(r.endpoint).hostname.includes("apple") ? "Apple" : new URL(r.endpoint).hostname.includes("google") ? "Google" : "Browser",
    kinds: r.kinds,
    created_at: r.created_at,
    last_ok_at: r.last_ok_at,
  }));
}

/** Send to every subscription of `userIds` that wants `kind`. Dead ones are dropped. */
export async function pushTo(userIds: string[], kind: DeskPushKind, payload: PushPayload): Promise<number> {
  if (!pushConfigured() || userIds.length === 0) return 0;
  const subs = await db.query<{ id: string; endpoint: string; p256dh: string; auth: string }>(
    `SELECT id, endpoint, p256dh, auth FROM desk_push_subscriptions
      WHERE user_id = ANY($1::text[]) AND ($2 = 'test' OR $2 = ANY(kinds))`,
    [userIds, kind],
  );
  const body = JSON.stringify({ ...payload, url: payload.url ?? "/admin/desk", kind });
  let sent = 0;
  await Promise.all(subs.map(async (s) => {
    try {
      await deliver({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, body);
      sent++;
      await db.query(`UPDATE desk_push_subscriptions SET last_ok_at = NOW(), failures = 0 WHERE id = $1`, [s.id]);
    } catch (e: any) {
      const code = Number(e?.statusCode);
      if (code === 404 || code === 410) {
        await db.query(`DELETE FROM desk_push_subscriptions WHERE id = $1`, [s.id]);
      } else {
        await db.query(
          `UPDATE desk_push_subscriptions SET failures = failures + 1 WHERE id = $1`, [s.id]);
        await db.query(`DELETE FROM desk_push_subscriptions WHERE id = $1 AND failures >= ${MAX_FAILURES}`, [s.id]);
      }
    }
  }));
  return sent;
}

/** Founder notifications: every admin account. */
export async function pushToAdmins(kind: DeskPushKind, payload: PushPayload): Promise<number> {
  const admins = await db.query<{ user_id: string }>(`SELECT user_id FROM users WHERE role = 'admin'`);
  return pushTo(admins.map((a) => a.user_id), kind, payload);
}

// ─── the poller's memory ──────────────────────────────────────────────────

export async function getState(key: string): Promise<string | null> {
  const rows = await db.query<{ value: string }>(`SELECT value FROM desk_push_state WHERE key = $1`, [key]);
  return rows[0]?.value ?? null;
}

export async function setState(key: string, value: string) {
  await db.query(
    `INSERT INTO desk_push_state (key, value) VALUES ($1, $2)
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()`, [key, value]);
}

/** Desk tokens ([FIRE] etc.) back to emoji for a notification. */
export function prettyTokens(t: string): string {
  return t.replace(/\[FIRE\]/g, "🔥").replace(/\[HEART\]/g, "❤️").replace(/\[CLAP\]/g, "👏").replace(/\[RUN\]/g, "🏃");
}
