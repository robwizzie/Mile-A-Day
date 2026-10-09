import type { Request, Response, NextFunction } from "express";
import { PostgresService } from "../services/DbService.js";
import {
  DESK_MASCOTS,
  DESK_STYLES,
  getDeskBox,
  listDeskBoxes,
  boxBelongsTo,
  DESK_TAPS,
  parseBoxState,
  queueBoxTap,
  recordBoxState,
  sendBoxMessage,
  setBoxSettings,
  createDisplayKey,
  createDisplayMessage,
  getDisplayFeed,
  listDisplayKeys,
  listDisplayMessages,
  sanitizeDisplayText,
  resolveDisplayKeyRow,
  revokeDisplayKey,
} from "../services/displayService.js";
import { logError } from "../services/errorLogService.js";

/**
 * Desk display endpoints. See services/displayService.ts for the security
 * model. Responses are never cacheable and never CORS-readable: the only
 * client is a microcontroller, not a browser.
 */

function noStore(res: Response) {
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("X-Content-Type-Options", "nosniff");
}

/** `Authorization: Display madk_...` — a header, never a query string (query
 *  strings end up in proxy and access logs). Sets req.displayUserId. */
export async function requireDisplayKey(req: Request, res: Response, next: NextFunction) {
  noStore(res);
  const header = req.headers.authorization ?? "";
  const match = /^Display\s+(\S+)$/.exec(header);
  const row = match ? await resolveDisplayKeyRow(match[1]).catch(() => null) : null;
  const userId = row?.userId;
  if (!userId) {
    // One generic answer for missing, malformed, unknown and revoked keys.
    return res.status(401).json({ error: "Invalid display key" });
  }
  (req as Request & { displayUserId?: string; displayKeyId?: string }).displayUserId = userId;
  (req as Request & { displayKeyId?: string }).displayKeyId = row!.keyId;
  next();
}

export async function displayFeed(req: Request, res: Response) {
  const userId = (req as Request & { displayUserId?: string }).displayUserId!;
  const keyId = (req as Request & { displayKeyId?: string }).displayKeyId;
  // The box says what's on its screen (style, mascot, awake, sleep hours) so
  // the phone remote can show it as it is. Strictly parsed; best effort.
  const state = parseBoxState(req.headers["x-desk-state"]);
  if (state && keyId) recordBoxState(keyId, state).catch(() => undefined);
  try {
    res.json(await getDisplayFeed(userId, keyId));
  } catch (e: any) {
    logError("api", "display feed failed", {
      userId,
      context: { message: String(e?.message ?? e).slice(0, 300) },
    });
    res.status(500).json({ error: "Feed unavailable" });
  }
}

// ─── Admin (mounted under /admin, so requireAdmin already ran) ─────────────

const db = PostgresService.getInstance();

/** GET /admin/display-keys — prefix/label/owner/dates only, never the hash. */
export async function adminListDisplayKeys(_req: Request, res: Response) {
  noStore(res);
  res.json({ keys: await listDisplayKeys() });
}

/**
 * POST /admin/display-keys?username=<name>&label=<text>
 * Mints a key for that user and returns it ONCE. (Query string because the
 * admin proxy forwards no body; the response, not the request, carries the
 * secret.)
 */
export async function adminCreateDisplayKey(req: Request, res: Response) {
  noStore(res);
  const username = typeof req.query.username === "string" ? req.query.username.trim() : "";
  const label = typeof req.query.label === "string" ? req.query.label.trim() : "";
  if (!username) return res.status(400).json({ error: "username required" });
  try {
    const users = await db.query<{ user_id: string }>(
      `SELECT user_id FROM users WHERE LOWER(username) = LOWER($1) LIMIT 2`,
      [username],
    );
    if (users.length !== 1) {
      return res.status(404).json({ error: "No single user with that username" });
    }
    const createdBy = ((req as any).userId as string) ?? null;
    const { key, row } = await createDisplayKey(users[0].user_id, label || "Desk display", createdBy);
    res.status(201).json({ key, display_key: row });
  } catch (err) {
    // Handled here so the global error logger never records this URL
    // (its query string carries the username).
    console.error("display key create failed:", (err as Error)?.message);
    res.status(500).json({ error: "Could not create key" });
  }
}

/** POST /admin/display-keys/:id/revoke */
export async function adminRevokeDisplayKey(req: Request, res: Response) {
  noStore(res);
  const id = String(req.params.id ?? "");
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) {
    return res.status(400).json({ error: "Bad id" });
  }
  const ok = await revokeDisplayKey(id);
  if (!ok) return res.status(404).json({ error: "No active key with that id" });
  res.json({ ok: true });
}


// ─── Desk-to-desk messages (admin only) ─────────────────────────────────────

export async function adminListDisplayMessages(_req: Request, res: Response) {
  noStore(res);
  res.json({ messages: await listDisplayMessages() });
}

/** POST /admin/display-messages  JSON { username, text }.
 *  Sends a short message to that user's desk display(s); expires in 24 h. */
