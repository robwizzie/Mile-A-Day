import { ImageResponse } from "next/og";
import {
  OG_SIZE,
  PersonCard,
  iconDataURI,
  ogFonts,
  remoteImageDataURI,
} from "../../_og/shared";
import {
  displayName,
  getPublicProfile,
  profileAvatarURL,
  profileInitials,
  profileStreak,
} from "./publicProfile";

// The unfurl for a shared profile link: who it is, their streak, and the
// invite. Only what `/public/users/:username` already publishes.
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
  const [fonts, icon, avatar] = await Promise.all([
    ogFonts(),
    iconDataURI(),
    remoteImageDataURI(profile ? profileAvatarURL(profile) : null),
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
      headline="is walking a mile every day"
      footnote="Add them on Mile A Day and keep each other moving."
    />,
    { ...size, fonts },
  );
}
