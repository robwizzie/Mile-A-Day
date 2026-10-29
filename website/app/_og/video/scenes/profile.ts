import {
  bannerStops,
  displayName,
  formatMiles,
  profileAvatarURL,
  profileBannerURL,
  profileInitials,
  profileStreak,
  type PublicProfile,
} from "../../../u/[username]/publicProfile";
import { ogAsset, remoteImage, type Scene } from "../render";
import { personScene } from "./person";

// /u/<username>'s video: the same facts as its PNG card (opengraph-image.tsx
// beside the page) — name, banner, streak, and the stats line only when the
// account shares it. An unknown user still gets a branded video, never a 500.
export async function profileScene(profile: PublicProfile | null): Promise<Scene> {
  const [icon, avatar, bannerImage] = await Promise.all([
    ogAsset("icon.png"),
    remoteImage(profile ? profileAvatarURL(profile) : null),
    remoteImage(profile ? profileBannerURL(profile) : null),
  ]);
  const name = profile ? displayName(profile) : "A Mile A Day runner";
  const handle = profile?.username ? `@${profile.username}` : null;
  const miles = profile?.total_miles;
  const friends = profile?.friend_count;

  return personScene({
    icon,
    avatar,
    initials: profile ? profileInitials(profile) : "M",
    name,
    handle: handle && handle.slice(1) !== name ? handle : null,
    streak: profileStreak(profile),
    stats:
      miles != null && friends != null
        ? {
            miles,
            friends,
            // Counting up through formatMiles' own steps, ending on its figure.
            milesText: (n) => `${formatMiles(n)} ${miles === 1 ? "mile" : "miles"}`,
          }
        : null,
    banner: profile
      ? { stops: bannerStops(profile.profile_banner_style), image: bannerImage }
      : null,
    headline: "is walking a mile every day",
    footnote: "Add them on Mile A Day and keep each other moving.",
    seed: `u/${profile?.username ?? ""}`,
  });
}