export async function adminSendDisplayMessage(req: Request, res: Response) {
  noStore(res);
  const username = typeof req.body?.username === "string" ? req.body.username.trim() : "";
  const text = sanitizeDisplayText(req.body?.text);
  if (!username) return res.status(400).json({ error: "username required" });
  if (!text) return res.status(400).json({ error: "Message is empty after cleanup (letters, numbers and a few emoji only)" });
  try {
    const users = await db.query<{ user_id: string }>(
      `SELECT user_id FROM users WHERE LOWER(username) = LOWER($1) LIMIT 2`,
      [username],
    );
    if (users.length !== 1) {
      return res.status(404).json({ error: "No single user with that username" });
    }
    const fromUserId = ((req as any).userId as string) ?? null;
    const message = await createDisplayMessage(users[0].user_id, fromUserId, text);
    res.status(201).json({ message });
  } catch (err) {
    console.error("display message failed:", (err as Error)?.message);
    res.status(500).json({ error: "Could not send message" });
  }
}


// ─── The desk remote (Admin -> Desks). Admin only; any active box.

/** GET /admin/desk/boxes */
const viewer = (req: Request) => ((req as any).userId as string | undefined);

/** The desk remote acts only on the signed-in admin's own boxes: anyone
 *  else's box answers 404, exactly like a box that doesn't exist. */
async function ownBox(req: Request, res: Response): Promise<string | null> {
  const id = String(req.params.id ?? "");
  if (await boxBelongsTo(id, viewer(req))) return id;
  res.status(404).json({ error: "No such desk" });
  return null;
}

export async function adminDeskBoxes(req: Request, res: Response) {
  noStore(res);
  res.json({ boxes: await listDeskBoxes(viewer(req) ?? "") });
}

/** GET /admin/desk/box/:id */
export async function adminDeskBox(req: Request, res: Response) {
  noStore(res);
  try {
    const id = await ownBox(req, res);
    if (!id) return;
    const box = await getDeskBox(id);
    if (!box) return res.status(404).json({ error: "No such desk" });
    res.json(box);
  } catch (err) {
    console.error("desk box failed:", (err as Error)?.message);
    res.status(500).json({ error: "Desk unavailable" });
  }
}

function deskIndex(v: unknown, max: number): number | null | undefined {
  if (v === undefined || v === null) return null;          // leave as is
  return Number.isInteger(v) && (v as number) >= 0 && (v as number) < max ? (v as number) : undefined;
}

function minutes(v: unknown): number | undefined {
  return Number.isInteger(v) && (v as number) >= 0 && (v as number) < 1440 ? (v as number) : undefined;
}

/** POST /admin/desk/box/:id/settings
 *  JSON { style?: 0-6, mascot?: 0-1, sleep?: {start, end} (minutes) | "never" | "default" } */
export async function adminDeskBoxSettings(req: Request, res: Response) {
  noStore(res);
  const id = await ownBox(req, res);
  if (!id) return;
  const style = deskIndex(req.body?.style, DESK_STYLES.length);
  const mascot = deskIndex(req.body?.mascot, DESK_MASCOTS.length);
  const raw = req.body?.sleep;
  let sleep: [number, number] | "never" | "default" | undefined;
  if (raw === "never" || raw === "default") sleep = raw;
  else if (raw && typeof raw === "object") {
    const a = minutes(raw.start), b = minutes(raw.end);
    if (a === undefined || b === undefined || a === b) {
      return res.status(400).json({ error: "sleep needs start and end (different minutes, 0-1439)" });
    }
    sleep = [a, b];
  } else if (raw !== undefined) {
    return res.status(400).json({ error: "sleep must be {start, end}, \"never\" or \"default\"" });
  }
  if (style === undefined || mascot === undefined || (style === null && mascot === null && sleep === undefined)) {
    return res.status(400).json({ error: "style (0-6), mascot (0-1) and/or sleep required" });
  }
  const settings = await setBoxSettings(id, { style, mascot, sleep });
  if (!settings) return res.status(404).json({ error: "No such desk" });
  res.json({ settings });
}

/** POST /admin/desk/box/:id/show | /wake — stat show (real data) or wake for 30 min. */
export function adminDeskBoxTap(kind: (typeof DESK_TAPS)[number]) {
  return async (req: Request, res: Response) => {
    noStore(res);
    const id = await ownBox(req, res);
    if (!id) return;
    const ok = await queueBoxTap(id, kind);
    if (ok === null) return res.status(404).json({ error: "No such desk" });
    if (!ok) return res.status(429).json({ error: "Slow down a little" });
    res.status(201).json({ ok: true });
  };
}

/** POST /admin/desk/box/:id/message  JSON { to: <box id>, text } */
export async function adminDeskBoxMessage(req: Request, res: Response) {
  noStore(res);
  const text = sanitizeDisplayText(req.body?.text);
  const to = typeof req.body?.to === "string" ? req.body.to : "";
  if (!text) return res.status(400).json({ error: "Message is empty after cleanup (letters, numbers and a few emoji only)" });
  const id = await ownBox(req, res);
  if (!id) return;
  const message = await sendBoxMessage(id, to, text);
  if (!message) return res.status(404).json({ error: "No such desk" });
  res.status(201).json({ message });
}
