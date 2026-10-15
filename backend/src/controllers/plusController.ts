import { Request, Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import {
  StoreVerificationError,
  verifyNotification,
  verifyTransaction,
} from "../services/appleStoreVerifier.js";
import {
  GiftOut,
  applyNotificationTransaction,
  getPlusStatus,
  listGifts,
  recordTransaction,
  redeemGift,
} from "../services/plusService.js";

/**
 * Mile A Day+ controllers. Everything authenticated is self-scoped on the
 * token (no :userId param). The one public handler is Apple's server
 * notification webhook, which authenticates by Apple's signature instead.
 */

// One post carries a restore's worth of entitlements plus a few pending
// updates; anything past this is not a real device.
const MAX_SIGNED_TRANSACTIONS = 25;
const MAX_JWS_LENGTH = 20_000;

/** GET /plus/status */
export async function plusStatusController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    const status = await getPlusStatus(req.userId!);
    if (!status) return res.status(404).json({ error: "user_not_found" });
    res.json(status);
  } catch (error) {
    console.error("[plus] status failed:", error);
    res.status(500).json({ error: "Error reading Plus status" });
  }
}

type TransactionResult =
  | { ok: true; kind: string }
  | { ok: false; error: string; retryable: boolean };

/**
 * POST /plus/transactions  { signed_transactions: string[] }
 *
 * The device posts Apple's signed StoreKit 2 transactions (after a purchase,
 * on launch, from the updates stream, on Restore). Each is verified, then
 * recorded for the posting account. `results[i]` answers `signed_transactions[i]`
 * so the app finishes exactly the transactions the server has on file.
 */
export async function postTransactionsController(
  req: AuthenticatedRequest,
  res: Response,
) {
  const list = req.body?.signed_transactions;
  if (
    !Array.isArray(list) ||
    list.length === 0 ||
    list.length > MAX_SIGNED_TRANSACTIONS ||
    !list.every(
      (s) =>
        typeof s === "string" && s.length > 0 && s.length <= MAX_JWS_LENGTH,
    )
  ) {
    return res.status(400).json({ error: "invalid_signed_transactions" });
  }

  const userId = req.userId!;
  const results: TransactionResult[] = [];
  const newGifts: GiftOut[] = [];
  let configMissing = false;

  for (const jws of list as string[]) {
    try {
      const tx = await verifyTransaction(jws);
      const outcome = await recordTransaction(userId, tx);
      if (outcome.ok) {
        results.push({ ok: true, kind: outcome.kind });
        if (outcome.kind === "gift") newGifts.push(outcome.gift);
      } else {
        results.push({ ok: false, error: outcome.error, retryable: false });
      }
    } catch (error) {
      if (error instanceof StoreVerificationError) {
        if (error.code === "not_configured") configMissing = true;
        console.warn(
          `[plus] transaction rejected (${error.code}): ${error.message}`,
        );
        results.push({
          ok: false,
          error: error.code,
          retryable: error.code === "not_configured",
        });
      } else {
        console.error("[plus] recording transaction failed:", error);
        results.push({ ok: false, error: "server_error", retryable: true });
      }
    }
  }

  if (configMissing && results.every((r) => !r.ok)) {
    return res.status(503).json({ error: "store_not_configured", results });
  }
  try {
    const status = await getPlusStatus(userId);
    res.json({ status, results, gifts: newGifts });
  } catch (error) {
    console.error("[plus] status after transactions failed:", error);
    res.status(500).json({ error: "Error reading Plus status", results });
  }
}

/** GET /plus/gifts — gifts this account bought, newest first. */
export async function listGiftsController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    res.json({ gifts: await listGifts(req.userId!) });
  } catch (error) {
    console.error("[plus] list gifts failed:", error);
    res.status(500).json({ error: "Error reading gifts" });
  }
}

/** POST /plus/gifts/redeem  { code } */
export async function redeemGiftController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    const result = await redeemGift(req.userId!, req.body?.code);
    if (!result.ok) {
      const status = result.error === "invalid_code" ? 404 : 409;
      return res.status(status).json({ error: result.error });
    }
    res.json({
      starts_at: result.starts_at,
      ends_at: result.ends_at,
      status: await getPlusStatus(req.userId!),
    });
  } catch (error) {
    console.error("[plus] redeem failed:", error);
    res.status(500).json({ error: "Error redeeming gift" });
  }
}

/**
 * POST /store/apple/notifications  { signedPayload }   (public)
 *
 * App Store Server Notifications V2. Apple retries anything but a 2xx, so a
 * payload that fails verification gets 400 (it will never verify) and our
 * own failures get 500 (worth a retry).
 */
export async function appleNotificationController(req: Request, res: Response) {
  const signedPayload = req.body?.signedPayload;
  if (typeof signedPayload !== "string" || !signedPayload) {
    return res.status(400).json({ error: "missing_signed_payload" });
  }
  try {
    const { notification, transaction, renewal } =
      await verifyNotification(signedPayload);
    let applied = 0;
    if (transaction) {
      applied = (await applyNotificationTransaction(transaction, renewal))
        .applied;
    }
    console.log(
      `[plus] notification ${notification.notificationType ?? "?"}` +
        `${notification.subtype ? `/${notification.subtype}` : ""} applied=${applied}`,
    );
    res.status(200).json({ ok: true });
  } catch (error) {
    if (
      error instanceof StoreVerificationError &&
      error.code === "unverified"
    ) {
      console.warn("[plus] notification rejected:", error.message);
      return res.status(400).json({ error: "unverified" });
    }
    console.error("[plus] notification failed:", error);
    res.status(500).json({ error: "notification_failed" });
  }
}
