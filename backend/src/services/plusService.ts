import crypto from "node:crypto";
import { PostgresService } from "./DbService.js";
import {
  FOUNDING_CUTOFF,
  PLUS_DOUBLE_DOWN_TARGET_DAYS,
  PLUS_PRODUCTS,
  PLUS_STREAK_SAVE_TARGET_RUN_DAYS,
  PLUS_STREAK_ASSIST_TARGET_DAYS,
  RENEWAL_GRACE_SQL,
  giftMonths,
  plusProductKind,
} from "./plusCatalog.js";

const db = PostgresService.getInstance();

/**
 * Mile A Day+ entitlement and ledger.
 *
 * A user is Plus when ANY of these holds right now (`plusActiveSql`):
 *   - a Founding Runner (account created before FOUNDING_CUTOFF) — for life;
 *   - a `plus_purchases` row that is unrevoked and unexpired (lifetime rows
 *     never expire; a renewing subscription gets RENEWAL_GRACE past expiry);
 *   - a redeemed, unvoided gift whose window covers now.
 * It is DERIVED on every read — nothing caches "is plus" on the user row, so a
 * refund, a lapse or a voided gift takes effect without anyone writing it.
 */

/** SQL boolean: is the users row aliased `u` Plus right now. */
export const plusActiveSql = (u: string) => `(
	${u}.created_at < '${FOUNDING_CUTOFF}'::timestamptz
	OR EXISTS (
		SELECT 1 FROM plus_purchases pp
		WHERE pp.user_id = ${u}.user_id AND pp.revoked_at IS NULL
		  AND (pp.expires_at IS NULL OR pp.expires_at > now()
		       OR (pp.auto_renew IS NOT FALSE AND pp.expires_at > now() - ${RENEWAL_GRACE_SQL})))
	OR EXISTS (
		SELECT 1 FROM plus_gifts pg
		WHERE pg.redeemed_by = ${u}.user_id AND pg.voided_at IS NULL
		  AND pg.grant_starts_at <= now() AND pg.grant_ends_at > now())
)`;

export async function isPlusActive(userId: string): Promise<boolean> {
  const rows = await db.query<{ plus: boolean }>(
    `SELECT ${plusActiveSql("u")} AS plus FROM users u WHERE u.user_id = $1`,
    [userId],
  );
  return rows[0]?.plus === true;
}

// ─── Status ────────────────────────────────────────────────────────────

export type PlusSource = "lifetime" | "subscription" | "gift" | "founding";

export interface PlusStatus {
  is_plus: boolean;
  /** What is carrying Plus right now (strongest first), null when not Plus. */
  source: PlusSource | null;
  /** When the carrying source ends; null = never (lifetime) or not Plus. */
  expires_at: string | null;
  /** Subscription only: false once the user turned auto-renew off. */
  will_renew: boolean | null;
  in_trial: boolean;
  family_shared: boolean;
  founding_runner: boolean;
  founding_ends_at: string | null;
  /** True once this account has ever started a subscription (trial eligibility hint). */
  ever_subscribed: boolean;
  products: typeof PLUS_PRODUCTS;
  perks: {
    double_down_target: number;
    streak_save_target: number;
    streak_assist_target: number;
  };
  /**
   * Which onboarding paywall this account gets (an A/B test, additive):
   * "streak" (protect-your-streak + trial timeline) or "flamey" (Flamey
   * trying on the Plus looks). Stable per account.
   */
  paywall_variant: PaywallVariant;
}

export type PaywallVariant = "streak" | "flamey";

/**
 * A stable 50/50 split by account: the first byte of sha256(user id). Same
 * answer on every read and every device, no row to write, and independent
 * of anything else hashed from the id.
 */
export function paywallVariantFor(userId: string): PaywallVariant {
  const byte = crypto.createHash("sha256").update(`paywall:${userId}`).digest()[0];
  return byte % 2 === 0 ? "streak" : "flamey";
}

interface PurchaseRow {
  kind: string;
  ownership: string;
  expires_at: string | null;
  revoked_at: string | null;
  in_trial: boolean;
  auto_renew: boolean | null;
  active: boolean;
}

