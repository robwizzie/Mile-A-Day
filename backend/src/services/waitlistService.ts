import { PostgresService } from "./DbService.js";

const db = PostgresService.getInstance();

// Practical upper bound from RFC 5321; anything longer is garbage or abuse.
const MAX_EMAIL_LENGTH = 254;
// Deliberately loose shape check — real validation happens when we actually
// email the list. This just keeps obvious junk out of the table.
const EMAIL_SHAPE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

/** Normalize and validate a submitted email. Returns null when unusable. */
export function normalizeWaitlistEmail(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const email = raw.trim().toLowerCase();
  if (email.length === 0 || email.length > MAX_EMAIL_LENGTH) return null;
  if (!EMAIL_SHAPE.test(email)) return null;
  return email;
}

/**
 * Add an email to the Android launch waitlist. Idempotent: duplicates are
 * silently absorbed (ON CONFLICT DO NOTHING) so the endpoint never reveals
 * whether an address was already subscribed.
 */
export async function addToAndroidWaitlist(
  email: string,
  source: string,
): Promise<void> {
  await db.query(
    `INSERT INTO android_waitlist (email, source)
     VALUES ($1, $2)
     ON CONFLICT (email) DO NOTHING`,
    [email, source],
  );
}
