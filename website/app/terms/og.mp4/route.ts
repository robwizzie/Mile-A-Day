import { ogVideoResponse } from "../../_og/video/serve";
import { TERMS, legalScene } from "../../_og/video/scenes/legal";

// /terms's og:video.
export const dynamic = "force-dynamic";
export const maxDuration = 60;

const WEEK = 7 * 24 * 3600;

export function GET(req: Request) {
  return ogVideoResponse(req, { key: "terms", ttl: WEEK, scene: () => legalScene(TERMS) });
}

export { GET as HEAD };