export async function getPlusStatus(
  userId: string,
): Promise<PlusStatus | null> {
  const users = await db.query<{ founding: boolean }>(
    `SELECT (u.created_at < '${FOUNDING_CUTOFF}'::timestamptz) AS founding
       FROM users u WHERE u.user_id = $1`,
    [userId],
  );
  if (!users.length) return null;
  const { founding } = users[0];

  const [purchases, gifts] = await Promise.all([
    db.query<PurchaseRow>(
      `SELECT kind, ownership, expires_at, revoked_at, in_trial, auto_renew,
              (revoked_at IS NULL AND (expires_at IS NULL OR expires_at > now()
                OR (auto_renew IS NOT FALSE AND expires_at > now() - ${RENEWAL_GRACE_SQL}))) AS active
         FROM plus_purchases WHERE user_id = $1
        ORDER BY expires_at DESC NULLS FIRST`,
      [userId],
    ),
    db.query<{ grant_ends_at: string }>(
      `SELECT grant_ends_at FROM plus_gifts
        WHERE redeemed_by = $1 AND voided_at IS NULL
          AND grant_starts_at <= now() AND grant_ends_at > now()
        ORDER BY grant_ends_at DESC LIMIT 1`,
      [userId],
    ),
  ]);

  const lifetime = purchases.find((p) => p.active && p.kind === "lifetime");
  const sub = purchases.find((p) => p.active && p.kind === "subscription");
  const gift = gifts[0];

  let source: PlusSource | null = null;
  let expires_at: string | null = null;
  let carrier: PurchaseRow | undefined;
  // A Founding Runner's Plus is for life, so it outranks everything but a
  // lifetime purchase (it never expires, so expires_at stays null).
  if (lifetime) {
    source = "lifetime";
    carrier = lifetime;
  } else if (founding) {
    source = "founding";
  } else if (sub) {
    source = "subscription";
    carrier = sub;
    expires_at = sub.expires_at;
  } else if (gift) {
    source = "gift";
    expires_at = gift.grant_ends_at;
  }

  const isPlus = source !== null;
  return {
    is_plus: isPlus,
    source,
    expires_at: iso(expires_at),
    will_renew: source === "subscription" ? sub?.auto_renew !== false : null,
    in_trial: source === "subscription" && sub?.in_trial === true,
    family_shared: carrier?.ownership === "FAMILY_SHARED",
    founding_runner: founding,
    // Kept for the response shape; a Founding Runner's Plus never ends.
    founding_ends_at: null,
    ever_subscribed: purchases.some((p) => p.kind === "subscription"),
    products: PLUS_PRODUCTS,
    perks: {
      double_down_target: PLUS_DOUBLE_DOWN_TARGET_DAYS,
      streak_save_target: PLUS_STREAK_SAVE_TARGET_RUN_DAYS,
      streak_assist_target: PLUS_STREAK_ASSIST_TARGET_DAYS,
    },
    paywall_variant: paywallVariantFor(userId),
  };
}

