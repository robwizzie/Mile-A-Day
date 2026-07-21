import { PostgresService } from "./DbService.js";
import { sendPush } from "./pushNotificationService.js";
import { shouldSendNotification } from "./notificationSettingsService.js";
import { visiblePostAuthor } from "./postService.js";

const db = PostgresService.getInstance();

// @username tokens: letters/digits/._- with trailing punctuation dots
// stripped ("nice one @rob."). Usernames resolve case-insensitively.
const MENTION_RE = /@([a-zA-Z0-9._-]+)/g;
const MAX_MENTIONS = 10;

export interface MentionedUser {
  user_id: string;
  username: string;
}

/** Distinct lowercased @usernames in the text, capped at MAX_MENTIONS. */
export function extractMentionUsernames(text: string): string[] {
  const found = new Set<string>();
  for (const match of text.matchAll(MENTION_RE)) {
    const username = match[1].replace(/\.+$/, "").toLowerCase();
    if (username.length > 0) found.add(username);
    if (found.size >= MAX_MENTIONS) break;
  }
  return [...found];
}

/** Resolve @usernames in `text` to real users, excluding the sender. */
export async function resolveMentions(
  text: string,
  excludeUserId: string,
): Promise<MentionedUser[]> {
  const usernames = extractMentionUsernames(text);
  if (usernames.length === 0) return [];
  const rows = await db.query<MentionedUser>(
    `SELECT user_id, username FROM users
		 WHERE lower(username) = ANY($1::text[]) AND user_id <> $2`,
    [usernames, excludeUserId],
  );
  return rows;
}

/**
 * Push "X mentioned you" to each mentioned user who can actually view the
 * post (author or accepted friend of the author, no blocks). Fire-and-forget;
 * gated on the shared social-interactions pref like hypes/story reactions.
 */
export async function notifyMentions(
  senderId: string,
  recipients: MentionedUser[],
  postId: string,
  content: string,
  where: "comment" | "post",
): Promise<void> {
  if (recipients.length === 0) return;
  const sender = await db.query<{ username: string | null }>(
    `SELECT username FROM users WHERE user_id = $1`,
    [senderId],
  );
  const name = sender[0]?.username ?? "A friend";
  const body = content.slice(0, 120);

  for (const r of recipients) {
    if (r.user_id === senderId) continue;
    if (!(await visiblePostAuthor(r.user_id, postId))) continue;
    if (!(await shouldSendNotification(r.user_id, senderId, "hype"))) continue;
    sendPush(r.user_id, {
      title: `${name} mentioned you in a ${where === "comment" ? "comment" : "post"} 💬`,
      body,
      type: "mention",
      data: { user_id: senderId, post_id: postId },
    }).catch((e: any) =>
      console.error("[notifyMentions] push failed:", e?.message ?? e),
    );
  }
}

/** Resolve + notify caption @mentions on a new post. Never throws. */
export async function notifyCaptionMentions(
  authorId: string,
  postId: string,
  caption: string,
): Promise<void> {
  try {
    const mentioned = await resolveMentions(caption, authorId);
    await notifyMentions(authorId, mentioned, postId, caption, "post");
  } catch (e: any) {
    console.error("[notifyCaptionMentions] failed:", e?.message ?? e);
  }
}
