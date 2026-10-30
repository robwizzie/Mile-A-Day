import { factsKey, ogVideoResponse } from "../../../_og/video/serve";
import { postScene } from "../../../_og/video/scenes/post";
import { getPublicPost } from "../publicPost";

// A post's og:video — its AUTHOR, never the post (see publicPost.ts). Keyed by
// what it draws; every unknown post shares one generic video.
export const dynamic = "force-dynamic";
export const maxDuration = 60;

export async function GET(
  req: Request,
  { params }: { params: Promise<{ postId: string }> },
) {
  const { postId } = await params;
  const post = await getPublicPost(postId);
  const key = post
    ? factsKey("p", [
        post.post_id,
        post.username,
        post.first_name,
        post.profile_image_url,
        post.current_streak,
      ])
    : "p/unknown";
  return ogVideoResponse(req, {
    key,
    ttl: 24 * 3600,
    scene: () => postScene(post),
  });
}

export { GET as HEAD };
