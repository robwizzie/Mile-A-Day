import fs from "node:fs";
import path from "node:path";
import {
  Environment,
  SignedDataVerifier,
  type JWSRenewalInfoDecodedPayload,
  type JWSTransactionDecodedPayload,
  type ResponseBodyV2DecodedPayload,
} from "@apple/app-store-server-library";

/**
 * StoreKit 2 signed-data verification (JWS, x5c chain to Apple's root CA).
 *
 * Nothing about a purchase is ever taken from the client's word: the device
 * posts Apple's SIGNED transaction and this module proves Apple signed it, for
 * THIS app, before the ledger sees a single field.
 *
 * Config (env):
 *   APPLE_BUNDLE_ID   — falls back to APNS_BUNDLE_ID (same app).
 *   APPLE_APP_ID      — the numeric App Store app id; required to verify
 *                       Production transactions (Sandbox doesn't need it).
 *   APPLE_ROOT_CERTS_DIR — optional folder of Apple root .cer files (DER).
 *                       Unset ⇒ fetched once over HTTPS from apple.com.
 *
 * Sandbox is ALWAYS accepted: App Review buys with sandbox accounts against
 * the production build, and rejecting those is a guaranteed rejection.
 * Xcode / local StoreKit testing is accepted only in NODE_ENV=development.
 */

const ROOT_CERT_URLS = [
  "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer",
  "https://www.apple.com/certificateauthority/AppleRootCA-G2.cer",
  "https://www.apple.com/certificateauthority/AppleIncRootCertificate.cer",
];

export class StoreVerificationError extends Error {
  constructor(
    /** `not_configured` = our setup (retryable); `unverified` = the data. */
    readonly code: "not_configured" | "unverified",
    message: string,
  ) {
    super(message);
  }
}

let rootCertsPromise: Promise<Buffer[]> | null = null;

async function loadRootCerts(): Promise<Buffer[]> {
  const dir = process.env.APPLE_ROOT_CERTS_DIR;
  if (dir) {
    const certs = fs
      .readdirSync(dir)
      .filter((f) => f.endsWith(".cer") || f.endsWith(".der"))
      .map((f) => fs.readFileSync(path.join(dir, f)));
    if (!certs.length) throw new Error(`no .cer files in ${dir}`);
    return certs;
  }
  const certs: Buffer[] = [];
  for (const url of ROOT_CERT_URLS) {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`${url} → HTTP ${res.status}`);
    certs.push(Buffer.from(await res.arrayBuffer()));
  }
  return certs;
}

/** Cached after the first success; a failure clears it so the next call retries. */
function rootCerts(): Promise<Buffer[]> {
  if (!rootCertsPromise) {
    rootCertsPromise = loadRootCerts().catch((err) => {
      rootCertsPromise = null;
      throw new StoreVerificationError(
        "not_configured",
        `Apple root certificates unavailable: ${err instanceof Error ? err.message : err}`,
      );
    });
  }
  return rootCertsPromise;
}

const verifiers = new Map<Environment, SignedDataVerifier>();

async function verifierFor(envName: unknown): Promise<SignedDataVerifier> {
  const bundleId = process.env.APPLE_BUNDLE_ID || process.env.APNS_BUNDLE_ID;
  if (!bundleId) {
    throw new StoreVerificationError(
      "not_configured",
      "APPLE_BUNDLE_ID is not set",
    );
  }
  let env: Environment;
  if (envName === Environment.PRODUCTION) env = Environment.PRODUCTION;
  else if (envName === Environment.SANDBOX) env = Environment.SANDBOX;
  else if (
    (envName === Environment.XCODE || envName === Environment.LOCAL_TESTING) &&
    process.env.NODE_ENV === "development"
  ) {
    env = envName;
  } else {
    throw new StoreVerificationError(
      "unverified",
      `environment ${String(envName)} not accepted`,
    );
  }

  const cached = verifiers.get(env);
  if (cached) return cached;

  let appAppleId: number | undefined;
  if (env === Environment.PRODUCTION) {
    appAppleId = Number(process.env.APPLE_APP_ID);
    if (!Number.isFinite(appAppleId) || appAppleId <= 0) {
      throw new StoreVerificationError(
        "not_configured",
        "APPLE_APP_ID is not set",
      );
    }
  }
  const verifier = new SignedDataVerifier(
    await rootCerts(),
    true,
    env,
    bundleId,
    appAppleId,
  );
  verifiers.set(env, verifier);
  return verifier;
}

/**
 * The payload of a compact JWS, UNVERIFIED — used only to pick which
 * environment's verifier to run. Nothing read here is trusted.
 */
function peekPayload(jws: string): Record<string, unknown> | null {
  const parts = jws.split(".");
  if (parts.length !== 3) return null;
  try {
    return JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
  } catch {
    return null;
  }
}

function unverified(err: unknown): never {
  if (err instanceof StoreVerificationError) throw err;
  throw new StoreVerificationError(
    "unverified",
    err instanceof Error ? err.message : String(err),
  );
}

export async function verifyTransaction(
  jws: string,
): Promise<JWSTransactionDecodedPayload> {
  const peek = peekPayload(jws);
  if (!peek) throw new StoreVerificationError("unverified", "not a JWS");
  const verifier = await verifierFor(peek.environment);
  try {
    return await verifier.verifyAndDecodeTransaction(jws);
  } catch (err) {
    unverified(err);
  }
}

export interface VerifiedNotification {
  notification: ResponseBodyV2DecodedPayload;
  transaction: JWSTransactionDecodedPayload | null;
  renewal: JWSRenewalInfoDecodedPayload | null;
}

/** An App Store Server Notification V2 `signedPayload`, with its inner JWSs. */
export async function verifyNotification(
  signedPayload: string,
): Promise<VerifiedNotification> {
  const peek = peekPayload(signedPayload);
  const data = (peek?.data ?? peek?.summary ?? {}) as Record<string, unknown>;
  const verifier = await verifierFor(data.environment);
  try {
    const notification =
      await verifier.verifyAndDecodeNotification(signedPayload);
    const signedTx = notification.data?.signedTransactionInfo;
    const signedRenewal = notification.data?.signedRenewalInfo;
    return {
      notification,
      transaction: signedTx
        ? await verifier.verifyAndDecodeTransaction(signedTx)
        : null,
      renewal: signedRenewal
        ? await verifier.verifyAndDecodeRenewalInfo(signedRenewal)
        : null,
    };
  } catch (err) {
    unverified(err);
  }
}
