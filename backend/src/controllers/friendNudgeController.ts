import { Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import { getUser } from "../services/userService.js";
import { getFriendship } from "../services/friendshipService.js";
import {
  sendPush,
  canFriendNudge,
  hasNudgedFriendToday,
  logFriendNudge,
} from "../services/pushNotificationService.js";
import { hasUnlimitedActions } from "../services/privilegedUsers.js";
import { shouldSendNotification } from "../services/notificationSettingsService.js";
import {
  getTodayMiles,
  DAILY_GOAL_TOLERANCE,
} from "../services/workoutService.js";
import {
  effectiveStreakSql,
  fetchTodayCoverage,
} from "../services/streakFeatureCore.js";
import { evaluateSocialBadgesForUser } from "../services/badgeService.js";
import { PostgresService } from "../services/DbService.js";
import { bothUseFun } from "../services/flameyService.js";

const db = PostgresService.getInstance();

/// Returns a map of user_id -> current_streak for the given users: the stored
/// snapshot with the calendar decay applied in SQL, ONE query for the batch.
/// (This used to recompute every friend's streak from their workout history —
/// and write it — on every nudge-status read.)
async function fetchStreaks(
  userIds: string[],
): Promise<Record<string, number>> {
  if (userIds.length === 0) return {};
  const uniqueIds = [...new Set(userIds)];
  try {
    const rows = await db.query<{ user_id: string; current_streak: number }>(
      `SELECT u.user_id, (${effectiveStreakSql("u")})::int AS current_streak
         FROM users u
        WHERE u.user_id = ANY($1::text[])`,
      [uniqueIds],
    );
    const map: Record<string, number> = {};
    for (const r of rows) map[r.user_id] = Number(r.current_streak) || 0;
    return map;
  } catch (err: any) {
    console.error(
      "fetchStreaks failed:",
      err.message,
    );
    return {};
  }
}

const FLAMEY_POKE_BODIES = [
  "He's itching for a mile — want to go?",
  "He's bouncing on his toes. One mile?",
  "He wants to stretch his legs. Walk with him?",
];

/** Varied copy for a Flamey poke. Playful, never a health claim. */
export function flameyPokeCopy(senderName: string): { title: string; body: string } {
  const body =
    FLAMEY_POKE_BODIES[Math.floor(Math.random() * FLAMEY_POKE_BODIES.length)];
  return { title: `🔥 ${senderName} poked your Flamey`, body };
}

export async function nudgeFriend(req: AuthenticatedRequest, res: Response) {
  const friendId = req.params.friendId;
  const senderId = req.userId!;

  try {
    if (senderId === friendId) {
      return res.status(400).json({ error: "You can't nudge yourself" });
    }

    // Verify they are friends
    const friendship = await getFriendship(senderId, friendId);
    if (
      !friendship ||
      "error" in friendship ||
      friendship.status !== "accepted"
    ) {
      return res.status(400).json({ error: "You can only nudge friends" });
    }

    // A Flamey poke is the same nudge — same friendship check above, same
    // done-today and once-a-day rules below, same push type — dressed in
    // Flamey's copy. Flamey only exists on the Fun dashboard, so both sides
    // must draw it; NULL (a build predating the field) counts as not Fun.
    // Without `source` nothing below changes.
    const flameyPoke = req.body?.source === "flamey";
    if (flameyPoke && !(await bothUseFun(senderId, friendId))) {
      return res.status(403).json({ error: "flamey_unavailable" });
    }

    // Check if friend has already completed their mile today — same 0.95
    // tolerance as streak counting, so a day the streak credits can't be
    // nudged as "incomplete".
    const friendTodayMiles = await getTodayMiles(friendId);
    if (friendTodayMiles >= DAILY_GOAL_TOLERANCE) {
      return res
        .status(400)
        .json({ error: "This friend has already completed their mile today" });
    }

    // Rate limit: 1 nudge per friend per 24h
    const allowed = await canFriendNudge(senderId, friendId);
    if (!allowed) {
      return res
        .status(429)
        .json({ error: "You can only nudge this friend once per day" });
    }

    // Check notification preferences
    const shouldSend = await shouldSendNotification(
      friendId,
      senderId,
      "nudge",
    );

    if (shouldSend) {
      const sender = await getUser({ userId: senderId });
      const senderName = sender?.username || "Someone";

      await sendPush(
        friendId,
        flameyPoke
          ? {
              ...flameyPokeCopy(senderName),
              // Same type every shipped build routes; `source` is additive
              // and string-valued (inbox `data` decodes as [String: String]).
              type: "friend_nudge",
              data: { user_id: senderId, source: "flamey" },
            }
          : {
              title: "Time to lace up!",
              body: `${senderName} is nudging you to get your mile in today`,
              type: "friend_nudge",
              data: { user_id: senderId },
            },
      );
    }

    // Log after the send so a failed push doesn't consume the daily limit
    await logFriendNudge(senderId, friendId);

    // Re-evaluate nudge badges (fire-and-forget — never block the response).
    evaluateSocialBadgesForUser(senderId).catch(() => {});

    res.status(200).json({ message: "Nudge sent" });
  } catch (error: any) {
    console.error("Error sending friend nudge:", error.message);
    res.status(500).json({ error: "Error sending nudge" });
  }
}

// Check if a friend can be nudged (for UI state)
export async function checkNudgeStatus(
  req: AuthenticatedRequest,
  res: Response,
) {
  const friendId = req.params.friendId;
  const senderId = req.userId!;

  try {
    const [nudgedToday, unlimited, friendTodayMiles, streaks, coverage] =
      await Promise.all([
        hasNudgedFriendToday(senderId, friendId),
        hasUnlimitedActions(senderId),
        getTodayMiles(friendId),
        fetchStreaks([friendId]),
        fetchTodayCoverage([friendId]),
      ]);
    const canNudge = unlimited || !nudgedToday;

    const hasCompletedMile = friendTodayMiles >= DAILY_GOAL_TOLERANCE;
    const covered = coverage[friendId] ?? null;

    res.status(200).json({
      can_nudge: canNudge && !hasCompletedMile,
      has_completed_mile: hasCompletedMile,
      // A token is already holding their day. Additive and null for almost
      // everyone; shipped builds ignore it. Without it the row paints a
      // banked day as "0.00 / 1 mi · 0%" — the app reporting that the rescue
      // the viewer may have just paid for did nothing.
      today_covered: covered,
      // Legacy field: derived from can_nudge, so unlimited nudgers read
      // false here and old builds keep their re-nudge ability.
      already_nudged_today: !canNudge,
      // Log truth + role, so new builds can show "already nudged, nudge
      // again?" for unlimited senders.
      has_nudged_today: nudgedToday,
      unlimited_nudges: unlimited,
      today_miles: Math.round(friendTodayMiles * 100) / 100,
      current_streak: streaks[friendId] ?? 0,
    });
  } catch (error: any) {
    console.error("Error checking nudge status:", error.message);
    res.status(500).json({ error: "Error checking nudge status" });
  }
}

// Batch check nudge status for all friends
export async function checkNudgeStatusBatch(
  req: AuthenticatedRequest,
  res: Response,
) {
  const senderId = req.userId!;
  const friendIds = req.body.friend_ids;

  if (!Array.isArray(friendIds) || friendIds.length === 0) {
    return res
      .status(400)
      .json({ error: "friend_ids must be a non-empty array" });
  }

  try {
    const statuses: Record<
      string,
      {
        can_nudge: boolean;
        has_completed_mile: boolean;
        already_nudged_today: boolean;
        has_nudged_today: boolean;
        unlimited_nudges: boolean;
        today_miles: number;
        current_streak: number;
        today_covered: {
          local_date: string;
          kind: string;
          source_username: string | null;
        } | null;
      }
    > = {};

    // One DB roundtrip for all streaks rather than N per-friend queries;
    // the role bypass is per-sender, so look it up once. Today's coverage is
    // batched the same way — it resolves each friend's own local day, so it
    // cannot be folded into the per-friend loop without N more queries.
    const [streaks, unlimited, coverage] = await Promise.all([
      fetchStreaks(friendIds),
      hasUnlimitedActions(senderId),
      fetchTodayCoverage(friendIds),
    ]);

    await Promise.all(
      friendIds.map(async (friendId: string) => {
        const [nudgedToday, friendTodayMiles] = await Promise.all([
          hasNudgedFriendToday(senderId, friendId),
          getTodayMiles(friendId),
        ]);
        const canNudge = unlimited || !nudgedToday;

        const hasCompletedMile = friendTodayMiles >= DAILY_GOAL_TOLERANCE;
        statuses[friendId] = {
          can_nudge: canNudge && !hasCompletedMile,
          has_completed_mile: hasCompletedMile,
          // Legacy: derived, so unlimited nudgers keep re-nudge on old builds.
          already_nudged_today: !canNudge,
          has_nudged_today: nudgedToday,
          unlimited_nudges: unlimited,
          today_miles: Math.round(friendTodayMiles * 100) / 100,
          current_streak: streaks[friendId] ?? 0,
          today_covered: coverage[friendId] ?? null,
        };
      }),
    );

    res.status(200).json({ statuses });
  } catch (error: any) {
    console.error("Error checking nudge statuses:", error.message);
    res.status(500).json({ error: "Error checking nudge statuses" });
  }
}
