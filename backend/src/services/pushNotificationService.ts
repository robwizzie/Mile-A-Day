import { PostgresService } from "./DbService.js";
import {
  getNotificationPreferences,
  shouldSendNotification,
} from "./notificationSettingsService.js";
import {
  resolveAudience,
  filterByIncomingAudience,
  restrictToCloseFriends,
  queuePendingFriendNotification,
  AudienceEventType,
} from "./audienceSettingsService.js";
import { hasUnlimitedActions } from "./privilegedUsers.js";
import { normalizeClientFeatures } from "./clientFeatures.js";
import { logError } from "./errorLogService.js";
import { START_OF_TODAY_ET_SQL } from "./dailyResetTime.js";
import fs from "fs";
import path from "path";
import http2 from "http2";
import jwt from "jsonwebtoken";

const db = PostgresService.getInstance();

// APNs Configuration
const APNS_KEY_PATH = process.env.APNS_KEY_PATH;
const APNS_KEY = process.env.APNS_KEY; // Key contents directly (for Coolify/cloud)
const APNS_KEY_ID = process.env.APNS_KEY_ID;
const APNS_TEAM_ID = process.env.APNS_TEAM_ID;
const APNS_BUNDLE_ID = process.env.APNS_BUNDLE_ID;
const APNS_PRODUCTION = process.env.APNS_PRODUCTION === "true";
type DeviceTokenEnvironment = "production" | "sandbox";

function apnsHostForEnvironment(environment: DeviceTokenEnvironment): string {
  return environment === "production"
    ? "https://api.push.apple.com"
    : "https://api.sandbox.push.apple.com";
}

function defaultTokenEnvironment(): DeviceTokenEnvironment {
  return APNS_PRODUCTION ? "production" : "sandbox";
}

function normalizeTokenEnvironment(
  environment?: string | null,
): DeviceTokenEnvironment {
  if (environment === "production") return "production";
  if (environment === "sandbox" || environment === "development") {
    return "sandbox";
  }
  return defaultTokenEnvironment();
}

let apnsKey: string | null = null;
let apnsToken: string | null = null;
let apnsTokenExpiry = 0;

/**
 * Normalize whatever landed in APNS_KEY into a PEM jsonwebtoken can sign with.
 *
 * Accepts the whole `.p8` file, just the base64 body, real newlines, or
 * literal `\n` escapes — an env var pasted into a dashboard arrives in all
 * four shapes and there is no shell in prod to inspect which one you got.
 *
 * Strip the armour BEFORE collapsing whitespace. The markers contain spaces,
 * so a whitespace-first pass turns `-----BEGIN PRIVATE KEY-----` into
 * `-----BEGINPRIVATEKEY-----`, the marker regex then misses, and the body is
 * re-wrapped with the old armour still nested inside. jsonwebtoken reports
 * that as "secretOrPrivateKey must be an asymmetric key when using ES256",
 * which reads like a bad key rather than a paste that needed trimming — and
 * it only reproduces in prod, where a whole key rotation gets blamed instead.
 */
export function toPem(rawKey: string): string {
  const body = rawKey
    .replace(/-----[^-]+-----/g, "") // any armour: PRIVATE KEY, EC PRIVATE KEY…
    .replace(/\\n/g, "")
    .replace(/\s/g, "");
  return `-----BEGIN PRIVATE KEY-----\n${body}\n-----END PRIVATE KEY-----\n`;
}

function loadApnsKey(): string | null {
  if (apnsKey) return apnsKey;

  // Option 1: Key contents passed directly via env var (for Coolify/cloud)
  if (APNS_KEY) {
    apnsKey = toPem(APNS_KEY);
    return apnsKey;
  }

  // Option 2: Key file path (for local dev)
  if (!APNS_KEY_PATH) {
    console.warn(
      "[Push] APNS_KEY or APNS_KEY_PATH not configured — push notifications disabled",
    );
    return null;
  }
  try {
    const keyPath = path.isAbsolute(APNS_KEY_PATH)
      ? APNS_KEY_PATH
      : path.join(process.cwd(), APNS_KEY_PATH);
    apnsKey = fs.readFileSync(keyPath, "utf8");
    return apnsKey;
  } catch (err: any) {
    console.error("[Push] Failed to load APNs key:", err.message);
    return null;
  }
}

function getApnsToken(): string | null {
  const key = loadApnsKey();
  if (!key || !APNS_KEY_ID || !APNS_TEAM_ID) return null;

  const now = Math.floor(Date.now() / 1000);
  // Refresh token every 50 minutes (APNs tokens valid for 60 min)
  if (apnsToken && now < apnsTokenExpiry) return apnsToken;

  // A malformed APNS_KEY makes jwt.sign THROW. This runs inside sendToDevice's
  // Promise executor, so an unusable key used to reject the whole fan-out and
  // surface as "Error sending hype: secretOrPrivateKey must be an asymmetric
  // key when using ES256" — i.e. a push misconfig failing the user's action.
  // Degrade to "push disabled" instead: the hype is still recorded.
  try {
    const signed = jwt.sign({}, key, {
      algorithm: "ES256",
      keyid: APNS_KEY_ID,
      issuer: APNS_TEAM_ID,
      expiresIn: "1h",
    });
    apnsToken = signed;
    apnsTokenExpiry = now + 50 * 60;
    return signed;
  } catch (err: any) {
    console.error(
      `[Push] APNs key unusable — check APNS_KEY/APNS_KEY_ID: ${err?.message}`,
    );
    return null;
  }
}

