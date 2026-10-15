/**
 * Mile A Day+ — the product catalog and the fixed dates/perks around it.
 *
 * Product ids are App Store Connect identifiers and are mirrored by the iOS
 * `PlusProducts` enum: never rename one, retire it instead (a shipped build
 * keeps buying the old id). Everything a product grants is decided HERE, from
 * the id, never from anything the client says about it.
 */

export const PLUS_PRODUCTS = {
  monthly: "mad.plus.monthly",
  yearly: "mad.plus.yearly",
  lifetime: "mad.plus.lifetime",
  giftYear: "mad.plus.gift.year",
} as const;

export type PlusProductKind = "subscription" | "lifetime" | "gift";

/** product id → what it is. Unknown ids are ignored, never recorded. */
export function plusProductKind(
  productId: string | undefined | null,
): PlusProductKind | null {
  switch (productId) {
    case PLUS_PRODUCTS.monthly:
    case PLUS_PRODUCTS.yearly:
      return "subscription";
    case PLUS_PRODUCTS.lifetime:
      return "lifetime";
    case PLUS_PRODUCTS.giftYear:
      return "gift";
    default:
      return null;
  }
}

/** Months of Plus one gift product grants. */
export function giftMonths(productId: string): number {
  return productId === PLUS_PRODUCTS.giftYear ? 12 : 0;
}

/**
 * Founding Runners: every account created before Plus was announced (the
 * paid-ads push) has Plus for LIFE, derived from `users.created_at` — nothing
 * is written per user, so there is no backfill and nothing to undo, and there
 * is no end date. Never move the cutoff BACK (that takes Plus away from
 * people who were told they have it); moving it forward also widens the
 * check scripts' seeded users into Founding Runners, so seed them after it.
 */
export const FOUNDING_CUTOFF = "2026-10-15T00:00:00Z";

/**
 * Streak-token perks: Plus fills all three meters faster — Double Down in 5
 * mile days instead of 14, Streak Save in 3 runs instead of 7, and the Assist
 * allowance comes round every 14 days instead of 30. Still spent the same way
 * (an Assist still needs a friend's spare mile).
 */
export const PLUS_DOUBLE_DOWN_TARGET_DAYS = 5;
export const PLUS_STREAK_SAVE_TARGET_RUN_DAYS = 3;
export const PLUS_STREAK_ASSIST_TARGET_DAYS = 14;

/**
 * Grace after a subscription's `expires_at` while it is still set to renew:
 * a renewal lands on the device (and is posted back) the next time the app
 * opens, so a user who hasn't opened it since the renewal date shouldn't see
 * their perks blink off in between. Never applies once auto-renew is off.
 */
export const RENEWAL_GRACE_SQL = "interval '1 day'";
