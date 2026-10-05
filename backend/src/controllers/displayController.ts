import type { Request, Response, NextFunction } from "express";
import { PostgresService } from "../services/DbService.js";
import {
  createDisplayKey,
  createDisplayMessage,
  getDisplayFeed,
  listDisplayKeys,
  listDisplayMessages,
  sanitizeDisplayText,
  resolveDisplayKey,
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
  const userId = match ? await resolveDisplayKey(match[1]).catch(() => null) : null;
  if (!userId) {
    // One generic answer for missing, malformed, unknown and revoked keys.
    return res.status(401).json({ error: "Invalid display key" });
  }
  (req as Request & { displayUserId?: string }).displayUserId = userId;
  next();
}

export async function displayFeed(req: Request, res: Response) {
  const userId = (req as Request & { displayUserId?: string }).displayUserId!;
  try {
    res.json(await getDisplayFeed(userId));
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
