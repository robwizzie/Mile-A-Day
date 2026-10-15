/**
 * Mile A Day+ check — entitlement, ledger, gifts and the perks that read it.
 *
 * Every failure here is money: a subscriber who paid and isn't Plus, a
 * refunded one who still is, a gift code that works twice. Apple's signature
 * check is the library's job; this pins what WE do with a verified payload:
 *
 *   1. Founding Runners: an account created before FOUNDING_CUTOFF is Plus
 *      for life (source "founding", no expiry); one created after is not.
 *   2. Subscriptions: a verified transaction makes the poster Plus until
 *      expiresDate; re-posting is idempotent; an OLDER transaction never
 *      rolls a newer one back; a lapse ends Plus (renewing ⇒ 1-day grace,
 *      auto-renew off ⇒ none); a refund (revocationDate) ends it at once and
 *      a REFUND_REVERSED transaction restores it.
 *   3. Lifetime: never expires; strongest source; family-shared flagged.
 *   4. Unknown products / malformed transactions are ignored, never recorded.
 *   5. Gifts: one code per Apple transaction (re-post returns the SAME code),
 *      the transaction belongs to the first poster; redeem once (409 on the
 *      second, 404 on garbage, case/dash-insensitive); the window stacks after
 *      the redeemer's other gifts; someone with Plus for life (founder or
 *      lifetime) is refused and the code stays unspent; a refund VOIDS the
 *      code and ends the window it granted.
 *   6. Server notifications: attributed by original transaction, or by
 *      appAccountToken for a transaction never posted; auto-renew off is
 *      stored; billing grace extends expiry.
 *   7. Perks: Plus fills the Double Down / Streak Save / Assist meters at
 *      the Plus targets; Plus-only Flamey items are owned only while Plus, and a stored
 *      Plus look drops at read on lapse (row untouched).
 *   8. HTTP: /plus/status, /plus/gifts, /plus/gifts/redeem and the
 *      /plus/transactions body guard, self-scoped on the token.
 *
 * Usage (same env as ci-smoke):  DATABASE_URL=... node scripts/plus-check.mjs
 */
import express from "express";
import { PostgresService } from "../dist/services/DbService.js";
import { authenticateToken } from "../dist/middleware/auth.js";
import plusRoutes from "../dist/routes/plusRoutes.js";
import { generateAccessToken } from "../dist/services/tokenService.js";
import {
  FOUNDING_CUTOFF,
  PLUS_DOUBLE_DOWN_TARGET_DAYS,
  PLUS_PRODUCTS,
  PLUS_STREAK_ASSIST_TARGET_DAYS,
  PLUS_STREAK_SAVE_TARGET_RUN_DAYS,
} from "../dist/services/plusCatalog.js";
import {
  appAccountTokenFor,
  applyNotificationTransaction,
  getPlusStatus,
  isPlusActive,
  listGifts,
  recordTransaction,
  redeemGift,
} from "../dist/services/plusService.js";
import {
  DOUBLE_DOWN_TARGET_DAYS,
  STREAK_ASSIST_TARGET_DAYS,
  STREAK_SAVE_TARGET_RUN_DAYS,
  getMeters,
} from "../dist/services/streakFeatureService.js";
import { getStreakFeatureRow } from "../dist/services/streakFeatureCore.js";
import { FLAMEY_CATALOG } from "../dist/services/flameyCatalog.js";
import {
  ownedFlameyItems,
  servedFlameyLook,
} from "../dist/services/flameyService.js";

const db = PostgresService.getInstance();

// 32-hex ids, the production shape (appAccountToken needs it).
const FOUNDER = "00000000000000000000000000f0f001";
const NEWBIE = "00000000000000000000000000f0f002";
const SUBBER = "00000000000000000000000000f0f003";
const LIFER = "00000000000000000000000000f0f004";
const GIVER = "00000000000000000000000000f0f005";
const TAKER = "00000000000000000000000000f0f006";
const THIEF = "00000000000000000000000000f0f007";
const LATE = "00000000000000000000000000f0f008"; // only ever seen via a notification
const ALL = [FOUNDER, NEWBIE, SUBBER, LIFER, GIVER, TAKER, THIEF, LATE];