export type NotificationType =
  | "friend_request"
  // Deliberately NOT in HIGH_PRIORITY_TYPES, unlike friend_request itself: this
  // one is a nudge about something already sitting in the app, so quiet hours
  // and the daily cap must both apply to it.
  | "friend_request_reminder"
  | "friend_request_accepted"
  | "friend_nudge"
  | "friend_activity"
  | "competition_invite"
  | "competition_accepted"
  | "competition_started"
  | "competition_finished"
  | "competition_updates"
  | "competition_nudge"
  | "competition_flex"
  | "competition_milestone"
  | "streak_broken"
  | "personal_best"
  | "friend_personal_best"
  | "lead_change"
  | "clash_tie"
  | "badge_earned"
  | "friend_badge_earned"
  | "friend_challenge_completed"
  | "challenge_won"
  | "hype_received"
  | "friend_post"
  | "story_reaction"
  | "post_comment"
  | "mention"
  | "coauthor_invite"
  | "coauthor_accepted"
  | "daily_reminder"
  // The runner's OWN "mile complete" — sent from the same atomic once-per-day
  // claim that triggers friend_activity, so it fires no matter which device
  // synced the mile (Watch, locked phone, third-party app).
  | "goal_reached"
  // The runner's OWN "streak ended" — the midnight sweep told FRIENDS
  // ("send encouragement!") while the owner found out from a zeroed flame.
  // Deliberately NOT high-priority: the sweep runs near midnight, and quiet
  // hours defer this to the morning flush, when "one mile starts the next
  // one" is actionable.
  | "streak_lost"
  | "weekly_recap"
  // Streak tokens (gated by per-user enrollment + the STREAK_FEATURES_DISABLED
  // kill switch; none are high-priority, so quiet hours apply automatically).
  | "streak_double_down"
  | "streak_saved"
  // An Assist takes both sides now — the recipient's token and a mile the
  // donor ran past their goal — so these four carry the exchange:
  // `available` tells the broken user they hold the token, `offer` and
  // `request` are the two ways it opens, and `accepted` tells the donor their
  // mile landed. (`streak_assist_opportunity` is retired: it fanned out to
  // every token-holding friend, which under the new rules asks most of them
  // for a mile they haven't run.)
  | "streak_assist_available"
  | "streak_assist_offer"
  | "streak_assist_request"
  | "streak_assist_accepted"
  | "streak_assisted"
  // Buddy Walks & Runs (gated by BUDDY_SESSIONS + per-user buddy_enrolled_at).
  // Only buddy_invite is high-priority — the rest are follow-ups about a
  // session the user is already in, so quiet hours and the daily cap apply.
  | "buddy_invite"
  | "buddy_joined"
  | "buddy_started"
  | "buddy_finished"
  | "buddy_friend_active"
  // A friend beat YOUR mile as their ghost. Deliberately not high-priority and
  // not cap-exempt: it's a flourish about someone else's workout, so quiet
  // hours and the daily cap both apply.
  | "ghost_beaten";

interface PushPayload {
  title: string;
  body: string;
  type: NotificationType;
  data?: Record<string, string>;
  category?: string;
  /**
   * App icon badge count. OMIT to leave the user's badge untouched — APNs
   * treats an absent badge as "no change", which is why every other push type
   * here can stay badge-free without stomping the count.
   *
   * Never send 0 on an unrelated type for the same reason: it would clear a
   * badge the user still needs to act on. Only friend_request sets this, and
   * only behind friendRequestClientV2Enabled().
   */
  badge?: number;
}

// Send a push notification to a single device token via HTTP/2
function sendToDevice(
  deviceToken: string,
  payload: PushPayload,
  userId?: string,
  environment: DeviceTokenEnvironment = defaultTokenEnvironment(),
): Promise<boolean> {
  const tokenTail = deviceToken.slice(-8);
  return new Promise((resolve) => {
    const token = getApnsToken();
    if (!token || !APNS_BUNDLE_ID) {
      console.warn("[Push] APNs not configured, skipping push");
      resolve(false);
      return;
    }

    const aps: Record<string, any> = {
      alert: { title: payload.title, body: payload.body },
      sound: "default",
      "mutable-content": 1,
    };
    if (payload.category) aps.category = payload.category;
    if (payload.badge !== undefined) aps.badge = payload.badge;

    const apnsPayload = JSON.stringify({
      aps,
      type: payload.type,
      data: payload.data ?? {},
    });

    const client = http2.connect(apnsHostForEnvironment(environment));

    client.on("error", (err) => {
      console.error("[Push] HTTP/2 connection error:", err.message);
      logError("push", `HTTP/2 connection error: ${err.message}`, {
        userId,
        context: { type: payload.type, tokenTail, phase: "connect" },
      });
      client.close();
      resolve(false);
    });

    const req = client.request({
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      authorization: `bearer ${token}`,
      "apns-topic": APNS_BUNDLE_ID,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    });

    let responseData = "";
    let statusCode = 0;

    req.on("response", (headers) => {
      statusCode = headers[":status"] as number;
    });

    req.on("data", (chunk) => {
      responseData += chunk;
    });

    req.on("end", () => {
      client.close();
      if (statusCode === 200) {
        resolve(true);
      } else {
        console.error(`[Push] APNs error ${statusCode}: ${responseData}`);
        logError("push", `APNs error ${statusCode}`, {
          userId,
          context: {
            type: payload.type,
            tokenTail,
            environment,
            statusCode,
            response: responseData?.slice(0, 500),
          },
        });
        if (isDeadToken(statusCode, responseData)) {
          removeInvalidToken(deviceToken).catch(() => {});
        }
        resolve(false);
      }
    });

    req.on("error", (err) => {
      console.error("[Push] Request error:", err.message);
      logError("push", `Request error: ${err.message}`, {
        userId,
        context: { type: payload.type, tokenTail, phase: "request" },
      });
      client.close();
      resolve(false);
    });

    req.write(apnsPayload);
    req.end();
  });
}

