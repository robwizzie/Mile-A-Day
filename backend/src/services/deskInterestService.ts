import { PostgresService } from "./DbService.js";
import { normalizeWaitlistEmail } from "./waitlistService.js";
import { pushToAdmins } from "./deskPushService.js";

const db = PostgresService.getInstance();

/** The price answers the form offers (US dollars); anything else is dropped. */
export const DESK_PRICES = ["49", "79", "99", "129+"] as const;
const NAME_MAX = 60;

/** A display name as typed, cleaned: letters, digits, spaces and a little
 *  punctuation, 1..60 chars. Null when nothing usable is left. */
export function cleanInterestName(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const name = raw.normalize("NFKC").replace(/[^\p{L}\p{N} .,'&-]/gu, "").replace(/\s+/g, " ").trim().slice(0, NAME_MAX);
  return name.length ? name : null;
}

export function cleanInterestPrice(raw: unknown): string | null {
  return typeof raw === "string" && (DESK_PRICES as readonly string[]).includes(raw) ? raw : null;
}

/** Save (or refresh) one signup. Same result whether the email is new or
 *  not, so the endpoint can't be used to test addresses. */
export async function addDeskInterest(name: string, email: string, price: string | null): Promise<void> {
  const rows = await db.query<{ inserted: boolean }>(
    `INSERT INTO desk_interest (name, email, price) VALUES ($1, $2, $3)
     ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name,
       price = COALESCE(EXCLUDED.price, desk_interest.price), updated_at = NOW()
     RETURNING (xmax = 0) AS inserted`,
    [name, email, price],
  );
  if (rows[0]?.inserted) {                      // the founders hear about new ones
    const [{ n }] = await db.query<{ n: number }>(`SELECT COUNT(*)::int AS n FROM desk_interest`);
    pushToAdmins("interest", {
      title: "Someone wants a desk box! 📦",
      body: `${name}${price ? ` would pay $${price}` : ""} · ${n} on the list`,
      tag: "interest",
    }).catch((e) => console.error("desk push (interest):", e));
  }
}

export interface DeskInterestRow { name: string; email: string; price: string | null; created_at: string }

/** Admin only: newest first, plus how many answered each price. */
export async function listDeskInterest(): Promise<{ total: number; prices: Record<string, number>; rows: DeskInterestRow[] }> {
  const [rows, counts] = await Promise.all([
    db.query<DeskInterestRow>(
      `SELECT name, email, price, to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS created_at
         FROM desk_interest ORDER BY created_at DESC LIMIT 500`,
    ),
    db.query<{ price: string | null; n: number }>(
      `SELECT price, COUNT(*)::int AS n FROM desk_interest GROUP BY price`,
    ),
  ]);
  const prices: Record<string, number> = {};
  let total = 0;
  for (const c of counts) {
    total += Number(c.n);
    prices[c.price ?? "none"] = Number(c.n);
  }
  return { total, prices, rows };
}

export { normalizeWaitlistEmail as normalizeInterestEmail };
