import { PostgresService } from "./DbService.js";
import { CLIENT_FEATURES } from "./clientFeatures.js";
import { sendSilentPushToDevices } from "./pushNotificationService.js";
import { WIDGET_KINDS } from "./widgetKinds.js";

const db = PostgresService.getInstance();

/**
 * Widget refresh pushes: make a home-screen widget move when something
 * happens on SOMEBODY ELSE's phone.
 *
 * A widget only redraws when the app writes the App Group and reloads it, and
 * the app only runs when its owner opens it — so a friend passing you in a
 * competition, in today's head-to-head, or on today's friends leaderboard
 * reached the widget hours late. The fix is a SILENT push (`content-available`,
 * background type, priority 5) that wakes the app for a few seconds to refetch
 * the one snapshot that changed and reload that one widget kind.
 *
 * A visible push that fires for the same event (the lead-change banners) does
 * NOT make this redundant: an alert push never wakes the app, so the widget
 * would still sit on the old standings under the banner that contradicts it.
 * The two are sent independently.
 *
 * Three bounds keep the volume honest:
 *  - capability: only devices declaring `widget_refresh_push_v1` (a shipped
 *    build lacks the background mode, so the push would never be delivered);
 *  - installed widgets: only devices that REPORTED the affected widget kind
 *    (`device_tokens.widget_kinds`; NULL ⇒ never pushed);
 *  - coalescing: at most one per USER per WIDGET_REFRESH_WINDOW_MINUTES,
 *    across every reason, claimed atomically in `widget_refresh_pushes`.
 *    Apple's own background-push allowance is ~2-3 an hour and it silently
 *    drops the rest, so sending more buys nothing. Because a coalesced event
 *    is DROPPED, the app refreshes every live snapshot the device has a
 *    widget for on each wake (reason first) — the reason orders the work, it
 *    doesn't limit it.
 *
 * Kill switch: WIDGET_REFRESH_PUSH_DISABLED=1|true|on. Never throws: every
 * caller is on a workout-sync path and a widget must never fail a sync.
 */

export type WidgetRefreshReason = "competition" | "h2h" | "leaderboard";

/** Which widget kinds a reason redraws — a device is pushed only if it has one. */
export const WIDGET_KINDS_FOR_REASON: Record<WidgetRefreshReason, string[]> = {
  competition: [WIDGET_KINDS.competition],
  // The head-to-head rival is a friend, and the friends leaderboard is the
  // widget that prints their miles against yours.
  h2h: [WIDGET_KINDS.dailyLeaderboard],
  leaderboard: [WIDGET_KINDS.dailyLeaderboard],
};

export const WIDGET_REFRESH_WINDOW_MINUTES = 15;

export const WIDGET_REFRESH_PUSH_TYPE = "widget_refresh";

export function widgetRefreshPushDisabled(): boolean {
  const raw = (process.env.WIDGET_REFRESH_PUSH_DISABLED ?? "")
    .trim()
    .toLowerCase();
  return raw === "1" || raw === "true" || raw === "on";
}

export interface WidgetRefreshResult {
  /** Users with at least one eligible device (feature + widget installed). */
  eligible: number;
  /** Users whose coalescing claim succeeded — i.e. who were actually pushed. */
  claimed: string[];
  /** Device pushes APNs accepted. */
  sent: number;
}

/**
 * Wake the eligible devices of `userIds` to refresh the widget(s) `reason`
 * affects. `excludeUserId` is the actor — their app is the one syncing, so it
 * is already awake and writes its own widgets.
 */
export async function requestWidgetRefresh(
  userIds: Iterable<string>,
  reason: WidgetRefreshReason,
  excludeUserId?: string,
): Promise<WidgetRefreshResult> {
  const empty: WidgetRefreshResult = { eligible: 0, claimed: [], sent: 0 };
  if (widgetRefreshPushDisabled()) return empty;
  const ids = [...new Set(userIds)].filter(
    (id) => id && id !== excludeUserId,
  );
  if (ids.length === 0) return empty;

  try {
    const devices = await db.query<{
      user_id: string;
      device_token: string;
      environment: string | null;
    }>(
      `SELECT user_id, device_token, environment
			FROM device_tokens
			WHERE user_id = ANY($1::text[])
				AND $2::text = ANY(client_features)
				AND widget_kinds && $3::text[]`,
      [ids, CLIENT_FEATURES.widgetRefreshPushV1, WIDGET_KINDS_FOR_REASON[reason]],
    );
    if (devices.length === 0) return empty;
    const eligibleUsers = [...new Set(devices.map((d) => d.user_id))];

    // One statement claims the window for every eligible user: a fresh row
    // inserts, an existing one only updates when its last push is older than
    // the window, and RETURNING names exactly who may be pushed. Two syncs
    // racing on the same recipient can't both win the conflict update.
    const claimed = await db.query<{ user_id: string }>(
      `INSERT INTO widget_refresh_pushes (user_id, last_sent_at, last_reason)
			SELECT u, NOW(), $2::text FROM unnest($1::text[]) AS u
			ON CONFLICT (user_id) DO UPDATE
				SET last_sent_at = NOW(), last_reason = EXCLUDED.last_reason
				WHERE widget_refresh_pushes.last_sent_at
					<= NOW() - make_interval(mins => $3::int)
			RETURNING user_id`,
      [eligibleUsers, reason, WIDGET_REFRESH_WINDOW_MINUTES],
    );
    const claimedIds = new Set(claimed.map((r) => r.user_id));
    if (claimedIds.size === 0) {
      return { eligible: eligibleUsers.length, claimed: [], sent: 0 };
    }

    const sent = await sendSilentPushToDevices(
      devices.filter((d) => claimedIds.has(d.user_id)),
      WIDGET_REFRESH_PUSH_TYPE,
      // String-valued, like every push `data`.
      { type: WIDGET_REFRESH_PUSH_TYPE, reason },
    );
    return {
      eligible: eligibleUsers.length,
      claimed: [...claimedIds],
      sent,
    };
  } catch (err: any) {
    console.error(
      `[WidgetRefresh] ${reason} refresh failed:`,
      err?.message ?? err,
    );
    return empty;
  }
}

/**
 * A workout sync moved `actorId`'s miles for today, which moves every friend's
 * Daily Leaderboard widget. Only friends who have that widget on a device that
 * can take the push are candidates, and each is still coalesced.
 */
export async function refreshFriendsLeaderboardWidgets(
  actorId: string,
): Promise<WidgetRefreshResult> {
  if (widgetRefreshPushDisabled()) {
    return { eligible: 0, claimed: [], sent: 0 };
  }
  try {
    const rows = await db.query<{ friend_id: string }>(
      `SELECT friend_id FROM friendships
			WHERE user_id = $1 AND status = 'accepted'`,
      [actorId],
    );
    return await requestWidgetRefresh(
      rows.map((r) => r.friend_id),
      "leaderboard",
      actorId,
    );
  } catch (err: any) {
    console.error(
      "[WidgetRefresh] friends leaderboard lookup failed:",
      err?.message ?? err,
    );
    return { eligible: 0, claimed: [], sent: 0 };
  }
}
