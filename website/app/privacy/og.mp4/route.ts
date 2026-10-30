import { ogVideoResponse } from "../../_og/video/serve";
import { PRIVACY, legalScene } from "../../_og/video/scenes/legal";

// /privacy's og:video.
export const dynamic = "force-dynamic";
export const maxDuration = 60;

const WEEK = 7 * 24 * 3600;

export function GET(req: Request) {
  return ogVideoResponse(req, { key: "privacy", ttl: WEEK, scene: () => legalScene(PRIVACY) });
}

export { GET as HEAD };
