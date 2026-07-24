import { PostgresService } from "./DbService.js";
import { sendPush } from "./pushNotificationService.js";
import { localNowSql } from "./dailyResetTime.js";
import { friendRequestRemindersEnabled } from "./friendRequestFeatures.js";

const db = PostgresService.getInstance();

/** Requests younger than this are still "fresh" — the original push covers them. */
const MIN_AGE_HOURS = 24;

/** One reminder per user per this window, no matter how many requests are waiting. */
const COOLDOWN_DAYS = 7;

/**
 * Local-time delivery window. Matches the h2h winner push: a reminder that
 * lands at 3 AM is worse than no reminder, and quiet-hours queuing would only
 * resurface it later as a degraded digest.
 */
const SEND_HOUR_START = 9;
const SEND_HOUR_END = 21;

type ReminderCandidate = {
  user_id: string;
  pending_count: string;
  requester_name: string | null;
};

/**
 * Remind users who have friend requests sitting unanswered.
 *
 * This is the only part of the friend-request work that ADDS notification
 * volume, so it is bounded on every axis: requests must be >24h old (the
 * original push already had its chance), one coalesced push per user per 7
 * days regardless of how many people are waiting, delivered only during the
 * user's own daytime, gated on a per-user preference, and — unlike
 * friend_request itself — subject to quiet hours and the daily cap because
 * friend_request_reminder is deliberately absent from HIGH_PRIORITY_TYPES.
 *
 * Cohort it exists for: users who missed the push AND haven't opened the app
 * since. Every in-app surface (dashboard row, icon badge, tab badge) is
 * invisible to them by definition.
 *
 * Runs hourly; the local-hour predicate means each user matches at most one
 * tick per day.
 */
export async function sendPendingFriendRequestReminders(): Promise<void> {
  if (!friendRequestRemindersEnabled()) return;

  // Eligibility is decided per USER, never per row. Grouping over ALL of the
  // user's pending rows (not just the >24h ones) is load-bearing: an unstamped
  // row that arrived yesterday must still be able to veto a reminder via the
  // cooldown below. Filtering stale rows in the WHERE instead would hide the
  // recent stamp from MAX() and let every new request earn its own reminder.
  const candidates = await db.query<ReminderCandidate>(
    `SELECT f.friend_id AS user_id,
			COUNT(*)::text AS pending_count,
			MIN(u.username) AS requester_name
		FROM friendships f
		JOIN users u ON u.user_id = f.user_id
		LEFT JOIN notification_settings ns ON ns.user_id = f.friend_id
		WHERE f.status = 'pending'
			AND COALESCE(ns.friend_request_reminder_enabled, TRUE) = TRUE
			AND EXTRACT(HOUR FROM ${localNowSql("f.friend_id")})
				BETWEEN ${SEND_HOUR_START} AND ${SEND_HOUR_END}
			AND EXISTS (
				SELECT 1 FROM device_tokens dt WHERE dt.user_id = f.friend_id
			)
		GROUP BY f.friend_id
		HAVING COUNT(*) FILTER (
				WHERE f.created_at < NOW() - INTERVAL '${MIN_AGE_HOURS} hours'
			) > 0
			AND (MAX(f.reminder_sent_at) IS NULL
				OR MAX(f.reminder_sent_at) < NOW() - INTERVAL '${COOLDOWN_DAYS} days')`,
  );

  for (const candidate of candidates) {
    // Claim-then-send, as in notifyPendingWinners — but the guard is the same
    // per-user one the HAVING used, so a concurrent tick that already stamped
    // this user matches zero rows here and sends nothing.
    //
    // Stamping EVERY pending row (including any that arrived since) is what
    // buys the coalescing: the next request to land is already inside the
    // cooldown and cannot trigger a reminder of its own.
    const claimed = await db.query<{ friend_id: string }>(
      `UPDATE friendships SET reminder_sent_at = NOW()
			WHERE friend_id = $1 AND status = 'pending'
				AND NOT EXISTS (
					SELECT 1 FROM friendships f2
					WHERE f2.friend_id = $1 AND f2.status = 'pending'
						AND f2.reminder_sent_at >= NOW() - INTERVAL '${COOLDOWN_DAYS} days'
				)
			RETURNING friend_id`,
      [candidate.user_id],
    );
    if (claimed.length === 0) continue;

    const count = parseInt(candidate.pending_count ?? "0");
    if (count === 0) continue;

    const name = candidate.requester_name;
    const body =
      count === 1 && name
        ? `${name} is waiting to be your friend`
        : `${count} people are waiting to be your friend`;

    try {
      await sendPush(candidate.user_id, {
        title: "Still waiting on you",
        body,
        type: "friend_request_reminder",
      });
    } catch (err: any) {
      // The claim already landed, so a delivery failure costs this user one
      // cooldown window rather than looping them on every subsequent tick.
      console.error(
        `[FriendRequestReminder] Push failed for ${candidate.user_id}:`,
        err.message,
      );
    }
  }
}