/**
 * Is an APNs rejection about THIS token, or about the server's config?
 *
 * Prune on the reason string, NEVER on a bare status code. Every send now goes
 * to the host matching the token's own recorded `environment`, so the failures
 * that used to make 400 untrustworthy have their own distinct shapes: a wrong
 * or environment-restricted APNs key is 403 (`InvalidProviderToken` /
 * `BadEnvironmentKeyInToken`) and a wrong `APNS_BUNDLE_ID` is
 * `DeviceTokenNotForTopic` — none of which reach this. Anything we don't
 * recognise is left alone: deleting on a status code alone is how a
 * recoverable misconfig turns into permanent token loss.
 *
 * A wrongly-pruned token costs one missed push — the app re-registers on the
 * next launch (AppDelegate -> sendDeviceTokenToBackend). That also self-heals
 * legacy rows with no `environment`, which default to production and so 400 if
 * they're really sandbox tokens.
 */
export function isDeadToken(statusCode: number, responseData: string): boolean {
  // 410 Unregistered: APNs definitively saying the app was uninstalled.
  if (statusCode === 410) return true;
  if (statusCode !== 400) return false;
  try {
    return JSON.parse(responseData)?.reason === "BadDeviceToken";
  } catch {
    return false; // ponytail: unparseable body — not evidence of anything
  }
}

async function removeInvalidToken(deviceToken: string): Promise<void> {
  await db.query("DELETE FROM device_tokens WHERE device_token = $1", [
    deviceToken,
  ]);
  console.log(
    `[Push] Removed invalid device token: ${deviceToken.substring(0, 8)}...`,
  );
}

// ─── Smart Throttling ───────────────────────────────────────────────

const DAILY_NOTIFICATION_CAP = 18;

/**
 * Types that skip the DAILY CAP but still respect quiet hours.
 *
 * The cap exists to stop automated chatter (activity, challenges, reminders)
 * burying the user. An @mention is not chatter — it's one person addressing
 * another by name, and it's the single push where "arrived silently" is worst:
 * `sendPush` still writes the in-app row when it throttles, so the recipient
 * gets an inbox entry and no notification, which reads as the mention feature
 * being broken rather than as rate limiting.
 *
 * Quiet hours are the user's own explicit choice, so those still apply — a
 * mention during them queues and surfaces at the morning flush like anything
 * else. That's the difference from HIGH_PRIORITY_TYPES, which skip both.
 */
const CAP_EXEMPT_TYPES: NotificationType[] = [
  "mention",
  // Being tagged into someone else's post puts your name on content you
  // didn't post. That has to reach you — a throttled tag is the one case
  // where the in-app row lands and the person never learns they're on it.
  "coauthor_invite",
  // Hypes and nudges are unlimited AS A PRODUCT — one friend deliberately
  // tapping another, which is the app's whole social loop. Capping them here
  // made "unlimited" a lie the sender couldn't see: hypeService says as much
  // ("Hypes are unlimited as a product"), admins bypass every send-side limit
  // via hasUnlimitedActions, and then the recipient's 18/day budget silently
  // swallowed the push anyway.
  //
  // Their abuse backstops live on the SEND side, where they can tell who's
  // doing it, and both survive this: HYPE_DAILY_ABUSE_CEILING (50/sender/day,
  // plus dedupe on contextful hypes) and nudges' 1-per-friend-per-24h. So the
  // worst case is bounded per sender, and the recipient still has the hype
  // toggle, per-friend muting, blocking and quiet hours.
  "hype_received",
  "friend_nudge",
];

/** Single source of truth for "the daily cap does not apply to this type". */
export function isCapExempt(type: NotificationType): boolean {
  return CAP_EXEMPT_TYPES.includes(type);
}

// High-priority types bypass throttling
const HIGH_PRIORITY_TYPES: NotificationType[] = [
  "friend_request",
  "competition_invite",
  "competition_started",
  "competition_finished",
  // Flexes are time-of-day specific (you flexed because you're winning *now*);
  // queueing them past quiet hours / daily cap delivers stale taunts.
  "competition_flex",
  // Daily reminders are evaluated server-side at the user's chosen hour and
  // already filtered to users who haven't completed their mile. Queueing one
  // to the 10 AM flush would resend the same "Mile still waiting…" text the
  // next morning without rechecking — reintroducing the exact stale-text race
  // the server-side path was built to eliminate.
  "daily_reminder",
  // A buddy invite is an offer to walk RIGHT NOW — the session is starting
  // within seconds. Queueing it past quiet hours would deliver an invitation to
  // a walk that ended hours ago. Because this bypasses both quiet hours and the
  // daily cap, the notification_settings.buddy_invites_enabled toggle is the
  // only thing that can stop it, which is why that toggle ships WITH the
  // feature rather than after it (Guideline 4.5.4).
  "buddy_invite",
  // The user's own goal celebration: they JUST finished a mile, so they're
  // awake and active by definition — quiet-hours queueing a late-night
  // mile's "you did it" to tomorrow's flush is exactly the flakiness this
  // push exists to fix.
  "goal_reached",
];

async function getDailyNotificationCount(userId: string): Promise<number> {
  const result = await db.query(
    `SELECT COUNT(*) as count FROM notification_log
		WHERE user_id = $1 AND created_at > CURRENT_DATE`,
    [userId],
  );
  return parseInt(result[0]?.count ?? "0");
}