let failures = 0;
function check(label, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  const ok = a === e;
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${a}${ok ? "" : ` (expected ${e})`}`,
  );
}

const HOUR = 3600 * 1000;
const DAY = 24 * HOUR;
const now = Date.now();

let txSeq = 0;
function tx(productId, extra = {}) {
  txSeq++;
  return {
    originalTransactionId: `pc-orig-${txSeq}`,
    transactionId: `pc-tx-${txSeq}`,
    productId,
    purchaseDate: now - HOUR,
    inAppOwnershipType: "PURCHASED",
    environment: "Sandbox",
    ...extra,
  };
}

async function cleanup() {
  await db.query(`DELETE FROM plus_purchases WHERE user_id = ANY($1)`, [ALL]);
  await db.query(
    `DELETE FROM plus_gifts WHERE purchaser_id = ANY($1) OR redeemed_by = ANY($1)`,
    [ALL],
  );
  await db.query(`DELETE FROM user_badges WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1)`, [ALL]);
}

const app = express();
app.use(express.json({ limit: "2mb" }));
app.use(authenticateToken);
app.use("/plus", plusRoutes);
const server = await new Promise((resolve) => {
  const s = app.listen(0, "127.0.0.1", () => resolve(s));
});
const base = `http://127.0.0.1:${server.address().port}`;

