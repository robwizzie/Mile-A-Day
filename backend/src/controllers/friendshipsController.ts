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
} from "../services/friendshipService.js";
import { friendRequestClientV2Enabled } from "../services/friendRequestFeatures.js";
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

  const friendResult = await sendFriendRequest(fromUser, toUser);

  if ("error" in friendResult) {
    throw new Error(friendResult.error);
  }

  // Push ONLY when a row was actually created. The insert is ON CONFLICT DO
  // NOTHING, but this push used to fire unconditionally — so re-POSTing the
  // same request sent unlimited pushes, and friend_request is in
  // HIGH_PRIORITY_TYPES, meaning every one of them pierced quiet hours and
  // skipped the daily cap. There is no rate limit on this route.
  if (friendResult.created) {
    const sender = users.find((u) => u.user_id === fromUser);
    const senderName = sender?.username || "Someone";

    // Badge + category are inert until the matching app build ships; see
    // friendRequestFeatures.ts for why they must not reach older clients.
    const clientV2 = friendRequestClientV2Enabled();
    const badge = clientV2
      ? await countPendingFriendRequests(toUser).catch(() => undefined)
      : undefined;

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
