import crypto from "crypto";
import { SignJWT, decodeJwt, importPKCS8 } from "jose";
import { PostgresService } from "./DbService.js";
import { logError } from "./errorLogService.js";
import { toPem } from "./pushNotificationService.js";

/**
 * Sign in with Apple token revocation (Guideline 5.1.1(v)): deleting an
 * account must revoke the user's Apple tokens through `/auth/revoke`, which
 * needs a refresh token, which only `/auth/token` can mint from a single-use
 * authorization code. So:
 *
 *   sign-in   → exchange the code, keep the refresh token encrypted in
 *               `apple_sign_in_tokens`. Best effort: never fails a sign-in.
 *   deletion  → move it to `apple_token_revocations` in the SAME transaction
 *               that removes the account, then try Apple once. Apple being
 *               down leaves the row for `sweepAppleRevocations` and the
 *               account is deleted regardless.
 *
 * Accounts from before this shipped hold no token, and the app's own refresh
 * tokens mean they may never sign in with Apple again. A client can close that
 * by sending a fresh `authorization_code` with `DELETE /users/:id`.
 *
 * Everything here is inert until the env below is set:
 *   APPLE_TEAM_ID, APPLE_CLIENT_ID      — Apple team, and the app's bundle id
 *   APPLE_SIGNIN_KEY_ID, APPLE_SIGNIN_KEY — a Sign in with Apple .p8; an APNs
 *                                           key cannot sign this client secret
 *   APPLE_TOKEN_ENCRYPTION_KEY          — base64 of 32 random bytes
 */
const db = PostgresService.getInstance();

const APPLE_AUTH = "https://appleid.apple.com";
// Both calls run inside a user's request, so a stalled Apple costs at most this.
const APPLE_TIMEOUT_MS = 4000;
// Backoff doubles from 2h to a 48h cap, so eight tries span about a week.
export const MAX_REVOCATION_ATTEMPTS = 8;
const SWEEP_BATCH = 50;

export type AppleRevocationResult = "revoked" | "pending" | "not_available";

interface AppleConfig {
  teamId: string;
  clientId: string;
  keyId: string;
  privateKey: string;
  encryptionKey: Buffer;
}

function appleConfig(): AppleConfig | null {
  const {
    APPLE_TEAM_ID: teamId,
    APPLE_CLIENT_ID: clientId,
    APPLE_SIGNIN_KEY_ID: keyId,
    APPLE_SIGNIN_KEY: rawKey,
    APPLE_TOKEN_ENCRYPTION_KEY: rawEncryptionKey,
  } = process.env;
  if (!teamId || !clientId || !keyId || !rawKey || !rawEncryptionKey) return null;
  const encryptionKey = Buffer.from(rawEncryptionKey, "base64");
  if (encryptionKey.length !== 32) {
    console.error("[appleTokens] APPLE_TOKEN_ENCRYPTION_KEY must be 32 bytes");
    return null;
  }
  return { teamId, clientId, keyId, privateKey: toPem(rawKey), encryptionKey };
}

function encryptToken(token: string, key: Buffer): string {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
  const body = Buffer.concat([cipher.update(token, "utf8"), cipher.final()]);
  return [iv, cipher.getAuthTag(), body].map((b) => b.toString("base64url")).join(".");
}

function decryptToken(stored: string, key: Buffer): string {
  const [iv, tag, body] = stored.split(".").map((p) => Buffer.from(p, "base64url"));
  const decipher = crypto.createDecipheriv("aes-256-gcm", key, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(body), decipher.final()]).toString("utf8");
}

async function clientSecret(cfg: AppleConfig, clientId: string): Promise<string> {
  const key = await importPKCS8(cfg.privateKey, "ES256");
  return new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: cfg.keyId })
    .setIssuer(cfg.teamId)
    .setSubject(clientId)
    .setAudience(APPLE_AUTH)
    .setIssuedAt()
    .setExpirationTime("5m")
    .sign(key);
}

