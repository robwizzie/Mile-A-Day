import { Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import { PostgresService } from "../services/DbService.js";
import { getFriendship } from "../services/friendshipService.js";
import { getUser } from "../services/userService.js";
import { sendPush } from "../services/pushNotificationService.js";
import { shouldSendNotification } from "../services/notificationSettingsService.js";
import { getPostAuthor } from "../services/postService.js";
import { hasUnlimitedHypes } from "../services/privilegedUsers.js";
import { evaluateSocialBadgesForUser } from "../services/badgeService.js";
import {
  logHypeIfUnderLimit,
  getDailyHypeCount,
  getHypeResetsAt,
  hasHypedContext,
  hasHypedRunContext,
  canonicalizeMileContext,
  HYPE_DAILY_LIMIT,
  HypeContext,
  getReceivedHypes,
  getContextHypers,
} from "../services/hypeService.js";

const db = PostgresService.getInstance();

/**
 * True if sender and target are accepted participants in at least one
 * currently-active competition.
 */
async function shareActiveCompetition(
  senderId: string,
  targetId: string,
): Promise<boolean> {
  const rows = await db.query<{ exists: boolean }>(
    `SELECT EXISTS (
			SELECT 1
			FROM competition_users cu_sender
			JOIN competition_users cu_target ON cu_target.competition_id = cu_sender.competition_id
			JOIN competitions c ON c.id = cu_sender.competition_id
			WHERE cu_sender.user_id = $1
				AND cu_target.user_id = $2
				AND cu_sender.invite_status = 'accepted'
				AND cu_target.invite_status = 'accepted'
				AND c.start_date IS NOT NULL
				AND c.start_date <= NOW()
				AND c.winner IS NULL
				AND (c.end_date IS NULL OR c.end_date > NOW())
		) AS exists`,
    [senderId, targetId],
  );
  return rows[0]?.exists === true;
}

async function isFriendOrCoParticipant(
  senderId: string,
  targetId: string,
): Promise<boolean> {
  const friendship = await getFriendship(senderId, targetId);
  const friendsAccepted =
    !!friendship &&
    !("error" in friendship) &&
    friendship.status === "accepted";
  if (friendsAccepted) return true;
  return shareActiveCompetition(senderId, targetId);
}

function buildHypeBackBody(
  senderName: string,
  context: HypeContext | undefined,
): string {
  if (!context) {
    return `@${senderName} just hyped up your recent workout!`;
  }
  switch (context.contextType) {
    case "mile":
      return `${senderName} hyped your daily mile 🔥`;
    case "badge":
      return `${senderName} hyped you earning '${context.contextLabel}' 🔥`;
    case "pr":
      return `${senderName} hyped your new ${context.contextLabel} 🔥`;
    case "challenge":
      return `${senderName} hyped your '${context.contextLabel}' challenge 🔥`;
    case "post":
      return `${senderName} hyped your post 🔥`;
  }
}

export async function sendHype(req: AuthenticatedRequest, res: Response) {
  const senderId = req.userId!;
  const targetUserId = req.body?.target_user_id;
  const rawContextType = req.body?.context_type;
  const rawContextId = req.body?.context_id;
  const rawContextLabel = req.body?.context_label;

  try {
    if (!targetUserId || typeof targetUserId !== "string") {
      return res.status(400).json({ error: "target_user_id is required" });
    }
    if (senderId === targetUserId) {
      return res.status(400).json({ error: "You can't hype yourself" });
    }

    // Parse optional context. All three must be present together, or all absent.
    let context: HypeContext | undefined;
    const anyCtx = rawContextType || rawContextId || rawContextLabel;
    const allCtx = rawContextType && rawContextId && rawContextLabel;
    if (anyCtx && !allCtx) {
      return res.status(400).json({
        error:
          "context_type, context_id, and context_label must be provided together",
      });
    }
    if (allCtx) {
      if (
        !["mile", "badge", "pr", "challenge", "post"].includes(rawContextType)
      ) {
        return res.status(400).json({
          error:
            "context_type must be one of 'mile' | 'badge' | 'pr' | 'challenge' | 'post'",
        });
      }
      context = {
        contextType: rawContextType,
        contextId: String(rawContextId),
        contextLabel: String(rawContextLabel),
      };
    }

    const allowed = await isFriendOrCoParticipant(senderId, targetUserId);
    if (!allowed) {
      return res.status(403).json({
        error:
          "You can only hype friends or people in your active competitions",
      });
    }

    // A context-less hype — older clients' push-notification "🔥 Hype" button
    // sends only target_user_id — has no run identity, so it would skip the
    // per-run dedupe below and let the same daily mile be hyped again from the
    // feed or inbox. Resolve it to the target's most recent daily-mile composite
    // (the same key those surfaces use) so it dedupes and counts as one hype.
    if (!context) {
      const recent = await db.query<{ local_date: string }>(
        `SELECT local_date::text AS local_date
				FROM workouts
				WHERE user_id = $1 AND deleted_at IS NULL AND exclusion_reason IS NULL
					AND device_end_date >= NOW() - INTERVAL '36 hours'
				ORDER BY device_end_date DESC
				LIMIT 1`,
        [targetUserId],
      );
      const localDate = recent[0]?.local_date;
      if (localDate) {
        context = {
          contextType: "mile",
          contextId: `${targetUserId}:${localDate}`,
          contextLabel: "today's mile",
        };
      }
    }

    // No event-occurred validation: the recipient only sees a hype affordance
    // when a real notification exists, so the notification itself is the proof.
    // Abuse is bounded by the friend/co-participant gate, per-context dedupe,
    // and the daily hype limit below.

    // Post hypes must reference a real post authored by the target — without
    // this, mismatched (target, post) pairs bypass dedupe and pollute counts.
    // (Non-uuid ids short-circuit before they'd blow up the ::uuid cast.)
    if (context?.contextType === "post") {
      const isUuid =
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
          context.contextId,
        );
      const author = isUuid ? await getPostAuthor(context.contextId) : null;
      if (author !== targetUserId) {
        return res
          .status(400)
          .json({ error: "context_id does not reference the target's post" });
      }
    }

    // Canonicalize mile hypes so the feed (workout_id-keyed) and the
    // notifications inbox (user:date-keyed) write and dedupe the same context.
    if (context?.contextType === "mile") {
      try {
        context = await canonicalizeMileContext(targetUserId, context);
      } catch {
        return res.status(400).json({ error: "Invalid mile context" });
      }
    }

    // Context-aware dedupe pre-check (legacy no-context hypes skip this).
    // Mile/post contexts dedupe across the whole RUN — hyping a mile from
    // the inbox and then the same run's post from the feed is ONE hype.
    if (context) {
      const alreadyHyped =
        context.contextType === "mile" || context.contextType === "post"
          ? await hasHypedRunContext(
              senderId,
              targetUserId,
              context.contextType,
              context.contextId,
            )
          : await hasHypedContext(
              senderId,
              targetUserId,
              context.contextType,
              context.contextId,
            );
      if (alreadyHyped) {
        return res.status(409).json({ error: "already_hyped" });
      }
    }

    // Atomic: insert iff still under the limit. Closes the concurrent-sender race.
    let inserted;
    try {
      inserted = await logHypeIfUnderLimit(senderId, targetUserId, context);
    } catch (err: any) {
      // Two identical requests can both pass the dedupe pre-check; the loser
      // hits the partial unique index — that's an "already hyped", not a 500.
      if (err?.code === "23505") {
        return res.status(409).json({ error: "already_hyped" });
      }
      throw err;
    }
    if (!inserted) {
      // Hypes are unlimited; the only thing that can block an insert now is the
      // silent per-day abuse ceiling (HYPE_DAILY_ABUSE_CEILING). Keep the copy
      // generic — don't cite the retired 3/day cap or leak the ceiling value.
      return res.status(429).json({
        error:
          "You're hyping a lot right now — take a breather and try again in a bit.",
        hypes_remaining: 0,
        resets_at: null,
      });
    }

    // Re-evaluate hype badges (first hype, X hypes) in the background.
    evaluateSocialBadgesForUser(senderId).catch(() => {});

    const [countAfter, unlimited] = await Promise.all([
      getDailyHypeCount(senderId),
      hasUnlimitedHypes(senderId),
    ]);

    const shouldSend = await shouldSendNotification(
      targetUserId,
      senderId,
      "hype",
    );
    if (shouldSend) {
      const sender = await getUser({ userId: senderId });
      const senderName = sender?.username ?? "Someone";
      const body = buildHypeBackBody(senderName, context);
      const pushData: Record<string, string> = { user_id: senderId };
      if (context) {
        pushData.context_type = context.contextType;
        pushData.context_label = context.contextLabel;
      }
      await sendPush(targetUserId, {
        title: "🔥 You got hyped!",
        body,
        type: "hype_received",
        data: pushData,
      });
    }

    // Unlimited (admin/founder) senders never report a depleted allowance:
    // old builds read hypes_remaining directly for their "N left" pill and
    // disable hyping at 0, so pin it at the cap; new builds show ∞ via the
    // explicit flag.
    res.status(200).json({
      message: "Hype sent",
      hypes_remaining: unlimited
        ? HYPE_DAILY_LIMIT
        : Math.max(0, HYPE_DAILY_LIMIT - countAfter),
      unlimited,
    });
  } catch (error: any) {
    console.error("Error sending hype:", error.message);
    res.status(500).json({ error: "Error sending hype" });
  }
}