async function logNotificationSent(
  userId: string,
  type: NotificationType,
): Promise<void> {
  // notification_log exists ONLY as the daily-cap ledger — getDailyNotificationCount
  // is its sole reader (plus a 30-day cleanup). Whether a push should charge the
  // budget at all is the caller's call: see `chargesBudget` in sendPush.
  await db.query(
    "INSERT INTO notification_log (user_id, type) VALUES ($1, $2)",
    [userId, type],
  );
}

async function isUserInQuietHours(userId: string): Promise<boolean> {
  const prefs = await getNotificationPreferences(userId);
  if (prefs.quiet_hours_start === null || prefs.quiet_hours_end === null)
    return false;

  const now = new Date();
  const etHour = parseInt(
    new Intl.DateTimeFormat("en-US", {
      timeZone: "America/New_York",
      hour: "numeric",
      hour12: false,
    }).format(now),
  );

  if (prefs.quiet_hours_start > prefs.quiet_hours_end) {
    // Spans midnight (e.g., 22 to 8)
    return etHour >= prefs.quiet_hours_start || etHour < prefs.quiet_hours_end;
  }
  return etHour >= prefs.quiet_hours_start && etHour < prefs.quiet_hours_end;
}

// ─── Public API ──────────────────────────────────────────────────────

export async function sendPush(
  userId: string,
  payload: PushPayload,
  opts: { bypassDailyCap?: boolean } = {},
): Promise<void> {
  // ONE expression for "does this push consume a unit of the 18/day budget",
  // read by every notification_log write below so the throttle check and the
  // ledger can never disagree. Two ways to not charge:
  //   - cap-exempt type: it isn't subject to the cap, so it must not eat it
  //     either, or a busy day of hypes starves the reminders the cap rations.
  //   - a flush: the row was already charged when it was queued (see FLUSH_OPTS).
  const chargesBudget = !opts.bypassDailyCap && !isCapExempt(payload.type);
  // Check user's custom quiet hours
  if (!HIGH_PRIORITY_TYPES.includes(payload.type)) {
    const inQuiet = await isUserInQuietHours(userId);
    if (inQuiet) {
      console.log(
        `[Push] Quiet hours for user ${userId}, queueing "${payload.type}"`,
      );
      await db.query(
        `INSERT INTO pending_notifications (user_id, type, competition_id, competition_name)
				VALUES ($1, $2, $3, $4)`,
        [
          userId,
          payload.type,
          payload.data?.competition_id ?? null,
          payload.title,
        ],
      );
      if (chargesBudget) await logNotificationSent(userId, payload.type);
      // Still store in inbox so user can see it later
      storeInAppNotification(userId, payload).catch((err) =>
        console.error("[Push] Error storing in-app notification:", err.message),
      );
      return;
    }

    // Smart throttling: check daily cap
    const dailyCount = await getDailyNotificationCount(userId);
    if (
      !opts.bypassDailyCap &&
      dailyCount >= DAILY_NOTIFICATION_CAP &&
      !isCapExempt(payload.type)
    ) {
      console.log(
        `[Push] Throttled "${payload.type}" for user ${userId} (${dailyCount}/${DAILY_NOTIFICATION_CAP} today)`,
      );
      await db.query(
        `INSERT INTO pending_notifications (user_id, type, competition_id, competition_name)
				VALUES ($1, $2, $3, $4)`,
        [
          userId,
          payload.type,
          payload.data?.competition_id ?? null,
          payload.title,
        ],
      );
      if (chargesBudget) await logNotificationSent(userId, payload.type);
      // Still store in inbox
      storeInAppNotification(userId, payload).catch((err) =>
        console.error("[Push] Error storing in-app notification:", err.message),
      );
      return;
    }
  }

  const tokens = await db.query<{
    device_token: string;
    environment: string | null;
  }>("SELECT device_token, environment FROM device_tokens WHERE user_id = $1", [
    userId,
  ]);

  if (tokens.length === 0) {
    console.log(`[Push] No device tokens found for user ${userId}`);
    // Still store in inbox even without device tokens
    storeInAppNotification(userId, payload).catch((err) =>
      console.error("[Push] Error storing in-app notification:", err.message),
    );
    return;
  }

  const results = await Promise.all(
    tokens.map(({ device_token, environment }) =>
      sendToDevice(
        device_token,
        payload,
        userId,
        normalizeTokenEnvironment(environment),
      ),
    ),
  );

  const sent = results.filter(Boolean).length;
  if (sent > 0) {
    if (chargesBudget) await logNotificationSent(userId, payload.type);
    console.log(
      `[Push] Sent "${payload.type}" to user ${userId} (${sent}/${tokens.length} devices)`,
    );
  }

  // Always store in-app notification regardless of push delivery
  storeInAppNotification(userId, payload).catch((err) =>
    console.error("[Push] Error storing in-app notification:", err.message),
  );
}

async function storeInAppNotification(
  userId: string,
  payload: PushPayload,
): Promise<void> {
  await db.query(
    `INSERT INTO in_app_notifications (user_id, title, body, type, data)
		VALUES ($1, $2, $3, $4, $5)`,
    [
      userId,
      payload.title,
      payload.body,
      payload.type,
      JSON.stringify(payload.data ?? {}),
    ],
  );
}

export async function registerDeviceToken(
  userId: string,
  deviceToken: string,
  environment?: string | null,
  clientFeatures?: unknown,
): Promise<void> {
  const tokenEnvironment = normalizeTokenEnvironment(environment);
  // Overwritten on every registration, never merged: capabilities belong to
  // the build currently installed, and a downgrade (or a reinstall of an
  // older TestFlight build) has to be able to take them away again.
  const features = normalizeClientFeatures(clientFeatures);
  await db.query(
    `INSERT INTO device_tokens (user_id, device_token, environment, client_features)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (user_id, device_token)
		DO UPDATE SET environment = EXCLUDED.environment,
			client_features = EXCLUDED.client_features,
			updated_at = NOW()`,
    [userId, deviceToken, tokenEnvironment, features],
  );
}

