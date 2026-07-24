import { Request, Response } from "express";
import {
  sendFriendRequest,
  getFriends as getUserFriends,
  getFriendRequests as getUserFriendRequests,
  getSentRequests as getUserSentRequests,
  updateFriendship,
  getFriendsActivityToday as getActivityToday,
  getFriendSuggestions,
  getMutualFriendCount,
  getFriendsWorkoutFeed,
  countPendingFriendRequests,
  hasRequestedFriendToday,
  countRequestsSentToday,
  logFriendRequest,
  FRIEND_REQUEST_DAILY_CEILING,
} from "../services/friendshipService.js";
import { friendRequestClientV2Enabled } from "../services/friendRequestFeatures.js";
import { getBlockedIds } from "../services/moderationService.js";
import { hasUnlimitedActions } from "../services/privilegedUsers.js";
import { AuthenticatedRequest } from "../middleware/auth.js";
import hasRequiredKeys from "../utils/hasRequiredKeys.js";
import { getUser, getUsers } from "../services/userService.js";
import {
  sendPush,
  fanOutFriendChallengePush,
} from "../services/pushNotificationService.js";
import { evaluateAddFriendCompletion } from "../services/dailyChallengeService.js";

const BAD_REQUEST_ERRORS = [
  "No friendship found",
  "Friendship already has status",
  `User can't update a request they sent`,
  "Invalid status",
];

export async function getFriends(req: Request, res: Response) {
  if (!hasRequiredKeys(["userId"], req, res)) return;

  const { userId } = req.params;

  const user = await getUser({ userId });
  if (!user) {
    return res.status(400).send({ error: `No user found with ID ${userId}` });
  }

  const friends = await getUserFriends(userId);

  res.send(friends);
}

export async function getSentRequests(req: Request, res: Response) {
  if (!hasRequiredKeys(["userId"], req, res)) return;

  const { userId } = req.params;

  const user = await getUser({ userId });
  if (!user) {
    return res.status(400).send({ error: `No user found with ID ${userId}` });
  }

  const friendRequests = await getUserSentRequests(userId);

  res.send(friendRequests);
}

export async function getFriendRequests(req: Request, res: Response) {
  if (!hasRequiredKeys(["userId"], req, res)) return;

  const { userId } = req.params;

  const user = await getUser({ userId });
  if (!user) {
    return res.status(400).send({ error: `No user found with ID ${userId}` });
  }

  const friendRequests = await getUserFriendRequests(userId);

  res.send(friendRequests);
}

export async function sendRequest(req: Request, res: Response) {
  if (!hasRequiredKeys(["fromUser", "toUser"], req, res)) return;

  const { fromUser, toUser } = req.body;

  const users = await getUsers([fromUser, toUser]);
  if (users.length !== 2) {
    const missingUser = [fromUser, toUser].find(
      (uId) => !users.find((u) => u.user_id === uId),
    );
    return res
      .status(400)
      .send({ error: `No user found with ID ${missingUser}` });
  }

  // Blocks are symmetric: getBlockedIds returns both directions, so neither the
  // blocker nor the blocked party can push a request at the other. This route
  // previously ignored user_blocks entirely — blocking someone did not stop
  // them from friend-requesting you again.
  const blockedIds = await getBlockedIds(fromUser);
  if (blockedIds.includes(toUser)) {
    // Deliberately the same message either way. Saying "they blocked you"
    // would leak the block back to the person who was blocked.
    return res
      .status(403)
      .send({ error: "You can't send a friend request to this user" });
  }

  // Daily ceiling — the only volume limit on this route. Admins bypass, as
  // they do for hype/nudge/flex.
  if (!(await hasUnlimitedActions(fromUser))) {
    const sentToday = await countRequestsSentToday(fromUser);
    if (sentToday >= FRIEND_REQUEST_DAILY_CEILING) {
      return res.status(429).send({
        error:
          "You've sent a lot of friend requests today. Try again tomorrow.",
      });
    }
  }

  // Whether this sender already had a push land on this target today. Checked
  // BEFORE the insert, because the insert is what makes `created` true.
  const alreadyRequestedToday = await hasRequestedFriendToday(fromUser, toUser);

  const friendResult = await sendFriendRequest(fromUser, toUser);

  if ("error" in friendResult) {
    throw new Error(friendResult.error);
  }

  // Push ONLY when a row was actually created AND we haven't already pushed
  // this pair today. The insert is ON CONFLICT DO NOTHING but the push used to
  // fire unconditionally, and friend_request is in HIGH_PRIORITY_TYPES, so
  // re-POSTing pierced quiet hours and skipped the daily cap every time.
  //
  // `created` alone isn't enough: decline and cancel DELETE the row, so a
  // send/cancel/send loop makes every insert "new" and re-pushes forever. The
  // log is what closes that. The row is still created either way — a genuine
  // re-send after an accidental cancel works, it just doesn't re-notify.
  if (friendResult.created && !alreadyRequestedToday) {
    const sender = users.find((u) => u.user_id === fromUser);
    const senderName = sender?.username || "Someone";

    // Badge + category are inert until the matching app build ships; see
    // friendRequestFeatures.ts for why they must not reach older clients.
    const clientV2 = friendRequestClientV2Enabled();
    const badge = clientV2
      ? await countPendingFriendRequests(toUser).catch(() => undefined)
      : undefined;

    // Log before dispatch: sendPush is fire-and-forget, so awaiting it isn't an
    // option, and an unlogged send would leave the pair re-pushable all day.
    await logFriendRequest(fromUser, toUser).catch((err) =>
      console.error("[Friends] Failed to log friend request:", err.message),
    );

    sendPush(toUser, {
      title: "New friend request",
      body: `${senderName} wants to be friends`,
      type: "friend_request",
      data: { user_id: fromUser },
      ...(clientV2 ? { category: "FRIEND_REQUEST" } : {}),
      ...(badge !== undefined ? { badge } : {}),
    }).catch((err) =>
      console.error(
        "[Push] Error sending friend request notification:",
        err.message,
      ),
    );
  }

  res.send(friendResult);
}