async function postToApple(path: string, form: Record<string, string>) {
  const res = await fetch(`${APPLE_AUTH}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(form).toString(),
    signal: AbortSignal.timeout(APPLE_TIMEOUT_MS),
  });
  const body = (await res.json().catch(() => ({}))) as Record<string, unknown>;
  return { status: res.status, body };
}

/**
 * Exchange an authorization code and store the refresh token. Never throws:
 * neither signing in nor deleting an account may depend on Apple answering.
 * `expectedSub` stops a code from another Apple account being stored here,
 * which would later revoke that person's sign-in instead.
 */
export async function captureAppleRefreshToken(
  userId: string,
  authorizationCode: string,
  expectedSub: string,
): Promise<boolean> {
  const cfg = appleConfig();
  if (!cfg) return false;
  try {
    const { status, body } = await postToApple("/auth/token", {
      client_id: cfg.clientId,
      client_secret: await clientSecret(cfg, cfg.clientId),
      code: authorizationCode,
      grant_type: "authorization_code",
    });
    const refreshToken = body.refresh_token;
    if (status !== 200 || typeof refreshToken !== "string" || typeof body.id_token !== "string") {
      throw new Error(`token exchange returned ${status} ${String(body.error ?? "")}`.trim());
    }
    // Read straight from Apple over TLS, so the signature adds nothing.
    if (decodeJwt(body.id_token).sub !== expectedSub) {
      throw new Error("token exchange returned a different Apple account");
    }
    await db.query(
      `INSERT INTO apple_sign_in_tokens (user_id, encrypted_refresh_token, client_id)
       VALUES ($1, $2, $3)
       ON CONFLICT (user_id) DO UPDATE
         SET encrypted_refresh_token = EXCLUDED.encrypted_refresh_token,
             client_id = EXCLUDED.client_id,
             updated_at = now()`,
      [userId, encryptToken(refreshToken, cfg.encryptionKey), cfg.clientId],
    );
    return true;
  } catch (err) {
    console.error("[appleTokens] code exchange failed:", err);
    logError("auth", "Apple code exchange failed", {
      userId,
      context: { reason: err instanceof Error ? err.message : String(err) },
    });
    return false;
  }
}

/**
 * Splice into the account-deletion transaction, before the `users` row goes
 * (the FK would cascade the token away unrevoked). The queued row carries no
 * user id: it lives on after the account, for as long as Apple takes to answer.
 */
export function appleRevocationStatements(userId: string, revocationId: string) {
  return [
    {
      query: `INSERT INTO apple_token_revocations (id, encrypted_refresh_token, client_id)
              SELECT $2::uuid, encrypted_refresh_token, client_id
              FROM apple_sign_in_tokens WHERE user_id = $1`,
      params: [userId, revocationId],
    },
    { query: "DELETE FROM apple_sign_in_tokens WHERE user_id = $1", params: [userId] },
  ];
}

interface QueuedRevocation {
  id: string;
  encrypted_refresh_token: string;
  client_id: string;
  attempts: number;
}

/**
 * Take ownership of due rows by pushing `next_attempt_at` out, so a crash
 * mid-call retries later and a second process can't double-send.
 */
async function claimRevocations(where: string, params: unknown[]): Promise<QueuedRevocation[]> {
  return db.query<QueuedRevocation & Record<string, any>>(
    `UPDATE apple_token_revocations
     SET attempts = attempts + 1,
         next_attempt_at = now() + make_interval(hours => LEAST(power(2, attempts + 1), 48)::int)
     WHERE id IN (
       SELECT id FROM apple_token_revocations
       WHERE ${where}
       ORDER BY next_attempt_at
       LIMIT ${SWEEP_BATCH}
       FOR UPDATE SKIP LOCKED
     )
     RETURNING id, encrypted_refresh_token, client_id, attempts`,
    params,
  );
}

async function attemptRevocation(
  row: QueuedRevocation,
  cfg: AppleConfig,
): Promise<AppleRevocationResult> {
  let reason: string;
  try {
    const { status, body } = await postToApple("/auth/revoke", {
      client_id: row.client_id,
      client_secret: await clientSecret(cfg, row.client_id),
      token: decryptToken(row.encrypted_refresh_token, cfg.encryptionKey),
      token_type_hint: "refresh_token",
    });
    // 200 also covers an already-invalid token. invalid_grant says the same
    // thing, and retrying could never change it.
    if (status === 200 || body.error === "invalid_grant") {
      await db.query("DELETE FROM apple_token_revocations WHERE id = $1", [row.id]);
      return "revoked";
    }
    reason = `revoke returned ${status} ${String(body.error ?? "")}`.trim();
  } catch (err) {
    reason = err instanceof Error ? err.message : String(err);
  }

  const gaveUp = row.attempts >= MAX_REVOCATION_ATTEMPTS;
  if (gaveUp) {
    // Stop holding a token for an account that no longer exists.
    await db.query("DELETE FROM apple_token_revocations WHERE id = $1", [row.id]);
  }
  logError("auth", gaveUp ? "Apple token revocation abandoned" : "Apple token revocation failed", {
    context: { attempts: row.attempts, reason },
  });
  return "pending";
}

/**
 * The first try, straight after the deletion commits. Never throws: the
 * account is already gone, so a failure here must not read as a failed delete.
 */
export async function revokeQueuedToken(revocationId: string): Promise<AppleRevocationResult> {
  try {
    const cfg = appleConfig();
    if (!cfg) {
      const queued = await db.query("SELECT 1 FROM apple_token_revocations WHERE id = $1", [revocationId]);
      return queued.length ? "pending" : "not_available";
    }
    const [row] = await claimRevocations("id = $1", [revocationId]);
    return row ? await attemptRevocation(row, cfg) : "not_available";
  } catch (err) {
    console.error("[appleTokens] revocation attempt failed:", err);
    return "pending";
  }
}

/** Retry whatever Apple didn't take at deletion time. */
export async function sweepAppleRevocations(): Promise<void> {
  const cfg = appleConfig();
  if (!cfg) return; // Waiting on config must not use up the attempts.
  const due = await claimRevocations("next_attempt_at <= now()", []);
  for (const row of due) await attemptRevocation(row, cfg);
}
