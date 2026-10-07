// The ONE resolver for a public profile — imported by the profile page AND its
// opengraph unfurl image, so the two can never describe a different person.
// Everything here is world-readable at `/public/users/:username`.

export const API_URL =
  process.env.NEXT_PUBLIC_API_URL || "https://mad.mindgoblin.tech";

export type PublicProfile = {
  user_id: string;
  username: string | null;
  first_name: string | null;
  last_name: string | null;
  bio: string | null;
  profile_image_url: string | null;
  current_streak: number;
};

export async function getPublicProfile(
  username: string,
): Promise<PublicProfile | null> {
  try {
    const res = await fetch(
      `${API_URL}/public/users/${encodeURIComponent(username)}`,
      { next: { revalidate: 300 } },
    );
    if (!res.ok) return null;
    return res.json();
  } catch {
    return null;
  }
}

export function displayName(profile: PublicProfile): string {
  if (profile.first_name && profile.last_name)
    return `${profile.first_name} ${profile.last_name}`;
  if (profile.first_name) return profile.first_name;
  return profile.username ?? "A runner";
}

export function profileInitials(profile: PublicProfile): string {
  return displayName(profile)
    .split(" ")
    .map((part) => part[0])
    .slice(0, 2)
    .join("")
    .toUpperCase();
}

/** Absolute avatar URL; a stored absolute URL is passed through, not re-prefixed. */
export function profileAvatarURL(profile: PublicProfile): string | null {
  const path = profile.profile_image_url;
  if (!path) return null;
  return /^https?:\/\//.test(path) ? path : `${API_URL}${path}`;
}

/** Zero is not a badge; a missing value is not a zero. */
export function profileStreak(profile: PublicProfile | null): number | null {
  const streak = profile?.current_streak;
  return typeof streak === "number" && streak > 0 ? streak : null;
}
