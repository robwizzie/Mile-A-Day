import { factsKey, ogVideoResponse } from "../../../_og/video/serve";
import { profileScene } from "../../../_og/video/scenes/profile";
import { getPublicProfile } from "../publicProfile";

// A profile's og:video. Keyed by exactly what it draws, so a new streak,
// avatar or banner is a new video straight away — and every unknown username
// shares the one generic video instead of costing a render each.
export const dynamic = "force-dynamic";
export const maxDuration = 60;

export async function GET(
  req: Request,
  { params }: { params: Promise<{ username: string }> },
) {
  const { username } = await params;
  const profile = await getPublicProfile(username);
  const key = profile
    ? factsKey("u", [
        profile.username,
        profile.first_name,
        profile.last_name,
        profile.profile_image_url,
        profile.current_streak,
        profile.profile_banner_style,
        profile.profile_banner_url,
        profile.total_miles,
        profile.friend_count,
      ])
    : "u/unknown";
  return ogVideoResponse(req, {
    key,
    ttl: 24 * 3600,
    scene: () => profileScene(profile),
  });
}

export { GET as HEAD };