export async function unregisterDeviceToken(
  userId: string,
  deviceToken: string,
): Promise<void> {
  await db.query(
    "DELETE FROM device_tokens WHERE user_id = $1 AND device_token = $2",
    [userId, deviceToken],
  );
}

// ─── Silent (background) pushes ─────────────────────────────────────

/**
 * APNs silent push. Wakes the app to do background work; renders nothing.
 * Do not call directly — use sendSilentPushToUser.
 */
function sendSilentPushToDevice(
  deviceToken: string,
  type: string,
  data: Record<string, string> = {},
  environment: DeviceTokenEnvironment = defaultTokenEnvironment(),
): Promise<boolean> {
  return new Promise((resolve) => {
    const token = getApnsToken();
    if (!token || !APNS_BUNDLE_ID) {
      console.warn("[Push] APNs not configured, skipping silent push");
      resolve(false);
      return;
    }

    const apnsPayload = JSON.stringify({
      aps: { "content-available": 1 },
      type,
      data,
    });

    const client = http2.connect(apnsHostForEnvironment(environment));

    client.on("error", (err) => {
      console.error("[Push] Silent HTTP/2 connection error:", err.message);
      client.close();
      resolve(false);
    });

    const req = client.request({
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      authorization: `bearer ${token}`,
      "apns-topic": APNS_BUNDLE_ID,
      "apns-push-type": "background",
      "apns-priority": "5",
      "content-type": "application/json",
    });

    let responseData = "";
    let statusCode = 0;

    req.on("response", (headers) => {
      statusCode = headers[":status"] as number;
    });

    req.on("data", (chunk) => {
      responseData += chunk;
    });

    req.on("end", () => {
      client.close();
      if (statusCode === 200) {
        resolve(true);
      } else {
        console.error(
          `[Push] Silent APNs error ${statusCode}: ${responseData}`,
        );
        if (isDeadToken(statusCode, responseData)) {
          removeInvalidToken(deviceToken).catch(() => {});
        }
        resolve(false);
      }
    });

    req.on("error", (err) => {
      console.error("[Push] Silent request error:", err.message);
      client.close();
      resolve(false);
    });

    req.write(apnsPayload);
    req.end();
  });
}

/**
 * Send a silent (content-available) push to every registered device of a user.
 * Skips throttling, quiet hours, in-app inbox storage, and notification_log writes.
 * These pushes are invisible to the user and have no per-day cap concern.
 */
export async function sendSilentPushToUser(
  userId: string,
  type: string,
  data: Record<string, string> = {},
): Promise<number> {
  const tokens = await db.query<{
    device_token: string;
    environment: string | null;
  }>("SELECT device_token, environment FROM device_tokens WHERE user_id = $1", [
    userId,
  ]);
  if (tokens.length === 0) return 0;

  const results = await Promise.all(
    tokens.map(({ device_token, environment }) =>
      sendSilentPushToDevice(
        device_token,
        type,
        data,
        normalizeTokenEnvironment(environment),
      ),
    ),
  );
  return results.filter(Boolean).length;
}

// ─── Quiet Hours & Batching ──────────────────────────────────────────

function isQuietHours(): boolean {
  const now = new Date();
  const etHour = parseInt(
    new Intl.DateTimeFormat("en-US", {
      timeZone: "America/New_York",
      hour: "numeric",
      hour12: false,
    }).format(now),
  );
  // Quiet hours: 10 PM (22) through 9:59 AM (9)
  return etHour >= 22 || etHour < 10;
}

export async function sendOrQueueCompetitionNotification(
  userId: string,
  type: "competition_started" | "competition_finished",
  competitionId: string,
  competitionName: string,
): Promise<void> {
  if (isQuietHours()) {
    await db.query(
      `INSERT INTO pending_notifications (user_id, type, competition_id, competition_name)
			VALUES ($1, $2, $3, $4)`,
      [userId, type, competitionId, competitionName],
    );
  } else {
    const title =
      type === "competition_started"
        ? "Competition started"
        : "Competition finished";
    const body =
      type === "competition_started"
        ? `${competitionName} has begun!`
        : `${competitionName} has finished!`;
    await sendPush(userId, {
      title,
      body,
      type,
      data: { competition_id: competitionId },
    });
  }
}

interface PendingNotification {
  id: string;
  user_id: string;
  type: string;
  competition_id: string;
  competition_name: string;
}

/**
 * For the `otherNotifs` half of the flush ONLY — deferred delivery of rows that
 * already paid, not new traffic.
 *
 * Those rows can only have come from sendPush's own quiet-hours or throttle
 * branch, and both call logNotificationSent before returning. Charging again at
 * flush double-bills the same notifications and can swallow the catch-up.
 *
 * It also repairs an exemption hole: a multi-item flush collapses everything
 * into ONE `competition_updates` digest, so a queued hype's cap exemption is
 * lost the moment it's folded in. Relabelling the digest would be worse — the
 * client routes on `type`, and a digest typed `hype_received` taps through to
 * the wrong screen.
 *
 * Do NOT extend this to the competition digest: those rows arrive uncharged
 * from sendOrQueueCompetitionNotification. The split is exact because the two
 * halves partition on competition_started/finished, which is precisely the set
 * that producer emits.
 */
const FLUSH_OPTS = { bypassDailyCap: true } as const;

