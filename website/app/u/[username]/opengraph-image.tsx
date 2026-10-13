import { ImageResponse } from "next/og";
import {
  OG_SIZE,
  PersonCard,
  iconDataURI,
  ogFonts,
  remoteImageDataURI,
} from "../../_og/shared";
import {
  bannerGradient,
  displayName,
  formatMiles,
  getPublicProfile,
  profileAvatarURL,
  profileBannerURL,
  profileInitials,
  profileStreak,
  type PublicProfile,
} from "./publicProfile";

// The unfurl for a shared profile link: who it is, their banner, streak and
// shared stats, and the invite. Only what `/public/users/:username` already
// publishes — a 'private' account's withheld stats come back null and stay off.
export const alt = "A Mile A Day profile";
export const size = OG_SIZE;
export const contentType = "image/png";

export default async function Image({
  params,
}: {
  params: Promise<{ username: string }>;
}) {
  const { username } = await params;
  // Never throws: an unknown user still gets a branded card, never a 500.
  const profile = await getPublicProfile(username);
  const [fonts, icon, avatar, bannerImage] = await Promise.all([
    ogFonts(),
    iconDataURI(),
    remoteImageDataURI(profile ? profileAvatarURL(profile) : null),
    remoteImageDataURI(profile ? profileBannerURL(profile) : null),
  ]);
  const name = profile ? displayName(profile) : "A Mile A Day runner";
  const handle = profile?.username ? `@${profile.username}` : null;

  return new ImageResponse(
    <PersonCard
      icon={icon}
      avatar={avatar}
      initials={profile ? profileInitials(profile) : "M"}
      name={name}
      handle={handle && handle.slice(1) !== name ? handle : null}
      streak={profileStreak(profile)}
      stats={profile ? statsLine(profile) : null}
      banner={
        profile
          ? { gradient: bannerGradient(profile.profile_banner_style), image: bannerImage }
          : null
      }
      headline="is walking a mile every day"
      footnote="Add them on Mile A Day and keep each other moving."
    />,
    { ...size, fonts },
  );
}

/** "312 miles · 14 friends"; null when the account withholds its stats. */
function statsLine(profile: PublicProfile): string | null {
  const miles = profile.total_miles;
  const friends = profile.friend_count;
  if (miles == null || friends == null) return null;
  const milesText = `${formatMiles(miles)} ${miles === 1 ? "mile" : "miles"}`;
  return `${milesText} · ${friends.toLocaleString("en-US")} ${friends === 1 ? "friend" : "friends"}`;
}
