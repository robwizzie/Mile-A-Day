import { Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import { PostgresService } from "../services/DbService.js";
import { getFriendship } from "../services/friendshipService.js";
import { getUser } from "../services/userService.js";
import { sendPush } from "../services/pushNotificationService.js";
import { shouldSendNotification } from "../services/notificationSettingsService.js";
import {
  lockUnearnedPhotos,
  visiblePostAuthors,
  VisiblePostAuthors,
  visiblePostPreviews,
} from "../services/postService.js";
import { getDailyGoalStatus } from "../services/workoutService.js";
import { signMediaUrl } from "../services/mediaSigningService.js";

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
  removeHypeForContext,
} from "../services/hypeService.js";

/**
 * Absolute base for media URLs put INTO a push payload.
 *
 * The notification service extension fetches these from its own process, so a
 * relative path — which is all `signMediaUrl` returns, and all any in-app
 * consumer needs — is unusable there. Same default as the website's proxy so
 * the two can't disagree about where this API lives.
 */
const PUSH_MEDIA_BASE_URL = (
  process.env.PUBLIC_API_URL ?? "https://mad.mindgoblin.tech"
).replace(/\/+$/, "");

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

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * A collab post reaches BOTH authors' circles, so "can I hype this?" can't be
 * answered by friendship with the post's primary author alone — the whole
 * point of a collab is that the coauthor's friends see it too. Anyone who can
 * SEE the post can hype it; that's the same audience that can already comment
 * on it (`visiblePostAuthors`), and it's strictly narrower than the feed.
 *
 * The hype itself is always recorded against the PRIMARY author, whichever of
 * the two the client named: `hype_count` / `is_hyped` on a post card count
 * rows keyed to `posts.user_id`, so a hype filed against the coauthor would be
 * invisible on the card AND skip the per-run dedupe (letting the same post be
 * hyped twice). The coauthor gets the push instead — see sendHype.
 *
 * Pure visibility + ownership: "is this MY post?" is a send-side rule only
 * (viewing your own post's hypers is fine), so it lives in sendHype.
 */
async function resolvePostHypeTarget(
  viewerId: string,
  postId: string,
  requestedTargetId: string,
): Promise<
  | { ok: true; targetId: string; authors: VisiblePostAuthors }
  | { ok: false; error: string }
> {
  const authors = UUID_RE.test(postId)
    ? await visiblePostAuthors(viewerId, postId)
    : null;
  // Deliberately the same message for "no such post" and "not visible to you":
  // a distinct 404 would confirm the post exists to someone who can't see it.
  if (!authors) {
    return { ok: false, error: "context_id does not reference a visible post" };
  }
  if (
    requestedTargetId !== authors.author_id &&
    requestedTargetId !== authors.coauthor_user_id
  ) {
    return {
      ok: false,
      error: "context_id does not reference the target's post",
    };
  }
  return { ok: true, targetId: authors.author_id, authors };
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

/**
 * The post's photo, absolute and signed, for a hype push's banner thumbnail.
 *
 * Instagram puts the liked photo on the notification, and the in-app inbox has
 * done that since it started sending `context_id`; the lock-screen banner is
 * the surface that never could. Attaching it needs two things the payload
 * didn't carry: `mutable-content` (already sent) and a URL the notification
 * service extension can fetch on its own. The extension runs in a separate
 * process with no session, no API base and no auth, so a bare path or a
 * protected URL is useless to it — hence absolute, and signed with the same
 * short-lived HMAC the app's own image loads use.
 *
 * Visibility goes through `visiblePostPreviews` and `lockUnearnedPhotos` — the
 * same pair the inbox uses — rather than a direct read. For a hype the
 * recipient is the post's own author, so both are satisfied trivially, and
 * that is exactly why it would be tempting to skip them; the day this is
 * reused for a push about somebody ELSE's post, skipping them is a photo on a
 * lock screen that the feed would have withheld.
 *
 * Returns null for anything that isn't a resolvable post photo. A banner
 * without a picture is the old banner, which is fine.
 *
 * Exported for ci-smoke, which drives it directly: the push itself can't be
 * observed from a test (APNs isn't reachable and the inbox row deliberately
 * drops this key), so the resolver is the only place the gate can be pinned.
 */
export async function hypePushImageURL(
  recipientId: string,
  context: { contextType: string; contextId: string },
): Promise<string | null> {
  if (context.contextType !== "post") return null;
  try {
    const [preview] = await visiblePostPreviews(recipientId, [
      context.contextId,
    ]);
    if (!preview) return null;
    let gate: { completed: boolean; localDate: string };
    try {
      const goal = await getDailyGoalStatus(recipientId);
      gate = { completed: goal.completed, localDate: goal.localDate };
    } catch {
      // Fail OPEN, like the inbox's own gate: a stats hiccup should not blank
      // the thumbnail. The recipient is the author here either way.
      gate = { completed: true, localDate: "" };
    }
    lockUnearnedPhotos([preview], recipientId, gate);
    if (!preview.media_url || preview.photo_locked) return null;
    const signed = signMediaUrl(preview.media_url);
    return `${PUSH_MEDIA_BASE_URL}${signed}`;
  } catch (e: any) {
    console.error("[Hype] push image resolve failed:", e?.message ?? e);
    return null;
  }
}

export async function sendHype(req: AuthenticatedRequest, res: Response) {
  const senderId = req.userId!;
  let targetUserId = req.body?.target_user_id;
  const rawContextType = req.body?.context_type;
  const rawContextId = req.body?.context_id;
  const rawContextLabel = req.body?.context_label;

  try {
    if (!targetUserId || typeof targetUserId !== "string") {
      return res.status(400).json({ error: "target_user_id is required" });
    }
    // Self-hypes are allowed (you can like your own post): the row counts in
    // the tally like anyone else's, but nobody is notified and it earns no
    // social badge — see the recipient loop and the badge call below.

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

    // Post hypes are authorized by whether the sender can SEE the post, not by
    // friendship with its primary author — a collab post legitimately reaches
    // the coauthor's friends too, and the old friend-only gate 403'd them after
    // the client had already played the hype animation. Resolving here also
    // pins the hype to the primary author and rejects a (target, post) pair
    // that don't belong together, which used to bypass dedupe and pollute
    // counts. Non-post contexts keep the friend/co-participant gate.
    let postCoauthorId: string | null = null;
    if (context?.contextType === "post") {
      const resolved = await resolvePostHypeTarget(
        senderId,
        context.contextId,
        targetUserId,
      );
      if (!resolved.ok) {
        return res.status(400).json({ error: resolved.error });
      }
      // Either author of a collab may hype it too — filed against the
      // primary author like every other hype, so the tally stays one pool.
      targetUserId = resolved.targetId;
      postCoauthorId = resolved.authors.coauthor_user_id;
    } else if (senderId !== targetUserId) {
      const allowed = await isFriendOrCoParticipant(senderId, targetUserId);
      if (!allowed) {
        return res.status(403).json({
          error:
            "You can only hype friends or people in your active competitions",
        });
      }
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
					-- Skip workouts that never earned a card: a 3-second phantom is
					-- the target's most recent workout surprisingly often, and it
					-- would aim the hype at a day with no mile in it.
					AND feed_role IN ('daily_mile', 'extra')
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

    // Re-evaluate hype badges (first hype, X hypes) in the background —
    // hyping yourself doesn't count toward them.
    if (senderId !== targetUserId) {
      evaluateSocialBadgesForUser(senderId).catch(() => {});
    }

    const [countAfter, unlimited] = await Promise.all([
      getDailyHypeCount(senderId),
      hasUnlimitedHypes(senderId),
    ]);

    // Both authors of a collab hear about it. Only the primary author's row is
    // in hype_log (see resolvePostHypeTarget) — the coauthor's copy is the
    // push alone, which is what keeps the card's tally honest while still
    // telling the person whose post it also is.
    // Nobody gets told about their own hype.
    const recipients = [targetUserId, postCoauthorId].filter(
      (id): id is string => !!id && id !== senderId,
    );
    const sender = await getUser({ userId: senderId });
    const senderName = sender?.username ?? "Someone";
    for (const recipientId of recipients) {
      const shouldSend = await shouldSendNotification(
        recipientId,
        senderId,
        "hype",
      );
      if (!shouldSend) continue;
      const body =
        recipientId === postCoauthorId
          ? `${senderName} hyped your collab post 🔥`
          : buildHypeBackBody(senderName, context);
      const pushData: Record<string, string> = { user_id: senderId };
      if (context) {
        pushData.context_type = context.contextType;
        pushData.context_label = context.contextLabel;
        // For post hypes this is the post uuid — the inbox uses it to show
        // the post's thumbnail and open the post on tap. String-valued like
        // every data field (shipped clients decode data as [String: String]).
        pushData.context_id = context.contextId;
        // ...and the picture itself, for the notification service extension
        // to attach so the BANNER carries the thumbnail the in-app inbox has
        // always had. Absolute and signed, because the extension is its own
        // process: it knows nothing about the app's API base or auth, and
        // must be able to fetch this with a bare GET.
        const image = await hypePushImageURL(recipientId, context);
        if (image) pushData.image_url = image;
      }
      await sendPush(recipientId, {
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

export async function removeHype(req: AuthenticatedRequest, res: Response) {
  const senderId = req.userId!;
  let targetUserId = req.body?.target_user_id;
  const rawContextType = req.body?.context_type;
  const rawContextId = req.body?.context_id;

  try {
    if (!targetUserId || typeof targetUserId !== "string") {
      return res.status(400).json({ error: "target_user_id is required" });
    }
    if (
      !["mile", "badge", "pr", "challenge", "post"].includes(rawContextType)
    ) {
      return res.status(400).json({
        error:
          "context_type must be one of 'mile' | 'badge' | 'pr' | 'challenge' | 'post'",
      });
    }
    if (!rawContextId) {
      return res.status(400).json({ error: "context_id is required" });
    }

    const contextType = rawContextType as HypeContext["contextType"];
    let contextId = String(rawContextId);

    if (contextType === "post") {
      const resolved = await resolvePostHypeTarget(
        senderId,
        contextId,
        targetUserId,
      );
      if (!resolved.ok) {
        return res.status(400).json({ error: resolved.error });
      }
      targetUserId = resolved.targetId;
    } else if (senderId !== targetUserId) {
      const allowed = await isFriendOrCoParticipant(senderId, targetUserId);
      if (!allowed) {
        return res.status(403).json({
          error:
            "You can only unhype friends or people in your active competitions",
        });
      }
    }

    if (contextType === "mile") {
      try {
        const canonical = await canonicalizeMileContext(targetUserId, {
          contextType: "mile",
          contextId,
          contextLabel: "",
        });
        contextId = canonical.contextId;
      } catch {
        return res.status(400).json({ error: "Invalid mile context" });
      }
    }

    const removed = await removeHypeForContext(
      senderId,
      targetUserId,
      contextType,
      contextId,
    );
    const [countAfter, unlimited] = await Promise.all([
      getDailyHypeCount(senderId),
      hasUnlimitedHypes(senderId),
    ]);

    res.status(200).json({
      message: removed > 0 ? "Hype removed" : "No hype to remove",
      removed: removed > 0,
      hypes_remaining: unlimited
        ? HYPE_DAILY_LIMIT
        : Math.max(0, HYPE_DAILY_LIMIT - countAfter),
      unlimited,
    });
  } catch (error: any) {
    console.error("Error removing hype:", error.message);
    res.status(500).json({ error: "Error removing hype" });
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
 * `target_user_id` (the content's author). Viewer must be someone who can see
 * the content — for a post that's either author's circle, for a mile it's the
 * author's friends / active-competition co-participants — i.e. the same
 * audience that can see the tally on the feed.
 */
export async function getContextHypersController(
  req: AuthenticatedRequest,
  res: Response,
) {
  const viewerId = req.userId!;
  const contextType = String(req.query.context_type ?? "");
  const rawContextId = String(req.query.context_id ?? "");
  let targetUserId = String(req.query.target_user_id ?? "");

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

    // Same audience rule as sending: a post's hypers are visible to anyone who
    // can see the post (a collab reaches the coauthor's friends too), and the
    // list itself is always keyed to the PRIMARY author's rows.
    if (contextType === "post") {
      const resolved = await resolvePostHypeTarget(
        viewerId,
        rawContextId,
        targetUserId,
      );
      if (!resolved.ok) {
        return res
          .status(403)
          .json({ error: "You can only view hypes on content you can see" });
      }
      targetUserId = resolved.targetId;
    } else if (viewerId !== targetUserId) {
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
