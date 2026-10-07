import { ImageResponse } from "next/og";

// The link unfurl for a shared post (iMessage, Slack, socials): a branded card
// naming the author, with their real avatar and streak.
//
// Deliberately NO route, photo, caption or distance. A post is friends-only
// content and this image travels the open web — a link forwarded out of the
// group chat it was meant for is the normal case, not the edge case — so the
// image follows the page's own signpost rule: confirm the link is real, say
// whose post it is, look like the app. Everything on it is already
// world-readable for that username at `/public/users/:username`.

import {
  OG_SIZE,
  PersonCard,
  iconDataURI,
  ogFonts,
  remoteImageDataURI,
} from "../../_og/shared";
import {
  getPublicPost,
  publicAuthorInitials,
  publicAuthorName,
  publicAvatarURL,
  publicStreak,
} from "./publicPost";

export const alt = "A Mile A Day post";
export const size = OG_SIZE;
export const contentType = "image/png";

export default async function Image({
  params,
}: {
  params: Promise<{ postId: string }>;
}) {
  const { postId } = await params;
  // `getPublicPost` already swallows failures into null, and every reader below
  // handles null — the unfurl degrades to "A runner", it never 500s.
  const post = await getPublicPost(postId);
  const [fonts, icon, avatar] = await Promise.all([
    ogFonts(),
    iconDataURI(),
    remoteImageDataURI(publicAvatarURL(post)),
  ]);
  // First name large with the handle under it, when both exist; otherwise the
  // same name the page's <title> uses.
  const name = post?.first_name ?? publicAuthorName(post);
  const handle =
    post?.first_name && post.username ? `@${post.username}` : null;

  return new ImageResponse(
    <PersonCard
      icon={icon}
      avatar={avatar}
      initials={publicAuthorInitials(post)}
      name={name}
      handle={handle}
      streak={publicStreak(post)}
      headline="shared a post on Mile A Day"
      footnote="Posts are for friends — open it in the app to see it."
    />,
    { ...size, fonts },
  );
}
