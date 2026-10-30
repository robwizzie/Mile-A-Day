import {
  publicAuthorInitials,
  publicAuthorName,
  publicAvatarURL,
  publicStreak,
  type PublicPost,
} from "../../../p/[postId]/publicPost";
import { ogAsset, remoteImage, type Scene } from "../render";
import { personScene } from "./person";

// /p/<id>'s video: the AUTHOR only, exactly like its PNG card. A post is
// friends-only and this video travels the open web, so nothing of the post
// (photo, route, distance, caption) is drawn — the tile beside them is a
// locked placeholder with an invented route.
export async function postScene(post: PublicPost | null): Promise<Scene> {
  const [icon, avatar] = await Promise.all([
    ogAsset("icon.png"),
    remoteImage(publicAvatarURL(post)),
  ]);
  return personScene({
    icon,
    avatar,
    initials: publicAuthorInitials(post),
    name: post?.first_name ?? publicAuthorName(post),
    handle: post?.first_name && post.username ? `@${post.username}` : null,
    streak: publicStreak(post),
    stats: null,
    banner: null,
    headline: "shared a post on Mile A Day",
    footnote: "Posts are for friends — open it in the app to see it.",
    post: true,
    seed: `p/${post?.post_id ?? ""}`,
  });
}