export async function flushBatchedNotifications(): Promise<void> {
  const pending = await db.query<PendingNotification>(
    `SELECT id, user_id, type, competition_id, competition_name
		FROM pending_notifications
		WHERE sent_at IS NULL
		ORDER BY user_id, created_at`,
  );

  if (pending.length === 0) return;

  // Group by user
  const byUser: Record<string, PendingNotification[]> = {};
  for (const row of pending) {
    if (!byUser[row.user_id]) byUser[row.user_id] = [];
    byUser[row.user_id].push(row);
  }

  for (const [userId, notifications] of Object.entries(byUser)) {
    const compNotifs = notifications.filter(
      (n) =>
        n.type === "competition_started" || n.type === "competition_finished",
    );
    const otherNotifs = notifications.filter(
      (n) =>
        n.type !== "competition_started" && n.type !== "competition_finished",
    );

    // Handle competition start/finish notifications (batch into digest)
    if (compNotifs.length > 0) {
      const starts = compNotifs.filter((n) => n.type === "competition_started");
      const finishes = compNotifs.filter(
        (n) => n.type === "competition_finished",
      );

      let title: string;
      let body: string;
      let type: NotificationType;

      if (starts.length > 0 && finishes.length > 0) {
        title = "Competition updates";
        body =
          "You have several updates to your competitions — open to check in";
        type = "competition_updates";
      } else if (starts.length === 1) {
        title = "Competition started";
        body = `${starts[0].competition_name} has begun!`;
        type = "competition_started";
      } else if (starts.length > 1) {
        title = "Competitions started";
        body = "Multiple competitions have started — open to check in";
        type = "competition_started";
      } else if (finishes.length === 1) {
        title = "Competition finished";
        body = `${finishes[0].competition_name} has finished!`;
        type = "competition_finished";
      } else {
        title = "Competitions finished";
        body = "Multiple competitions have finished — open to check in";
        type = "competition_finished";
      }

      // NO FLUSH_OPTS here, deliberately: competition_started/finished are the
      // one kind queued by sendOrQueueCompetitionNotification, which inserts
      // straight into pending_notifications without charging the ledger. They
      // are also HIGH_PRIORITY, so sendPush's own queueing branches never see
      // them — this digest is their FIRST charge, not a second one.
      await sendPush(userId, { title, body, type });
    }

    // Handle other throttled notifications (send digest summary)
    if (otherNotifs.length > 0) {
      if (otherNotifs.length === 1) {
        // Single throttled notification: send it directly
        const n = otherNotifs[0];
        await sendPush(
          userId,
          {
            title: n.competition_name || "Notification", // competition_name stores the original title
            body: `You have a notification you missed`,
            type: (n.type as NotificationType) || "competition_updates",
          },
          FLUSH_OPTS,
        );
      } else {
        // Multiple: send digest
        await sendPush(
          userId,
          {
            title: "Catch up on activity",
            body: `You have ${otherNotifs.length} notifications from while you were away`,
            type: "competition_updates",
          },
          FLUSH_OPTS,
        );
      }
    }
  }

  // Mark all as sent
  const ids = pending.map((n) => n.id);
  await db.query(
    `UPDATE pending_notifications SET sent_at = NOW() WHERE id = ANY($1::uuid[])`,
    [ids],
  );

  console.log(
    `[Push] Flushed ${pending.length} batched notifications for ${Object.keys(byUser).length} users`,
  );
}

// ─── Nudge Rate Limiting ─────────────────────────────────────────────

export async function canNudge(
  competitionId: string,
  senderId: string,
  targetId: string,
): Promise<boolean> {
  if (await hasUnlimitedActions(senderId)) return true;
  const result = await db.query(
    `SELECT id FROM nudge_log
		WHERE competition_id = $1 AND sender_id = $2 AND target_id = $3
			AND created_at >= ${START_OF_TODAY_ET_SQL}
		LIMIT 1`,
    [competitionId, senderId, targetId],
  );
  return result.length === 0;
}

export async function logNudge(
  competitionId: string,
  senderId: string,
  targetId: string,
): Promise<void> {
  await db.query(
    `INSERT INTO nudge_log (competition_id, sender_id, target_id) VALUES ($1, $2, $3)`,
    [competitionId, senderId, targetId],
  );
}

// ─── Friend Nudge Rate Limiting ─────────────────────────────────────

/** Log truth: has the sender already nudged this friend today (ET day)?
 * Independent of any rate-limit bypass — unlimited (admin) nudgers still
 * want to SEE that they've nudged, even though they may nudge again. */
export async function hasNudgedFriendToday(
  senderId: string,
  targetId: string,
): Promise<boolean> {
  const result = await db.query(
    `SELECT id FROM friend_nudge_log
		WHERE sender_id = $1 AND target_id = $2
			AND created_at >= ${START_OF_TODAY_ET_SQL}
		LIMIT 1`,
    [senderId, targetId],
  );
  return result.length > 0;
}

export async function canFriendNudge(
  senderId: string,
  targetId: string,
): Promise<boolean> {
  if (await hasUnlimitedActions(senderId)) return true;
  return !(await hasNudgedFriendToday(senderId, targetId));
}

export async function logFriendNudge(
  senderId: string,
  targetId: string,
): Promise<void> {
  await db.query(
    `INSERT INTO friend_nudge_log (sender_id, target_id) VALUES ($1, $2)`,
    [senderId, targetId],
  );
}

// ─── Flex Rate Limiting (per sender→target per day, across all competitions) ──

export async function canFlex(
  senderId: string,
  targetId: string,
): Promise<boolean> {
  if (await hasUnlimitedActions(senderId)) return true;
  const result = await db.query(
    `SELECT id FROM flex_log
		WHERE sender_id = $1 AND target_id = $2
			AND created_at >= ${START_OF_TODAY_ET_SQL}
		LIMIT 1`,
    [senderId, targetId],
  );
  return result.length === 0;
}

