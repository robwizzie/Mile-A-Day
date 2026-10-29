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
  // Additive (backend publicProfileService). Absent on an older API — every
  // reader treats missing exactly like null.
  profile_banner_style?: string | null;
  profile_banner_url?: string | null;
  /** null = a 'private' account withholds it (never a zero). */
  total_miles?: number | null;
  friend_count?: number | null;
  medals?: PublicMedal[] | null;
};

export type PublicMedal = {
  badge_id: string;
  name: string;
  icon: string;
  rarity: string;
  category: string;
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

function absoluteUploadURL(path: string | null | undefined): string | null {
  if (!path) return null;
  return /^https?:\/\//.test(path) ? path : `${API_URL}${path}`;
}

/** Absolute avatar URL; a stored absolute URL is passed through, not re-prefixed. */
export function profileAvatarURL(profile: PublicProfile): string | null {
  return absoluteUploadURL(profile.profile_image_url);
}

/** Absolute uploaded-banner URL (served unsigned, like avatars). */
export function profileBannerURL(profile: PublicProfile): string | null {
  return absoluteUploadURL(profile.profile_banner_url);
}

// The app's ProfileBannerStyle presets (Views/Profile/ProfileHero.swift):
// two MADTheme stops each, drawn as [a, b·0.9, b·0.32] top-leading →
// bottom-trailing over black. Unknown or absent ⇒ ember, like
// `ProfileBannerStyle.resolve`.
const BANNER_STOPS: Record<string, [string, string]> = {
  ember: ["230,77,102", "217,64,89"], // redGradient → madRed
  sunrise: ["255,153,0", "217,64,89"], // warning → madRed
  sky: ["64,153,242", "64,153,242"], // walkBlue
  trail: ["51,179,77", "51,179,77"], // success
  ghost: ["107,79,217", "61,46,140"], // the "beat the ghost" chip
  night: ["38,38,38", "13,13,13"], // blackGradient
};

/** The preset's two "r,g,b" stops (the og.mp4 video draws them itself). */
export function bannerStops(style: string | null | undefined): [string, string] {
  const [a, b] = BANNER_STOPS[style ?? ""] ?? BANNER_STOPS.ember;
  return [a, b];
}

/** The preset as a CSS gradient image — lay it over black, as the app does. */
export function bannerGradient(style: string | null | undefined): string {
  const [a, b] = bannerStops(style);
  return `linear-gradient(135deg, rgb(${a}), rgba(${b},0.9), rgba(${b},0.32))`;
}

/** The Miles tile's figure: whole miles from 100, one decimal below (ProfileStatTiles). */
export function formatMiles(miles: number): string {
  return miles >= 100
    ? Math.round(miles).toLocaleString("en-US")
    : (Math.floor(miles * 10) / 10).toFixed(1);
}

/** Zero is not a badge; a missing value is not a zero. */
export function profileStreak(profile: PublicProfile | null): number | null {
  const streak = profile?.current_streak;
  return typeof streak === "number" && streak > 0 ? streak : null;
}
