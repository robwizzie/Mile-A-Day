import { PostgresService } from "./DbService.js";
import { sendPush } from "./pushNotificationService.js";
import { allowedRecipients } from "./notificationSettingsService.js";
import { CLIENT_FEATURES } from "./clientFeatures.js";
import { userOffsetMinutesSql } from "./dailyResetTime.js";
import { logError } from "./errorLogService.js";
import { BadRequestError } from "../errors/Errors.js";

const db = PostgresService.getInstance();

/**
 * "Tell me when they're out": a per-friend switch that pings you when that
 * friend starts a walk, so the friends you walk with most don't depend on you
 * happening to look at the app.
 *
 * Friends-out has always been PULL ONLY, and that stays true for everyone who
 * didn't ask: nothing here is sent unless the RECIPIENT turned it on for that
 * one friend. The walker's own `share_live_presence` still decides whether
 * they can be seen out at all (off = no alerts about them, ever), blocks
 * either way stop it, the recipient's buddy switch and per-friend mute apply
 * (`allowedRecipients`), and it rings at most once per friend per day (the
 * walker's local day, `buddy_out_alert_log`). Who follows whom is never shown
 * to the friend.
 */

const SHARES_PRESENCE_SQL = (userColumn: string) => `COALESCE(
    (SELECT ns.share_live_presence FROM notification_settings ns
      WHERE ns.user_id = ${userColumn}),
    TRUE
  )`;

/** Friends `userId` asked to hear about, that they can still hear about. */
export async function listOutAlerts(userId: string): Promise<string[]> {
  const rows = await db.query<{ friend_id: string }>(
    `SELECT a.friend_id FROM buddy_out_alerts a
      WHERE a.user_id = $1
        AND EXISTS (
          SELECT 1 FROM friendships f
           WHERE f.user_id = $1 AND f.friend_id = a.friend_id AND f.status = 'accepted'
        )
      ORDER BY a.created_at`,
    [userId],
  );
  return rows.map((r) => r.friend_id);
}

/**
 * Turn the switch on or off for one friend. On needs an accepted friendship
 * and no block either way (`not_friends`); off always succeeds.
 */
export async function setOutAlert(
  userId: string,
  friendId: string,
  enabled: boolean,
): Promise<boolean> {
  if (!friendId || friendId === userId)
    throw new BadRequestError("invalid_friend");
  if (!enabled) {
    await db.query(
      `DELETE FROM buddy_out_alerts WHERE user_id = $1 AND friend_id = $2`,
      [userId, friendId],
    );
    return false;
  }
  const rows = await db.query<{ ok: number }>(
    `INSERT INTO buddy_out_alerts (user_id, friend_id)
     SELECT $1::text, $2::text
      WHERE EXISTS (
        SELECT 1 FROM friendships f
         WHERE f.user_id = $1 AND f.friend_id = $2 AND f.status = 'accepted'
      )
        AND NOT EXISTS (
        SELECT 1 FROM user_blocks b
         WHERE (b.blocker_id = $1 AND b.blocked_id = $2)
            OR (b.blocker_id = $2 AND b.blocked_id = $1)
      )
     ON CONFLICT (user_id, friend_id) DO NOTHING
     RETURNING 1 AS ok`,
    [userId, friendId],
  );
  if (rows.length === 0) {
    const existing = await db.query<{ ok: number }>(
      `SELECT 1 AS ok FROM buddy_out_alerts WHERE user_id = $1 AND friend_id = $2`,
      [userId, friendId],
    );
    if (existing.length === 0) throw new BadRequestError("not_friends");
  }
  return true;
}

/**
 * `walkerId` just started a walk: ping everyone who asked about them and
 * hasn't been pinged about them today. Claimed per (subscriber, walker,
 * walker's local day) BEFORE sending, so two starts racing each other send
 * once. Never throws; returns how many were sent.
 */
export async function notifyOutAlertSubscribers(
  walkerId: string,
  workoutType: string | null | undefined,
): Promise<number> {
  try {
    const claimed = await db.query<{ user_id: string }>(
      `INSERT INTO buddy_out_alert_log (user_id, friend_id, local_date)
       SELECT a.user_id, a.friend_id,
              ((NOW() AT TIME ZONE 'UTC')
                + (${userOffsetMinutesSql("a.friend_id")} || ' minutes')::interval)::date
         FROM buddy_out_alerts a
        WHERE a.friend_id = $1
          AND ${SHARES_PRESENCE_SQL("$1::text")}
          AND EXISTS (
            SELECT 1 FROM friendships f
             WHERE f.user_id = a.user_id AND f.friend_id = $1 AND f.status = 'accepted'
          )
          AND NOT EXISTS (
            SELECT 1 FROM user_blocks b
             WHERE (b.blocker_id = a.user_id AND b.blocked_id = $1)
                OR (b.blocker_id = $1 AND b.blocked_id = a.user_id)
          )
       ON CONFLICT (user_id, friend_id, local_date) DO NOTHING
       RETURNING user_id`,
      [walkerId],
    );
    if (claimed.length === 0) return 0;

    const allowed = await allowedRecipients(
      claimed.map((r) => r.user_id),
      walkerId,
      "buddy",
    );
    if (allowed.length === 0) return 0;

    const who = await db.query<{
      first_name: string | null;
      username: string | null;
    }>(`SELECT first_name, username FROM users WHERE user_id = $1`, [walkerId]);
    const name =
      (who[0]?.first_name && who[0].first_name.trim()) ||
      (who[0]?.username && who[0].username.trim()) ||
      "A friend";
    const verb = workoutType === "running" ? "running" : "walking";

    for (const userId of allowed) {
      await sendPush(
        userId,
        {
          title: `${name} is out ${verb}`,
          body: "Want to go together? Tap to join them.",
          type: "buddy_friend_out",
          data: { friend_id: walkerId, workout_type: verb },
        },
        {
          deviceFeature: {
            feature: CLIENT_FEATURES.buddyOutAlertV1,
            supported: true,
          },
        },
      );
    }
    return allowed.length;
  } catch (err) {
    void logError("buddy", "failed to send buddy out alerts", {
      userId: walkerId,
      context: { error: String(err) },
    });
    return 0;
  }
}
