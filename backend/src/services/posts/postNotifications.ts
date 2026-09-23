// Post-related pushes: new post to friends, collab tags, crew photos, coauthor
// accepted.

import { PostgresService } from "../DbService.js";
import { userSupports, CLIENT_FEATURES } from "../clientFeatures.js";
import { sendPush } from "../pushNotificationService.js";
import { shouldSendNotification } from "../notificationSettingsService.js";

const db = PostgresService.getInstance();

/**
 * Best-effort push to the author's friends that they shared a new post/story.
 * One notification per deliberate createPost — a post going to the story AND
 * the feed together still produces a single push. Respects each friend's
 * `friend_posts_enabled` (default on), excludes blocks both ways, only
 * reaches friends whose build can open the feed/stories UI (same signal as
 * userHasFeedFeature), and is capped to avoid fan-out storms.
 *
 * Anti-spam via UPGRADE, not dismissal: when the deferred "got their mile
 * in" push is still pending (the 10-min merge window, send_after_at set —
 * audience-'ask' confirm cards have it NULL and are never touched), its
 * payload is upgraded in place to carry the photo (body + data.post_id) and
 * NO separate friend_post is sent. The original recipient pool — including
 * competition co-participants and friends on pre-feed builds — still gets
 * exactly one push on the original schedule. Only when nothing is pending
 * (posted later, mile push already sent) does the immediate friend_post
 * fan-out fire. Never throws into the caller.
 */
export async function notifyFriendsOfPost(input: {
  authorId: string;
  postId: string;
  caption: string | null;
  toFeed: boolean;
  toStory: boolean;
  localDate: string;
}): Promise<void> {
  const { authorId, postId, caption, toFeed, toStory, localDate } = input;
  try {
    const trimmedCaption = caption?.trim() ?? "";
    const storyOnly = toStory && !toFeed;
    const mergedBody =
      trimmedCaption.length > 0
        ? `📸 ${trimmedCaption.slice(0, 110)}`
        : storyOnly
          ? "and shared a story from it 📸"
          : "and shared a photo from it 📸";

    const upgraded = await db.query<{ id: string }>(
      `UPDATE pending_friend_notifications
			 SET payload = jsonb_set(
				 jsonb_set(payload, '{body}', to_jsonb($3::text)),
				 '{data,post_id}', to_jsonb($4::text)
			 )
			 WHERE user_id = $1 AND event_type = 'mile_completed'
				 AND status = 'pending' AND send_after_at IS NOT NULL
				 AND local_date = $2::date
			 RETURNING id`,
      [authorId, localDate, mergedBody, postId],
    );
    if (upgraded.length > 0) {
      // The scheduled mile push now carries the photo — one merged
      // notification per run, original pool, original timing.
      return;
    }

    // Rolling-window coalesce: don't buzz friends again if this author made
    // another deliberate post in the last few hours. A morning walk and an
    // evening run (>window apart) both notify; three quick posts in a session
    // don't triple-buzz. (The mile-merge above handles the just-finished
    // case; this caps the later-post path.) The post itself still lands in
    // the feed — only the push is suppressed.
    //
    // Probed against posts (not in_app_notifications): a prior deliberate
    // post in the window is the proxy for "already notified", and this hits
    // idx_posts_user_created (user_id, created_at) instead of full-scanning
    // the ever-growing inbox table on data->>'user_id'.
    const recent = await db.query<{ id: string }>(
      `SELECT 1 AS id FROM posts
			 WHERE user_id = $1
				 AND post_id <> $2
				 AND is_auto = false
				 AND deleted_at IS NULL
				 AND created_at > NOW() - INTERVAL '6 hours'
			 LIMIT 1`,
      [authorId, postId],
    );
    if (recent.length > 0) return;

    const recipients = await db.query<{ uid: string }>(
      `SELECT f.friend_id AS uid
				 FROM friendships f
				 LEFT JOIN notification_settings ns ON ns.user_id = f.friend_id
				 WHERE f.user_id = $1 AND f.status = 'accepted'
					 AND COALESCE(ns.friend_posts_enabled, true) = true
					 AND f.friend_id NOT IN (
						 SELECT blocked_id FROM user_blocks WHERE blocker_id = $1
						 UNION
						 SELECT blocker_id FROM user_blocks WHERE blocked_id = $1
					 )
					 AND (
						 EXISTS (SELECT 1 FROM posts fp WHERE fp.user_id = f.friend_id)
						 OR EXISTS (
							 SELECT 1 FROM users fu
							 WHERE fu.user_id = f.friend_id
								 AND fu.terms_accepted_at IS NOT NULL
						 )
					 )
				 LIMIT 25`,
      [authorId],
    );
    if (recipients.length === 0) return;

    const authorRows = await db.query<{ username: string | null }>(
      `SELECT username FROM users WHERE user_id = $1`,
      [authorId],
    );
    const name = authorRows[0]?.username ?? "A friend";
    const title = storyOnly
      ? `${name} added to their story ✨`
      : `${name} posted 📸`;
    const body =
      trimmedCaption.length > 0
        ? trimmedCaption.slice(0, 120)
        : storyOnly
          ? "shared a new story"
          : "shared a new post";

    for (const r of recipients) {
      sendPush(r.uid, {
        title,
        body,
        type: "friend_post",
        // kind routes the tap client-side ("story" opens the story viewer,
        // "post" lands on the feed entry); post_id is additive deep-link data.
        data: {
          user_id: authorId,
          kind: storyOnly ? "story" : "post",
          post_id: postId,
        },
      }).catch((e: any) =>
        console.error("[notifyFriendsOfPost]", e?.message ?? e),
      );
    }
  } catch (e: any) {
    console.error("[notifyFriendsOfPost] failed:", e?.message ?? e);
  }
}