export async function getSuggestions(req: Request, res: Response) {
  if (!hasRequiredKeys(["userId"], req, res)) return;

  const { userId } = req.params;

  const user = await getUser({ userId });
  if (!user) {
    return res.status(400).send({ error: `No user found with ID ${userId}` });
  }

  const suggestions = await getFriendSuggestions(userId);

  res.send(suggestions);
}

export async function getFriendsFeed(req: Request, res: Response) {
  const userId = (req as AuthenticatedRequest).userId;
  if (!userId) {
    return res.status(401).send({ error: "Not authenticated" });
  }

  const feed = await getFriendsWorkoutFeed(userId);

  res.send(feed);
}

export async function getMutualFriends(req: Request, res: Response) {
  if (!hasRequiredKeys(["userId"], req, res)) return;

  const viewerId = (req as AuthenticatedRequest).userId;
  const { userId } = req.params;

  const count = await getMutualFriendCount(viewerId as string, userId);

  res.send({ count });
}

export async function getFriendsActivityToday(req: Request, res: Response) {
  if (!hasRequiredKeys(["userId"], req, res)) return;

  const { userId } = req.params;

  const user = await getUser({ userId });
  if (!user) {
    return res.status(400).send({ error: `No user found with ID ${userId}` });
  }

  const activity = await getActivityToday(userId);

  res.send(activity);
}

export function getFriendshipHandler(
  status: "accepted" | "rejected" | "ignored" | "removed",
) {
  return async function friendshipHandler(req: Request, res: Response) {
    if (!hasRequiredKeys(["fromUser", "toUser"], req, res)) return;

    const { fromUser, toUser } = req.body;

    const users = await getUsers([fromUser, toUser]);
    if (users.length !== 2) {
      const missingUser = [fromUser, toUser].find(
        (uId) => !users.find((u) => u.user_id === uId),
      );
      return res
        .status(400)
        .send({ error: `No user found with ID ${missingUser}` });
    }

    const friendResult = await updateFriendship(toUser, fromUser, status);

    if ("error" in friendResult) {
      if (BAD_REQUEST_ERRORS.find((e) => friendResult.error.startsWith(e))) {
        return res.status(400).send(friendResult);
      } else {
        throw new Error(friendResult.error);
      }
    }

    // Notify the original sender that their request was accepted
    if (status === "accepted") {
      // "Make a Friend" daily challenge: award whichever side just crossed
      // 0 → 1 friends. Fire-and-forget — never blocks or fails the accept.
      for (const uid of [fromUser, toUser]) {
        evaluateAddFriendCompletion(uid)
          .then((completion) => {
            if (completion) {
              fanOutFriendChallengePush(uid, completion).catch((err) =>
                console.error(
                  "[Challenges] add_friend fan-out failed:",
                  err.message,
                ),
              );
            }
          })
          .catch((err) =>
            console.error(
              "[Challenges] add_friend award failed:",
              err?.message ?? err,
            ),
          );
      }

      const accepter = users.find((u) => u.user_id === toUser);
      const accepterName = accepter?.username || "Someone";
      sendPush(fromUser, {
        title: "Friend request accepted",
        body: `${accepterName} accepted your friend request`,
        type: "friend_request_accepted",
        data: { user_id: toUser },
      }).catch((err) =>
        console.error(
          "[Push] Error sending friend accepted notification:",
          err.message,
        ),
      );
    }

    res.send(friendResult);
  };
}
