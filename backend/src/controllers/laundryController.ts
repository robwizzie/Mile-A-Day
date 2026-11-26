import type { Request, Response, NextFunction } from "express";
import { listDeskBoxes } from "../services/displayService.js";
import { logError } from "../services/errorLogService.js";
import {
  cleanReadings,
  createLaundryPlug,
  getLaundryStatus,
  isMachine,
  listLaundryPlugs,
  markEmptied,
  recentLoads,
  reportReadings,
  resolveLaundryKey,
  revokeLaundryPlug,
} from "../services/laundryService.js";

/**
 * Laundry endpoints. See services/laundryService.ts for the security model.
 * Plug side: one write-only route. Owner side (under /admin, requireAdmin
 * already ran): your own plugs and machines only, and only with a desk.
 */

type PlugReq = Request & { laundryPlug?: Awaited<ReturnType<typeof resolveLaundryKey>> };

function noStore(res: Response) {
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("X-Content-Type-Options", "nosniff");
}

/** `Authorization: Laundry madl_...` (a header, never the URL). */
export async function requireLaundryKey(req: Request, res: Response, next: NextFunction) {
  noStore(res);
  const m = /^Laundry\s+(\S+)$/.exec(req.headers.authorization ?? "");
  let plug: Awaited<ReturnType<typeof resolveLaundryKey>> = null;
  try {
    plug = m ? await resolveLaundryKey(m[1]) : null;
  } catch {
    // The database, not the key: the plug keeps its readings and tries again.
    return res.status(503).json({ error: "Try again" });
  }
  if (!plug) return res.status(401).json({ error: "Invalid plug key" });
  (req as PlugReq).laundryPlug = plug;
  next();
}

/** POST /laundry/report {v:1, dt:2, on:true, p:[watts, ...]} (oldest first). */
export async function laundryReport(req: Request, res: Response) {
  const plug = (req as PlugReq).laundryPlug!;
  const r = cleanReadings(req.body);
  if (!r) return res.status(400).json({ error: "Bad readings" });
  try {
    await reportReadings(plug, r.watts, r.on);
    res.json({ ok: true });
  } catch (e: any) {
    logError("api", "laundry report failed", {
      userId: plug.userId,
      context: { message: String(e?.message ?? e).slice(0, 300) },
    });
    res.status(500).json({ error: "Try again" });
  }
}

// ─── the owner's desk remote ────────────────────────────────────────────────

const viewer = (req: Request) => (req as any).userId as string | undefined;

/** Who has laundry: user ids in LAUNDRY_USER_IDS (comma separated; default
 *  just Rob's account, whose house it's for). Ids, not usernames: a username
 *  can be changed. Everyone else gets a 404 and their remote never shows it. */
function laundryUsers(): string[] {
  return (process.env.LAUNDRY_USER_IDS ?? "f9157a851e684135bd4f459165c6197b")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}

/** Laundry is a desk feature: you need a box of your own, and to be on the
 *  list. (`anyPlug`: removing a plug works for anyone who still has one.) */
async function owner(req: Request, res: Response, anyPlug = false): Promise<string | null> {
  noStore(res);
  const me = viewer(req);
  const listed = !!me && laundryUsers().includes(me);
  if (me && !listed && anyPlug && (await listLaundryPlugs(me)).length > 0) return me;
  if (!me || !listed || (await listDeskBoxes(me)).length === 0) {
    res.status(404).json({ error: "No desk on this account" });
    return null;
  }
  return me;
}

/** GET /admin/desk/laundry: my machines, my plugs (no keys), my last loads. */
export async function adminLaundry(req: Request, res: Response) {
  const me = await owner(req, res);
  if (!me) return;
  const [status, plugs, loads] = await Promise.all([getLaundryStatus(me), listLaundryPlugs(me), recentLoads(me)]);
  res.json({ status, plugs, loads });
}

/** POST /admin/desk/laundry/plug?machine=washer|dryer: a key for that plug,
 *  shown once (it replaces the machine's old plug). */
export async function adminLaundryPlug(req: Request, res: Response) {
  const me = await owner(req, res);
  if (!me) return;
  const machine = req.query.machine;
  if (!isMachine(machine)) return res.status(400).json({ error: "machine must be washer or dryer" });
  try {
    const { key, plug } = await createLaundryPlug(me, machine);
    const base = process.env.LAUNDRY_REPORT_BASE || "https://mad.mindgoblin.tech";
    res.status(201).json({ key, plug, report_url: `${base}/laundry/report` });
  } catch (e) {
    if ((e as { code?: string })?.code === "23505") {
      return res.status(409).json({ error: "Making that plug already: try again in a moment" });
    }
    console.error("laundry plug create failed:", (e as Error)?.message);
    res.status(500).json({ error: "Could not create the plug key" });
  }
}

/** POST /admin/desk/laundry/plug/:id/revoke */
export async function adminLaundryRevoke(req: Request, res: Response) {
  const me = await owner(req, res, true);
  if (!me) return;
  if (!(await revokeLaundryPlug(me, String(req.params.id)))) return res.status(404).json({ error: "Not found" });
  res.json({ ok: true });
}

/** POST /admin/desk/laundry/:machine/emptied: no more "it's done" on the box. */
export async function adminLaundryEmptied(req: Request, res: Response) {
  const me = await owner(req, res);
  if (!me) return;
  const machine = req.params.machine;
  if (!isMachine(machine) || !(await markEmptied(me, machine))) return res.status(404).json({ error: "Not found" });
  res.json({ ok: true });
}