function iso(value: string | Date | null | undefined): string | null {
  if (!value) return null;
  const d = value instanceof Date ? value : new Date(value);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

// ─── Ledger ────────────────────────────────────────────────────────────

/**
 * The fields of an Apple-signed transaction the ledger uses — always from a
 * VERIFIED payload (`appleStoreVerifier`), never from a request body.
 */
export interface VerifiedTransaction {
  originalTransactionId?: string;
  transactionId?: string;
  productId?: string;
  purchaseDate?: number;
  expiresDate?: number;
  revocationDate?: number;
  inAppOwnershipType?: string;
  environment?: string;
  appAccountToken?: string;
  offerType?: number;
  offerDiscountType?: string;
}

export interface GiftOut {
  code: string;
  display_code: string;
  product_id: string;
  months: number;
  created_at: string | null;
  redeemed: boolean;
  redeemed_at: string | null;
  redeemed_by_username: string | null;
  voided: boolean;
}

export type RecordOutcome =
  | { ok: true; kind: "subscription" | "lifetime" }
  | { ok: true; kind: "gift"; gift: GiftOut }
  | { ok: false; error: "unknown_product" | "malformed" | "not_purchaser" };

/**
 * Record one verified transaction for `userId` (the account that posted it).
 * Idempotent: a re-post (restore, relaunch, the updates stream) lands on the
 * same row and only ever moves it FORWARD (a later purchase date, or a
 * revocation state change).
 */
export async function recordTransaction(
  userId: string,
  tx: VerifiedTransaction,
): Promise<RecordOutcome> {
  const kind = plusProductKind(tx.productId);
  if (!kind) return { ok: false, error: "unknown_product" };
  if (!tx.transactionId || !tx.originalTransactionId || !tx.purchaseDate) {
    return { ok: false, error: "malformed" };
  }
  const environment = tx.environment ?? "Production";

  // A signed transaction is a bearer token — valid forever, to anyone who
  // holds it. The app stamps the buyer's id on every purchase
  // (appAccountToken), so a transaction carrying SOMEONE ELSE's id is never
  // recorded for the poster, however genuine Apple's signature is.
  // (Family Sharing members' copies are exempt: whose id Apple carries on
  // them isn't documented, and they're capped below anyway.)
  if (
    tx.appAccountToken &&
    tx.inAppOwnershipType !== "FAMILY_SHARED" &&
    !sameAccount(tx.appAccountToken, userId)
  ) {
    return { ok: false, error: "not_purchaser" };
  }

  if (kind === "gift") {
    const gift = await recordGiftPurchase(userId, tx, environment);
    return gift
      ? { ok: true, kind: "gift", gift }
      : { ok: false, error: "not_purchaser" };
  }

  if (kind === "subscription" && !tx.expiresDate)
    return { ok: false, error: "malformed" };

  // Token-less transactions (an offer code, a purchase from the App Store
  // page) belong to the first account that posts them. Family Sharing is the
  // one legitimate fan-out, capped at a family's size.
  const others = await db.query<{ n: number }>(
    `SELECT COUNT(DISTINCT user_id)::int AS n FROM plus_purchases
      WHERE original_transaction_id = $1 AND user_id <> $2`,
    [tx.originalTransactionId, userId],
  );
  const otherOwners = others[0]?.n ?? 0;
  const familyShared = tx.inAppOwnershipType === "FAMILY_SHARED";
  if (otherOwners > 0 && (!familyShared || otherOwners >= MAX_FAMILY_ACCOUNTS)) {
    return { ok: false, error: "not_purchaser" };
  }

  await upsertPurchase(userId, kind, tx, environment);
  return { ok: true, kind };
}

// The organizer plus five Family Sharing members.
const MAX_FAMILY_ACCOUNTS = 6;

function sameAccount(appAccountToken: string, userId: string): boolean {
  return appAccountToken.replace(/-/g, "").toLowerCase() === userId.toLowerCase();
}

async function upsertPurchase(
  userId: string,
  kind: "subscription" | "lifetime",
  tx: VerifiedTransaction,
  environment: string,
  autoRenew: boolean | null = null,
): Promise<void> {
  const inTrial = tx.offerType === 1 && tx.offerDiscountType === "FREE_TRIAL";
  await db.query(
    `INSERT INTO plus_purchases
       (original_transaction_id, user_id, product_id, transaction_id, kind,
        ownership, environment, purchased_at, expires_at, revoked_at, in_trial, auto_renew)
     VALUES ($1, $2, $3, $4, $5, $6, $7, to_timestamp($8::double precision / 1000),
             to_timestamp($9::double precision / 1000), to_timestamp($10::double precision / 1000),
             $11, $12)
     ON CONFLICT (original_transaction_id, user_id) DO UPDATE SET
       product_id = EXCLUDED.product_id,
       transaction_id = EXCLUDED.transaction_id,
       kind = EXCLUDED.kind,
       ownership = EXCLUDED.ownership,
       purchased_at = EXCLUDED.purchased_at,
       expires_at = EXCLUDED.expires_at,
       revoked_at = EXCLUDED.revoked_at,
       in_trial = EXCLUDED.in_trial,
       auto_renew = COALESCE(EXCLUDED.auto_renew, plus_purchases.auto_renew),
       updated_at = now()
     WHERE plus_purchases.purchased_at <= EXCLUDED.purchased_at`,
    [
      tx.originalTransactionId,
      userId,
      tx.productId,
      tx.transactionId,
      kind,
      tx.inAppOwnershipType ?? "PURCHASED",
      environment,
      tx.purchaseDate,
      kind === "lifetime" ? null : (tx.expiresDate ?? null),
      tx.revocationDate ?? null,
      inTrial,
      autoRenew,
    ],
  );
}

// ─── Gifts ─────────────────────────────────────────────────────────────

// No 0/O/1/I/L: codes get read aloud and typed from a screenshot.
const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const CODE_LENGTH = 12;

function newGiftCode(): string {
  const bytes = crypto.randomBytes(CODE_LENGTH);
  let out = "";
  for (let i = 0; i < CODE_LENGTH; i++)
    out += CODE_ALPHABET[bytes[i] % CODE_ALPHABET.length];
  return out;
}

/** "ABCD-EFGH-JKMN" — how a code is shown and shared. */
export function displayGiftCode(code: string): string {
  return code.match(/.{1,4}/g)?.join("-") ?? code;
}

/** What a person typed → the stored form (case, dashes and spaces ignored). */
export function normalizeGiftCode(input: unknown): string | null {
  if (typeof input !== "string") return null;
  const code = input.toUpperCase().replace(/[^A-Z0-9]/g, "");
  return code.length === CODE_LENGTH ? code : null;
}

const GIFT_COLUMNS = `g.code, g.product_id, g.months, g.created_at, g.redeemed_at,
	g.voided_at, g.purchaser_id, ru.username AS redeemed_by_username`;

interface GiftRow {
  code: string;
  product_id: string;
  months: number;
  created_at: string | null;
  redeemed_at: string | null;
  voided_at: string | null;
  purchaser_id: string;
  redeemed_by_username: string | null;
}

function giftOut(row: GiftRow): GiftOut {
  return {
    code: row.code,
    display_code: displayGiftCode(row.code),
    product_id: row.product_id,
    months: Number(row.months),
    created_at: iso(row.created_at),
    redeemed: row.redeemed_at !== null,
    redeemed_at: iso(row.redeemed_at),
    redeemed_by_username: row.redeemed_by_username ?? null,
    voided: row.voided_at !== null,
  };
}

/**
 * One gift purchase → one code, keyed on the Apple transaction id so a
 * re-post returns the SAME code. Null when the transaction is already on file
 * for a different purchaser (a transaction belongs to whoever posted it first).
 */
async function recordGiftPurchase(
  userId: string,
  tx: VerifiedTransaction,
  environment: string,
): Promise<GiftOut | null> {
  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      await db.query(
        `INSERT INTO plus_gifts (code, purchaser_id, transaction_id, product_id, environment, months, voided_at)
         VALUES ($1, $2, $3, $4, $5, $6, to_timestamp($7::double precision / 1000))
         ON CONFLICT (transaction_id) DO NOTHING`,
        [
          newGiftCode(),
          userId,
          tx.transactionId,
          tx.productId,
          environment,
          giftMonths(tx.productId!),
          tx.revocationDate ?? null,
        ],
      );
      break;
    } catch (err) {
      // A code collision (PK) is astronomically rare; just draw again.
      if ((err as { code?: string }).code !== "23505" || attempt === 4)
        throw err;
    }
  }
  const rows = await db.query<GiftRow>(
    `SELECT ${GIFT_COLUMNS} FROM plus_gifts g
       LEFT JOIN users ru ON ru.user_id = g.redeemed_by
      WHERE g.transaction_id = $1`,
    [tx.transactionId],
  );
  const row = rows[0];
  if (!row || row.purchaser_id !== userId) return null;
  return giftOut(row);
}

