// The ONE resolver for a shared post's public preview — imported by the
// signpost page AND its opengraph unfurl image, so the two can never name a
// different person for the same link. Deliberately just the AUTHOR: a post is
// friends-only content and these surfaces travel the open web.
//
// "Just the author" now includes their avatar and streak, which is not a
// widening: both are already world-readable for any username at
// `/public/users/:username`, and profile images are the one media path the
// backend deliberately leaves unsigned precisely because they back share pages.
// Nothing about the POST itself — no photo, no route, no distance, no caption —
// appears here or in the image.

export const API_URL =
  process.env.NEXT_PUBLIC_API_URL || "https://mad.mindgoblin.tech";

export type PublicPost = {
  post_id: string;
  username: string | null;
  first_name: string | null;
  profile_image_url: string | null;
  current_streak: number | null;
};

export async function getPublicPost(
  postId: string,
): Promise<PublicPost | null> {
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

/** Two letters for the avatar fallback — the same source the name comes from. */
export function publicAuthorInitials(post: PublicPost | null): string {
  return (post?.username ?? post?.first_name ?? "M").slice(0, 2).toUpperCase();
}

/**
 * Absolute URL for the author's avatar, or null when they have none.
 *
 * The backend stores a bare path; older rows (and any future absolute URL) are
 * passed through untouched rather than double-prefixed.
 */
export function publicAvatarURL(post: PublicPost | null): string | null {
  const path = post?.profile_image_url;
  if (!path) return null;
  return /^https?:\/\//.test(path) ? path : `${API_URL}${path}`;
}

/**
 * The streak worth printing. Zero is not a badge, and a missing value is not a
 * zero — an older server that doesn't send the field must not publish "0 day
 * streak" over somebody's 400-day run.
 */
export function publicStreak(post: PublicPost | null): number | null {
  const streak = post?.current_streak;
  return typeof streak === "number" && streak > 0 ? streak : null;
}