export async function getReceivedHypesController(
  req: AuthenticatedRequest,
  res: Response,
) {
  const userId = req.userId!;
  try {
    const hypes = await getReceivedHypes(userId);
    res.status(200).json(hypes);
  } catch (error: any) {
    console.error("Error getting received hypes:", error.message);
    res.status(500).json({ error: "Error getting received hypes" });
  }
}

/**
 * Who hyped a specific post or daily mile — the Instagram-style "who liked
 * this" list behind a hype tally. Query params: `context_type` ('post'|'mile'),
 * `context_id` (post id, or the mile's workout id / user:date composite), and
 * `target_user_id` (the content's author). Viewer must be the author, a
 * friend, or an active-competition co-participant — the same audience that can
 * see the tally on the feed.
 */
export async function getContextHypersController(
  req: AuthenticatedRequest,
  res: Response,
) {
  const viewerId = req.userId!;
  const contextType = String(req.query.context_type ?? "");
  const rawContextId = String(req.query.context_id ?? "");
  const targetUserId = String(req.query.target_user_id ?? "");

  try {
    if (!["post", "mile"].includes(contextType)) {
      return res
        .status(400)
        .json({ error: "context_type must be 'post' or 'mile'" });
    }
    if (!rawContextId || !targetUserId) {
      return res
        .status(400)
        .json({ error: "context_id and target_user_id are required" });
    }

    if (viewerId !== targetUserId) {
      const allowed = await isFriendOrCoParticipant(viewerId, targetUserId);
      if (!allowed) {
        return res
          .status(403)
          .json({ error: "You can only view hypes on content you can see" });
      }
    }

    // Mile hypes are stored under the canonical `<userId>:<localDate>`
    // composite — resolve a raw workout id to it, same as the send path.
    let contextId = rawContextId;
    if (contextType === "mile") {
      try {
        const canonical = await canonicalizeMileContext(targetUserId, {
          contextType: "mile",
          contextId: rawContextId,
          contextLabel: "",
        });
        contextId = canonical.contextId;
      } catch {
        return res.status(400).json({ error: "Invalid mile context" });
      }
    }

    const hypers = await getContextHypers(targetUserId, contextType, contextId);
    res.status(200).json({ hypers, count: hypers.length });
  } catch (error: any) {
    console.error("Error getting context hypers:", error.message);
    res.status(500).json({ error: "Error getting context hypers" });
  }
}

export async function getHypeStatus(req: AuthenticatedRequest, res: Response) {
  const senderId = req.userId!;
  try {
    const [count, resetsAt, unlimited] = await Promise.all([
      getDailyHypeCount(senderId),
      getHypeResetsAt(senderId),
      hasUnlimitedHypes(senderId),
    ]);
    // See sendHype: unlimited senders pin hypes_remaining at the cap so old
    // builds never render a depleted/disabled hype UI for them.
    res.status(200).json({
      hypes_remaining: unlimited
        ? HYPE_DAILY_LIMIT
        : Math.max(0, HYPE_DAILY_LIMIT - count),
      resets_at: resetsAt,
      unlimited,
    });
  } catch (error: any) {
    console.error("Error getting hype status:", error.message);
    res.status(500).json({ error: "Error getting hype status" });
  }
}
