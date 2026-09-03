// The ONE resolver for a shared post's public preview — imported by the
// signpost page AND its opengraph unfurl image, so the two can never name a
// different person for the same link. Deliberately just the author: a post is
// friends-only content and these surfaces travel the open web.

export const API_URL =
  process.env.NEXT_PUBLIC_API_URL || "https://mad.mindgoblin.tech";

export type PublicPost = {
  post_id: string;
  username: string | null;
  first_name: string | null;
};

export async function getPublicPost(postId: string): Promise<PublicPost | null> {
  try {
    const res = await fetch(
      `${API_URL}/public/posts/${encodeURIComponent(postId)}`,
      { next: { revalidate: 300 } },
    );
    if (!res.ok) return null;
    return res.json();
  } catch {
    return null;
  }
}

export function publicAuthorName(post: PublicPost | null): string {
  if (post?.username) return `@${post.username}`;
  if (post?.first_name) return post.first_name;
  return "A runner";
}