async function call(method, p, userId, body) {
  const token = await generateAccessToken(userId);
  const res = await fetch(base + p, {
    method,
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${token}`,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let json = null;
  try {
    json = await res.json();
  } catch {}
  return { status: res.status, json };
}

const status = (u) => getPlusStatus(u);

try {
  await cleanup();
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, username, apple_sub, email, first_name)
       VALUES ($1::text, 'pc_' || right($1::text, 3), $1::text, $1::text || '@example.com', 'P')`,
      [id],
    );
  }
  // Everyone but the founder is "new" (after the cutoff), whatever day CI runs.
  const afterCutoff = new Date(Date.parse(FOUNDING_CUTOFF) + DAY).toISOString();
  await db.query(
    `UPDATE users SET created_at = GREATEST(now(), $2::timestamptz) WHERE user_id = ANY($1)`,
    [ALL.filter((u) => u !== FOUNDER), afterCutoff],
  );
  await db.query(
    `UPDATE users SET created_at = $2::timestamptz - interval '30 days' WHERE user_id = $1`,
    [FOUNDER, FOUNDING_CUTOFF],
  );

  // ── 1. Founding Runners ──────────────────────────────────────────────
  const f = await status(FOUNDER);
  check(
    "founder is Plus for life",
    [f.is_plus, f.source, f.expires_at],
    [true, "founding", null],
  );
  check(
    "founder flagged as Founding Runner, no end date",
    [f.founding_runner, f.founding_ends_at],
    [true, null],
  );
  check("isPlusActive agrees (founder)", await isPlusActive(FOUNDER), true);
  const n = await status(NEWBIE);
  check(
    "new account is not Plus",
    [n.is_plus, n.source, n.founding_runner],
    [false, null, false],
  );
  check("isPlusActive agrees (newbie)", await isPlusActive(NEWBIE), false);
  check("status carries product ids", n.products, PLUS_PRODUCTS);

  // ── 2. Subscriptions ─────────────────────────────────────────────────
  const sub1 = tx(PLUS_PRODUCTS.yearly, {
    expiresDate: now + 7 * DAY,
    offerType: 1,
    offerDiscountType: "FREE_TRIAL",
  });
  check("record subscription", await recordTransaction(SUBBER, sub1), {
    ok: true,
    kind: "subscription",
  });
  let s = await status(SUBBER);
  check(
    "subscriber is Plus, in trial, renewing",
    [s.is_plus, s.source, s.in_trial, s.will_renew, s.ever_subscribed],
    [true, "subscription", true, true, true],
  );
  check(
    "expires_at = transaction expiry",
    s.expires_at,
    new Date(now + 7 * DAY).toISOString(),
  );
  await recordTransaction(SUBBER, sub1);
  const rowCount = await db.query(
    `SELECT count(*)::int AS n FROM plus_purchases WHERE user_id = $1`,
    [SUBBER],
  );
  check("re-post is idempotent (one row)", rowCount[0].n, 1);

  // Renewal: same original, newer transaction, later expiry, no longer a trial.
  const renewal = {
    ...sub1,
    transactionId: "pc-tx-renew",
    purchaseDate: now,
    expiresDate: now + 372 * DAY,
    offerType: undefined,
    offerDiscountType: undefined,
  };
  await recordTransaction(SUBBER, renewal);
  s = await status(SUBBER);
  check(
    "renewal moves expiry forward and ends the trial",
    [s.expires_at, s.in_trial],
    [new Date(now + 372 * DAY).toISOString(), false],
  );
  await recordTransaction(SUBBER, sub1); // the OLD one again (e.g. a stale restore)
  s = await status(SUBBER);
  check(
    "an older transaction never rolls back a newer one",
    s.expires_at,
    new Date(now + 372 * DAY).toISOString(),
  );

  // Lapse: expired 12h ago. Renewing ⇒ still inside the 1-day grace.
  await db.query(
    `UPDATE plus_purchases SET expires_at = now() - interval '12 hours', auto_renew = NULL WHERE user_id = $1`,
    [SUBBER],
  );
  check(
    "just-expired renewing sub is inside the grace",
    await isPlusActive(SUBBER),
    true,
  );
  await db.query(
    `UPDATE plus_purchases SET auto_renew = false WHERE user_id = $1`,
    [SUBBER],
  );
  check("auto-renew off ⇒ no grace", await isPlusActive(SUBBER), false);
  s = await status(SUBBER);
  check(
    "lapsed status",
    [s.is_plus, s.source, s.ever_subscribed],
    [false, null, true],
  );
  await db.query(
    `UPDATE plus_purchases SET expires_at = now() - interval '3 days', auto_renew = NULL WHERE user_id = $1`,
    [SUBBER],
  );
  check(
    "long-expired renewing sub is not Plus",
    await isPlusActive(SUBBER),
    false,
  );

  // Refund then reversal, through the notification path.
  const sub2 = tx(PLUS_PRODUCTS.monthly, { expiresDate: now + 30 * DAY });
  await recordTransaction(SUBBER, sub2);
  check("fresh monthly is Plus", await isPlusActive(SUBBER), true);
  check(
    "REFUND notification applies to the owner",
    await applyNotificationTransaction({ ...sub2, revocationDate: now }, null),
    { applied: 1 },
  );
  check("refunded ⇒ not Plus", await isPlusActive(SUBBER), false);
  await applyNotificationTransaction(sub2, null); // REFUND_REVERSED: no revocationDate
  check("refund reversed ⇒ Plus again", await isPlusActive(SUBBER), true);
  await applyNotificationTransaction(sub2, { autoRenewStatus: 0 });
  s = await status(SUBBER);
  check("auto-renew off stored from renewal info", s.will_renew, false);

  // ── 3. Lifetime ──────────────────────────────────────────────────────
  const life = tx(PLUS_PRODUCTS.lifetime, {
    inAppOwnershipType: "FAMILY_SHARED",
  });
  check("record lifetime", await recordTransaction(LIFER, life), {
    ok: true,
    kind: "lifetime",
  });
  const l = await status(LIFER);
  check(
    "lifetime: Plus forever, family-shared",
    [l.is_plus, l.source, l.expires_at, l.family_shared],
    [true, "lifetime", null, true],
  );
  const expiresStored = await db.query(
    `SELECT expires_at FROM plus_purchases WHERE user_id = $1`,
    [LIFER],
  );
  check(
    "lifetime row never stores an expiry",
    expiresStored[0].expires_at,
    null,
  );

  // Ownership: a signed transaction is a bearer token.
  const stamped = tx(PLUS_PRODUCTS.yearly, {
    expiresDate: now + 30 * DAY,
    appAccountToken: appAccountTokenFor(SUBBER),
  });
  check("someone else's appAccountToken ⇒ refused", await recordTransaction(THIEF, stamped), {
    ok: false,
    error: "not_purchaser",
  });
  check("…and the buyer's own is accepted", await recordTransaction(SUBBER, stamped), {
    ok: true,
    kind: "subscription",
  });
  const tokenless = tx(PLUS_PRODUCTS.monthly, { expiresDate: now + 30 * DAY });
  await recordTransaction(SUBBER, tokenless);
  check("token-less: a second account can't claim it", await recordTransaction(THIEF, tokenless), {
    ok: false,
    error: "not_purchaser",
  });
  check("thief is not Plus", await isPlusActive(THIEF), false);
  await db.query(`DELETE FROM plus_purchases WHERE original_transaction_id = ANY($1)`, [
    [stamped.originalTransactionId, tokenless.originalTransactionId],
  ]);
  check("family-shared copy on a second account is allowed", await recordTransaction(TAKER, life), {
    ok: true,
    kind: "lifetime",
  });
  await db.query(`DELETE FROM plus_purchases WHERE user_id = $1`, [TAKER]);

  // ── 4. Junk ──────────────────────────────────────────────────────────
  check(
    "unknown product ignored",
    await recordTransaction(NEWBIE, tx("com.other.app.coins")),
    {
      ok: false,
      error: "unknown_product",
    },
  );
  check(
    "subscription without expiry is malformed",
    await recordTransaction(NEWBIE, tx(PLUS_PRODUCTS.monthly)),
    {
      ok: false,
      error: "malformed",
    },
  );
  check("nothing recorded for junk", await isPlusActive(NEWBIE), false);

  // ── 5. Gifts ─────────────────────────────────────────────────────────
  const giftTx = tx(PLUS_PRODUCTS.giftYear);
  const g1 = await recordTransaction(GIVER, giftTx);
  check(
    "gift purchase returns a code",
    [g1.ok, g1.kind, g1.gift?.months, g1.gift?.redeemed],
    [true, "gift", 12, false],
  );
  check(
    "code is 12 chars, displayed in 4s",
    [
      g1.gift.code.length,
      /^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$/.test(g1.gift.display_code),
    ],
    [12, true],
  );
  const g1again = await recordTransaction(GIVER, giftTx);
  check(
    "re-posting the gift returns the SAME code",
    g1again.gift?.code,
    g1.gift.code,
  );
  check(
    "another account can't claim the purchase",
    await recordTransaction(THIEF, giftTx),
    {
      ok: false,
      error: "not_purchaser",
    },
  );
  check(
    "giver isn't Plus from buying a gift",
    await isPlusActive(GIVER),
    false,
  );

  check("garbage code", await redeemGift(TAKER, "nope"), {
    ok: false,
    error: "invalid_code",
  });
  check("unknown well-formed code", await redeemGift(TAKER, "AAAA-AAAA-AAAA"), {
    ok: false,
    error: "invalid_code",
  });
  const typed = g1.gift.display_code.toLowerCase().replace(/-/g, " ");
  const r1 = await redeemGift(TAKER, typed);
  check("redeem (lower-case, spaces) works", r1.ok, true);
  const t = await status(TAKER);
  check("redeemer is Plus via gift", [t.is_plus, t.source], [true, "gift"]);
  const months = Math.round(
    (Date.parse(r1.ends_at) - Date.parse(r1.starts_at)) / (30.4 * DAY),
  );
  check("window is ~12 months", months, 12);
  check("second redeem refused", await redeemGift(THIEF, g1.gift.code), {
    ok: false,
    error: "already_redeemed",
  });
  const listed = await listGifts(GIVER);
  check(
    "giver sees it redeemed, by whom",
    [listed.length, listed[0].redeemed, listed[0].redeemed_by_username],
    [1, true, "pc_006"],
  );

  // Stacking: a second gift starts where the first ends.
  const g2 = await recordTransaction(GIVER, tx(PLUS_PRODUCTS.giftYear));
  const r2 = await redeemGift(TAKER, g2.gift.code);
  check("second gift stacks after the first", r2.starts_at, r1.ends_at);
  // Plus for life already: refused, and the code stays unspent.
  const g3 = await recordTransaction(GIVER, tx(PLUS_PRODUCTS.giftYear));
  check("founder can't redeem a gift", await redeemGift(FOUNDER, g3.gift.code), {
    ok: false,
    error: "already_lifetime",
  });
  check("lifetime buyer can't redeem a gift", await redeemGift(LIFER, g3.gift.code), {
    ok: false,
    error: "already_lifetime",
  });
  check(
    "refused code is still unredeemed",
    (await db.query(`SELECT redeemed_by FROM plus_gifts WHERE code = $1`, [g3.gift.code]))[0]
      .redeemed_by,
    null,
  );

  // Refund of the first gift voids it and ends the window it granted.
  check(
    "gift REFUND voids the code",
    await applyNotificationTransaction(
      { ...giftTx, revocationDate: now },
      null,
    ),
    { applied: 1 },
  );
  check(
    "voided gift no longer carries Plus (second hasn't started)",
    await isPlusActive(TAKER),
    false,
  );
  const g4 = await recordTransaction(GIVER, tx(PLUS_PRODUCTS.giftYear));
  await applyNotificationTransaction(
    {
      ...g4.gift,
      transactionId: `pc-tx-${txSeq}`,
      productId: PLUS_PRODUCTS.giftYear,
      revocationDate: now,
    },
    null,
  );
  check(
    "a voided, unredeemed code can't be redeemed",
    await redeemGift(NEWBIE, g4.gift.code),
    {
      ok: false,
      error: "gift_voided",
    },
  );

  // ── 6. Notifications for a never-posted transaction ─────────────────
  const lateTx = tx(PLUS_PRODUCTS.monthly, {
    expiresDate: now - DAY,
    appAccountToken: appAccountTokenFor(LATE).toUpperCase(),
  });
  check(
    "appAccountToken attributes an unseen transaction",
    await applyNotificationTransaction(lateTx, {
      gracePeriodExpiresDate: now + 5 * DAY,
    }),
    { applied: 1 },
  );
  check(
    "billing grace extends expiry",
    (await status(LATE)).expires_at,
    new Date(now + 5 * DAY).toISOString(),
  );
  check(
    "no token, no row ⇒ nothing applied",
    await applyNotificationTransaction(
      tx(PLUS_PRODUCTS.monthly, { expiresDate: now + DAY }),
      null,
    ),
    { applied: 0 },
  );
  check(
    "appAccountToken shape",
    appAccountTokenFor(LATE),
    "00000000-0000-0000-0000-000000f0f008",
  );
  check("non-hex user id has no token", appAccountTokenFor("fc-owner"), null);

  // ── 7. Perks ─────────────────────────────────────────────────────────
  const today = new Date().toISOString().slice(0, 10);
  async function seedRunDays(userId, days) {
    for (let i = 0; i < days; i++) {
      const d = new Date(Date.now() - i * DAY).toISOString().slice(0, 10);
      await db.query(
        `INSERT INTO workouts (workout_id, user_id, distance, local_date, date, timezone_offset,
                               workout_type, device_end_date, calories, total_duration)
         VALUES ($1, $2, 1.2, $3::date, $3::date, 0, 'running', $3::date + time '12:00', 100, 600)`,
        [`pc-w-${userId}-${i}`, userId, d],
      );
    }
    await db.query(
      `UPDATE users SET streak_features_at = now() - interval '60 days' WHERE user_id = $1`,
      [userId],
    );
  }
  await seedRunDays(SUBBER, 12); // Plus (active monthly)
  await seedRunDays(NEWBIE, 12); // not Plus
  const plusMeters = await getMeters(
    SUBBER,
    await getStreakFeatureRow(SUBBER),
    today,
  );
  const freeMeters = await getMeters(
    NEWBIE,
    await getStreakFeatureRow(NEWBIE),
    today,
  );
  check(
    "Plus targets",
    [plusMeters.double_down.target, plusMeters.streak_save.target],
    [PLUS_DOUBLE_DOWN_TARGET_DAYS, PLUS_STREAK_SAVE_TARGET_RUN_DAYS],
  );
  check(
    "free targets unchanged",
    [freeMeters.double_down.target, freeMeters.streak_save.target],
    [DOUBLE_DOWN_TARGET_DAYS, STREAK_SAVE_TARGET_RUN_DAYS],
  );
  check(
    "12 days: Plus holds Double Down, free doesn't yet",
    [plusMeters.double_down.held, freeMeters.double_down.held],
    [true, false],
  );
  check(
    "Assist targets",
    [plusMeters.streak_assist.target, freeMeters.streak_assist.target],
    [PLUS_STREAK_ASSIST_TARGET_DAYS, STREAK_ASSIST_TARGET_DAYS],
  );
  // Spent an Assist 20 days ago: back for Plus (14), not yet for free (30).
  await db.query(
    `UPDATE users SET streak_assist_last_used = $2::date - 20 WHERE user_id = ANY($1)`,
    [[SUBBER, NEWBIE], today],
  );
  const plusAssist = await getMeters(SUBBER, await getStreakFeatureRow(SUBBER), today);
  const freeAssist = await getMeters(NEWBIE, await getStreakFeatureRow(NEWBIE), today);
  check(
    "20 days after an Assist: Plus holds one again, free doesn't yet",
    [plusAssist.streak_assist.held, freeAssist.streak_assist.held],
    [true, false],
  );

  const plusItems = [...FLAMEY_CATALOG.values()]
    .filter((i) => i.unlock.kind === "plus")
    .map((i) => i.id);
  check("catalog has Plus items", plusItems.length > 0, true);
  const subOwned = await ownedFlameyItems(SUBBER);
  const freeOwned = await ownedFlameyItems(NEWBIE);
  check(
    "Plus owns every Plus item",
    plusItems.every((id) => subOwned.has(id)),
    true,
  );
  check(
    "free owns none",
    plusItems.some((id) => freeOwned.has(id)),
    false,
  );
  const stored = { color: plusItems[0] };
  check(
    "a Plus look serves while Plus",
    servedFlameyLook(stored, subOwned),
    stored,
  );
  await db.query(
    `UPDATE plus_purchases SET revoked_at = now() WHERE user_id = $1`,
    [SUBBER],
  );
  check(
    "…and drops at read after a lapse",
    servedFlameyLook(stored, await ownedFlameyItems(SUBBER)),
    null,
  );

  // ── 8. HTTP ──────────────────────────────────────────────────────────
  const hs = await call("GET", "/plus/status", LIFER);
  check("GET /plus/status", [hs.status, hs.json?.source], [200, "lifetime"]);
  const hg = await call("GET", "/plus/gifts", GIVER);
  check(
    "GET /plus/gifts lists the giver's gifts",
    [hg.status, hg.json?.gifts?.length],
    [200, 4],
  );
  const hgOther = await call("GET", "/plus/gifts", THIEF);
  check("…and nobody else's", hgOther.json?.gifts?.length, 0);
  const g5 = await recordTransaction(GIVER, tx(PLUS_PRODUCTS.giftYear));
  const hr = await call("POST", "/plus/gifts/redeem", NEWBIE, {
    code: g5.gift.display_code,
  });
  check(
    "POST /plus/gifts/redeem",
    [hr.status, hr.json?.status?.source],
    [200, "gift"],
  );
  const hr2 = await call("POST", "/plus/gifts/redeem", THIEF, {
    code: g5.gift.code,
  });
  check(
    "…again ⇒ 409 already_redeemed",
    [hr2.status, hr2.json?.error],
    [409, "already_redeemed"],
  );
  const hr3 = await call("POST", "/plus/gifts/redeem", THIEF, { code: "XXXX" });
  check(
    "…garbage ⇒ 404 invalid_code",
    [hr3.status, hr3.json?.error],
    [404, "invalid_code"],
  );
  for (const [label, body] of [
    ["missing", {}],
    ["empty", { signed_transactions: [] }],
    ["not strings", { signed_transactions: [1] }],
    ["too many", { signed_transactions: Array(26).fill("a.b.c") }],
  ]) {
    const r = await call("POST", "/plus/transactions", NEWBIE, body);
    check(`POST /plus/transactions ${label} ⇒ 400`, r.status, 400);
  }
  const unsigned = await call("POST", "/plus/transactions", NEWBIE, {
    signed_transactions: ["not-a-jws"],
  });
  check(
    "an unsigned blob is rejected, not recorded",
    [unsigned.status, unsigned.json?.results?.[0]],
    [200, { ok: false, error: "unverified", retryable: false }],
  );
  const noAuth = await fetch(base + "/plus/status");
  check("auth required", noAuth.status, 401);
} catch (err) {
  failures++;
  console.error("FAIL  threw:", err);
} finally {
  await cleanup().catch(() => {});
  server.close();
  await db.end?.();
}

console.log(failures ? `\n${failures} failure(s)` : "\nall plus checks passed");
process.exit(failures ? 1 : 0);
