import { ogVideoResponse } from "../_og/video/serve";
import { homeScene } from "../_og/video/scenes/home";

// The home page's og:video (layout.tsx / page.tsx point at it). The PNG card
// beside it (opengraph-image.tsx) stays the og:image fallback.
export const dynamic = "force-dynamic";
export const maxDuration = 60;

const WEEK = 7 * 24 * 3600;

export function GET(req: Request) {
  return ogVideoResponse(req, { key: "home", ttl: WEEK, scene: homeScene });
}

export { GET as HEAD };