export async function listGifts(userId: string): Promise<GiftOut[]> {
  const rows = await db.query<GiftRow>(
    `SELECT ${GIFT_COLUMNS} FROM plus_gifts g
       LEFT JOIN users ru ON ru.user_id = g.redeemed_by
      WHERE g.purchaser_id = $1
      ORDER BY g.created_at DESC
      LIMIT 100`,
    [userId],
  );
  return rows.map(giftOut);
}

export type RedeemResult =
  | { ok: true; starts_at: string; ends_at: string }
  | {
      ok: false;
      error: "invalid_code" | "already_redeemed" | "gift_voided" | "already_lifetime";
    };

/**
 * Redeem a gift code. The window starts when the redeemer's other gifts
 * end, so a gift never overlaps time they already had; a paid subscription
 * is not counted — that's billed by Apple and the user manages it there.
 * Someone who already has Plus for life (a Founding Runner or a lifetime
 * purchase) is refused BEFORE the code is spent, so it can go to someone else.
 */
export async function redeemGift(
  userId: string,
  rawCode: unknown,
): Promise<RedeemResult> {
  const code = normalizeGiftCode(rawCode);
  if (!code) return { ok: false, error: "invalid_code" };

  const found = await db.query<{
    redeemed_by: string | null;
    voided_at: string | null;
  }>(`SELECT redeemed_by, voided_at FROM plus_gifts WHERE code = $1`, [code]);
  if (!found.length) return { ok: false, error: "invalid_code" };
  if (found[0].voided_at) return { ok: false, error: "gift_voided" };
  if (found[0].redeemed_by) return { ok: false, error: "already_redeemed" };

  const lifetime = await db.query(
    `SELECT 1 FROM users u
      WHERE u.user_id = $1
        AND (u.created_at < '${FOUNDING_CUTOFF}'::timestamptz
             OR EXISTS (SELECT 1 FROM plus_purchases pp
                         WHERE pp.user_id = u.user_id AND pp.kind = 'lifetime'
                           AND pp.revoked_at IS NULL))`,
    [userId],
  );
  if (lifetime.length) return { ok: false, error: "already_lifetime" };

  const rows = await db.query<{
    grant_starts_at: string;
    grant_ends_at: string;
  }>(
    `WITH start AS (
       SELECT GREATEST(
         now(),
         COALESCE((SELECT MAX(g2.grant_ends_at) FROM plus_gifts g2
                    WHERE g2.redeemed_by = $2 AND g2.voided_at IS NULL), now())) AS at
       FROM users u WHERE u.user_id = $2
     )
     UPDATE plus_gifts g
        SET redeemed_by = $2, redeemed_at = now(),
            grant_starts_at = start.at,
            grant_ends_at = start.at + make_interval(months => g.months)
       FROM start
      WHERE g.code = $1 AND g.redeemed_by IS NULL AND g.voided_at IS NULL
      RETURNING g.grant_starts_at, g.grant_ends_at`,
    [code, userId],
  );
  if (!rows.length) return { ok: false, error: "already_redeemed" };
  return {
    ok: true,
    starts_at: iso(rows[0].grant_starts_at)!,
    ends_at: iso(rows[0].grant_ends_at)!,
  };
}