/**
 * Would a NEW tag on `coauthorId` land on their profile grid? Reads the
 * setting alone — a brand-new tag has no per-post override yet. Only used to
 * word the tag push truthfully; the grid query resolves this itself.
 */
async function taggedPostsLandOnProfile(coauthorId: string): Promise<boolean> {
  const rows = await db.query<{ on_profile: boolean | null }>(
    `SELECT tagged_posts_on_profile AS on_profile
		 FROM notification_settings WHERE user_id = $1`,
    [coauthorId],
  );
  return rows[0]?.on_profile ?? true;
}

/**
 * Push "you've been tagged" to the coauthor. Never throws.
 *
 * The post is ALREADY on their profile by the time this sends — there's no
 * invite to answer, so the push is an FYI with a way out, not a decision.
 * Devices that registered the collab-tag capability additionally get a
 * "Remove me" action button, so opting out never requires opening the app.
 */
export async function notifyCoauthorInvite(
  authorId: string,
  coauthorId: string,
  postId: string,
): Promise<void> {
  try {
    if (!(await shouldSendNotification(coauthorId, authorId, "hype"))) return;
    const rows = await db.query<{ username: string | null }>(
      `SELECT username FROM users WHERE user_id = $1`,
      [authorId],
    );
    const name = rows[0]?.username ?? "A friend";
    const canRemoveInline = await userSupports(
      coauthorId,
      CLIENT_FEATURES.collabTagV1,
    );
    // Say where it actually went. Telling someone with tags-off-my-grid that
    // it's "on your profile now" is simply false, and it's the one line that
    // would send them hunting for a post that isn't there.
    const onProfile = await taggedPostsLandOnProfile(coauthorId);
    await sendPush(coauthorId, {
      title: `${name} tagged you in their post 🤝`,
      body: onProfile
        ? "It's on your profile now — you can remove yourself any time."
        : "It's in your Tagged tab — you can remove yourself any time.",
      // Type unchanged: every shipped build routes `coauthor_invite`, and a new
      // string would tap to nothing on all of them.
      type: "coauthor_invite",
      ...(canRemoveInline ? { category: "COAUTHOR_TAG" } : {}),
      data: { user_id: authorId, post_id: postId },
    });
  } catch (e: any) {
    console.error("[notifyCoauthorInvite] failed:", e?.message ?? e);
  }
}

/**
 * "Sam added their photo to your walk."
 *
 * The moment that makes a shared card feel alive rather than static: without
 * it, a buddy post is a thing one person made and everyone else silently
 * appended to, and nobody ever goes back to look. Goes to the AUTHOR and to
 * every other credited participant, because on a four-person walk the third
 * photo landing is news to all three of the others, not just the poster.
 *
 * Type string is new, so it's gated on `buddyGroupPostV1` — an older build has
 * no route for it and would show a banner that taps to nothing. Same reason
 * the `post_id` rides in `data`: the client opens the post directly. Every
 * value there stays a STRING (shipped builds decode the inbox as
 * `[String: String]`, and one number breaks the whole decode).
 *
 * Never throws — a failed push must not fail the photo.
 */
export async function notifyCrewPhoto(
  postId: string,
  actorId: string,
): Promise<void> {
  try {
    const rows = await db.query<{ user_id: string }>(
      // Everyone on the post except whoever just added the photo. The author
      // is unioned in explicitly: they have no post_coauthors row of their own.
      `SELECT p.user_id FROM posts p
        WHERE p.post_id = $1 AND p.deleted_at IS NULL AND p.user_id <> $2
        UNION
       SELECT pca.user_id FROM post_coauthors pca
        WHERE pca.post_id = $1 AND pca.status = 'accepted' AND pca.user_id <> $2`,
      [postId, actorId],
    );
    if (rows.length === 0) return;

    const actor = await db.query<{ username: string | null }>(
      `SELECT username FROM users WHERE user_id = $1`,
      [actorId],
    );
    const name = actor[0]?.username ?? "A friend";

    for (const { user_id: recipient } of rows) {
      if (!(await shouldSendNotification(recipient, actorId, "hype"))) continue;
      if (!(await userSupports(recipient, CLIENT_FEATURES.buddyGroupPostV1))) {
        continue;
      }
      await sendPush(recipient, {
        title: `${name} added their photo 📸`,
        body: "It's on your walk's post — go see it.",
        type: "crew_photo",
        data: { user_id: actorId, post_id: postId },
      });
    }
  } catch (e: any) {
    console.error("[notifyCrewPhoto] failed:", e?.message ?? e);
  }
}

/** Tell the author their invited coauthor accepted. Never throws. */
export async function notifyCoauthorAccepted(
  coauthorId: string,
  authorId: string,
  postId: string,
): Promise<void> {
  try {
    if (!(await shouldSendNotification(authorId, coauthorId, "hype"))) return;
    const rows = await db.query<{ username: string | null }>(
      `SELECT username FROM users WHERE user_id = $1`,
      [coauthorId],
    );
    const name = rows[0]?.username ?? "Your friend";
    await sendPush(authorId, {
      title: `${name} joined your post 🤝`,
      body: "You're sharing this mile together",
      type: "coauthor_accepted",
      data: { user_id: coauthorId, post_id: postId },
    });
  } catch (e: any) {
    console.error("[notifyCoauthorAccepted] failed:", e?.message ?? e);
  }
}