export async function logFlex(
  senderId: string,
  targetId: string,
  competitionId: string,
  message: string | null,
): Promise<void> {
  await db.query(
    `INSERT INTO flex_log (sender_id, target_id, competition_id, message) VALUES ($1, $2, $3, $4)`,
    [senderId, targetId, competitionId, message],
  );
}

// ─── Badges & Challenges ────────────────────────────────────────────

interface BadgeEarnedPayload {
  badgeId: string;
  name: string;
  description: string;
  rarity: "common" | "rare" | "legendary";
  icon: string;
}

interface ChallengeCompletedPayload {
  localDate: string;
  challengeKey: string;
  challengeTitle: string;
}

/**
 * Push the user themselves when they earn a new badge.
 */
export async function fireBadgeEarnedPush(
  userId: string,
  badge: BadgeEarnedPayload,
): Promise<void> {
  await sendPush(userId, {
    title: "🏅 Medal Unlocked",
    body: `${badge.name} — ${badge.description}`,
    type: "badge_earned",
    data: {
      badge_id: badge.badgeId,
      rarity: badge.rarity,
      icon: badge.icon,
    },
  });
}

/**
 * Apply the sender's outgoing audience setting to a friend fan-out and the
 * recipients' incoming audience filter. Returns the final recipient list, or
 * null when nothing should send now ('none', or 'ask' — in which case the
 * payload has been queued in pending_friend_notifications for confirmation).
 */
async function resolveFriendFanOutRecipients(
  senderId: string,
  eventType: AudienceEventType,
  payload: PushPayload,
  workoutId: string | null = null,
): Promise<string[] | null> {
  const outgoing = await resolveAudience(senderId, "outgoing", eventType, "");
  if (outgoing === "none") return null;
  if (outgoing === "ask") {
    // Pass workoutId when available so the partial unique index dedupes
    // re-queued pendings (e.g. PR re-detection on a same-day re-upload).
    await queuePendingFriendNotification(
      senderId,
      eventType,
      "",
      workoutId,
      payload,
    );
    return null;
  }

  let friendIds = await getAcceptedFriendIds(senderId);
  if (outgoing === "close") {
    friendIds = await restrictToCloseFriends(senderId, friendIds);
  }
  if (friendIds.length === 0) return [];
  return filterByIncomingAudience(friendIds, senderId, eventType, "");
}

/**
 * Fan out a rare+ badge to every accepted friend. Throttled 1/hour per (sender, recipient).
 */
export async function fanOutFriendBadgePush(
  senderId: string,
  badge: BadgeEarnedPayload,
): Promise<void> {
  const sender = await getSenderDisplayName(senderId);
  const payload: PushPayload = {
    title: `${sender} earned a medal`,
    body: `${badge.name} — ${badge.rarity}`,
    type: "friend_badge_earned",
    data: {
      sender_id: senderId,
      badge_id: badge.badgeId,
      badge_name: badge.name,
      rarity: badge.rarity,
    },
  };

  const friendIds = await resolveFriendFanOutRecipients(
    senderId,
    "badge_earned",
    payload,
  );
  if (!friendIds || friendIds.length === 0) return;

  for (const friendId of friendIds) {
    const okToPush = await passesFriendBadgeThrottle(senderId, friendId);
    if (!okToPush) continue;

    sendPush(friendId, payload).catch((err) =>
      console.error("[Push] friend_badge_earned send failed:", err.message),
    );
  }
}

function formatPersonalBestBody(
  prType: "fastest_mile" | "most_miles_day",
  newValue: number,
): string {
  if (prType === "fastest_mile") {
    const totalSeconds = Math.round(newValue);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    const paceStr = `${minutes}:${seconds.toString().padStart(2, "0")}`;
    return `Fastest mile — ${paceStr} pace`;
  }
  const milesStr = newValue >= 10 ? newValue.toFixed(1) : newValue.toFixed(2);
  return `Most miles in a day — ${milesStr} mi`;
}

function personalBestLabel(
  prType: "fastest_mile" | "most_miles_day",
  newValue: number,
): string {
  if (prType === "fastest_mile") {
    const totalSeconds = Math.round(newValue);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `fastest mile (${minutes}:${seconds.toString().padStart(2, "0")})`;
  }
  const milesStr = newValue >= 10 ? newValue.toFixed(1) : newValue.toFixed(2);
  return `most miles in a day (${milesStr} mi)`;
}

/**
 * Fan out a personal-best to every accepted friend. No throttle — each PR
 * dimension is its own event, and a single workout breaking both PRs should
 * produce two distinct inbox rows so the viewer can hype each independently.
 */
export async function fanOutFriendPersonalBestPush(
  senderId: string,
  prType: "fastest_mile" | "most_miles_day",
  newValue: number,
  workoutId: string,
): Promise<void> {
  const sender = await getSenderDisplayName(senderId);
  const payload: PushPayload = {
    title: `${sender} set a new personal best`,
    body: formatPersonalBestBody(prType, newValue),
    type: "friend_personal_best",
    data: {
      sender_id: senderId,
      pr_type: prType,
      pr_label: personalBestLabel(prType, newValue),
      new_value: String(newValue),
      workout_id: workoutId,
    },
  };

  const friendIds = await resolveFriendFanOutRecipients(
    senderId,
    "personal_best",
    payload,
    workoutId,
  );
  if (!friendIds || friendIds.length === 0) return;

  for (const friendId of friendIds) {
    const allowed = await shouldSendNotification(
      friendId,
      senderId,
      "friend_personal_best",
    );
    if (!allowed) continue;

    sendPush(friendId, payload).catch((err) =>
      console.error("[Push] friend_personal_best send failed:", err.message),
    );
  }
}