// ─── App Store Server Notifications ───────────────────────────────────

/** A 32-hex MAD user id as Apple's appAccountToken (a UUID), and back. */
export function appAccountTokenFor(userId: string): string | null {
  const hex = userId.toLowerCase();
  if (!/^[0-9a-f]{32}$/.test(hex)) return null;
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export interface NotificationOutcome {
  applied: number;
}

/**
 * Apply a verified server notification's transaction (renewal, expiry,
 * refund, revoke, refund reversed …). The transaction itself carries the new
 * truth (expiresDate / revocationDate), so every type is the same upsert onto
 * the rows already on file for that original transaction. A transaction we
 * have never seen is attributed through its appAccountToken — the purchasing
 * account's id, set by the app at purchase time.
 */
export async function applyNotificationTransaction(
  tx: VerifiedTransaction,
  renewal: { autoRenewStatus?: number; gracePeriodExpiresDate?: number } | null,
): Promise<NotificationOutcome> {
  const kind = plusProductKind(tx.productId);
  if (!kind || !tx.transactionId) return { applied: 0 };
  const environment = tx.environment ?? "Production";

  if (kind === "gift") {
    // A refunded gift: void the code, which also ends any window it granted.
    if (!tx.revocationDate) return { applied: 0 };
    const rows = await db.query(
      `UPDATE plus_gifts SET voided_at = to_timestamp($2::double precision / 1000)
        WHERE transaction_id = $1 AND voided_at IS NULL RETURNING code`,
      [tx.transactionId, tx.revocationDate],
    );
    return { applied: rows.length };
  }

  if (!tx.originalTransactionId || !tx.purchaseDate) return { applied: 0 };
  const owners = await db.query<{ user_id: string }>(
    `SELECT user_id FROM plus_purchases WHERE original_transaction_id = $1`,
    [tx.originalTransactionId],
  );
  let userIds = owners.map((r) => r.user_id);
  if (!userIds.length && tx.appAccountToken) {
    const hex = tx.appAccountToken.replace(/-/g, "").toLowerCase();
    const users = await db.query<{ user_id: string }>(
      `SELECT user_id FROM users WHERE lower(user_id) = $1`,
      [hex],
    );
    userIds = users.map((r) => r.user_id);
  }
  if (!userIds.length) return { applied: 0 };

  // Billing grace: Apple keeps the subscriber entitled while it retries.
  const effective: VerifiedTransaction = { ...tx };
  if (
    kind === "subscription" &&
    renewal?.gracePeriodExpiresDate &&
    renewal.gracePeriodExpiresDate > (tx.expiresDate ?? 0)
  ) {
    effective.expiresDate = renewal.gracePeriodExpiresDate;
  }
  if (kind === "subscription" && !effective.expiresDate) return { applied: 0 };
  const autoRenew =
    renewal?.autoRenewStatus === undefined
      ? null
      : renewal.autoRenewStatus === 1;

  for (const userId of userIds) {
    await upsertPurchase(userId, kind, effective, environment, autoRenew);
    if (autoRenew !== null) {
      // A renewal-preference change can arrive with an OLDER transaction than
      // the one on file; the flag itself is always current.
      await db.query(
        `UPDATE plus_purchases SET auto_renew = $3, updated_at = now()
          WHERE original_transaction_id = $1 AND user_id = $2`,
        [tx.originalTransactionId, userId, autoRenew],
      );
    }
  }
  return { applied: userIds.length };
}