const RACE_DISPLAY_NAMES: Record<string, string> = {
  "1mi": "1 mile",
  "2mi": "2 mile",
  "5k": "5K",
  "5mi": "5 mile",
  "10k": "10K",
  "15k": "15K",
  half: "half marathon",
  marathon: "marathon",
};

function formatRaceDuration(sec: number): string {
  const s = Math.round(sec);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const ss = s % 60;
  const pad = (n: number) => n.toString().padStart(2, "0");
  return h > 0 ? `${h}:${pad(m)}:${pad(ss)}` : `${m}:${pad(ss)}`;
}

/**
 * Fan out a race-distance PR (best time for 5K, 10K, half, etc.) to every
 * accepted friend. Reuses the friend_personal_best notification category so it
 * inherits the existing user-facing on/off toggle and audience gating — no new
 * settings surface. pr_type is `race_<key>` so clients can distinguish it.
 */
export async function fanOutFriendRacePrPush(
  senderId: string,
  distanceKey: string,
  durationSec: number,
  workoutId: string,
): Promise<void> {
  const sender = await getSenderDisplayName(senderId);
  const name = RACE_DISPLAY_NAMES[distanceKey] ?? distanceKey;
  const timeStr = formatRaceDuration(durationSec);
  const payload: PushPayload = {
    title: `${sender} set a new ${name} PR`,
    body: `${timeStr} — new personal record 🏃`,
    type: "friend_personal_best",
    data: {
      sender_id: senderId,
      pr_type: `race_${distanceKey}`,
      pr_label: `${name} PR (${timeStr})`,
      new_value: String(durationSec),
      workout_id: workoutId,
    },
  };

  const friendIds = await resolveFriendFanOutRecipients(
    senderId,
    "personal_best",
    payload,
    workoutId,
  );
  if (!friendIds || friendIds.length === 0) return;

  for (const friendId of friendIds) {
    const allowed = await shouldSendNotification(
      friendId,
      senderId,
      "friend_personal_best",
    );
    if (!allowed) continue;

    sendPush(friendId, payload).catch((err) =>
      console.error("[Push] friend_race_pr send failed:", err.message),
    );
  }
}

/**
 * Fan out a daily-challenge completion to every accepted friend.
 */
export async function fanOutFriendChallengePush(
  senderId: string,
  completion: ChallengeCompletedPayload,
): Promise<void> {
  const sender = await getSenderDisplayName(senderId);
  const payload: PushPayload = {
    title: `${sender} finished today's challenge`,
    body: completion.challengeTitle,
    type: "friend_challenge_completed",
    data: {
      sender_id: senderId,
      challenge_key: completion.challengeKey,
      challenge_title: completion.challengeTitle,
      local_date: completion.localDate,
    },
  };

  const friendIds = await resolveFriendFanOutRecipients(
    senderId,
    "challenge_completed",
    payload,
  );
  if (!friendIds || friendIds.length === 0) return;

  for (const friendId of friendIds) {
    sendPush(friendId, payload).catch((err) =>
      console.error(
        "[Push] friend_challenge_completed send failed:",
        err.message,
      ),
    );
  }
}

async function getAcceptedFriendIds(userId: string): Promise<string[]> {
  const rows = await db.query<{ friend_id: string }>(
    `SELECT friend_id FROM friendships WHERE user_id = $1 AND status = 'accepted'`,
    [userId],
  );
  return rows.map((r) => r.friend_id);
}

async function getSenderDisplayName(userId: string): Promise<string> {
  const rows = await db.query<{
    first_name: string | null;
    username: string | null;
  }>(`SELECT first_name, username FROM users WHERE user_id = $1`, [userId]);
  const row = rows[0];
  return row?.first_name || row?.username || "A friend";
}

// Throttle friend_badge_earned to at most 1 per sender→recipient per hour to avoid multi-badge-day spam.
async function passesFriendBadgeThrottle(
  senderId: string,
  recipientId: string,
): Promise<boolean> {
  const rows = await db.query<{ count: string }>(
    `SELECT COUNT(*)::text AS count FROM in_app_notifications
		WHERE user_id = $1 AND type = 'friend_badge_earned'
		  AND (data->>'sender_id') = $2
		  AND created_at > NOW() - INTERVAL '1 hour'`,
    [recipientId, senderId],
  );
  return parseInt(rows[0]?.count ?? "0", 10) === 0;
}

// ─── Cleanup ────────────────────────────────────────────────────────

/**
 * Clean up old log entries to prevent unbounded table growth.
 * Should be called daily via cron.
 */
export async function cleanupNotificationLogs(): Promise<void> {
  const results = await Promise.all([
    db.query(
      `DELETE FROM notification_log WHERE created_at < NOW() - INTERVAL '30 days'`,
    ),
    db.query(
      `DELETE FROM pending_notifications WHERE sent_at IS NOT NULL AND sent_at < NOW() - INTERVAL '7 days'`,
    ),
    db.query(
      `DELETE FROM nudge_log WHERE created_at < NOW() - INTERVAL '7 days'`,
    ),
    db.query(
      `DELETE FROM friend_nudge_log WHERE created_at < NOW() - INTERVAL '7 days'`,
    ),
    db.query(
      `DELETE FROM friend_request_log WHERE created_at < NOW() - INTERVAL '7 days'`,
    ),
    db.query(
      `DELETE FROM flex_log WHERE created_at < NOW() - INTERVAL '30 days'`,
    ),
  ]);
  console.log("[Cleanup] Cleaned up old notification logs");
}
