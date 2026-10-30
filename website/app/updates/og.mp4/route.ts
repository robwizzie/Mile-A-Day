import { CURRENT_RELEASE } from "@/lib/releases";
import { ogVideoResponse } from "../../_og/video/serve";
import { updatesScene } from "../../_og/video/scenes/updates";

// /updates' og:video: the current release from lib/releases.ts.
export const dynamic = "force-dynamic";
export const maxDuration = 60;

const WEEK = 7 * 24 * 3600;

export function GET(req: Request) {
  return ogVideoResponse(req, {
    key: `updates/${CURRENT_RELEASE.version}`,
    ttl: WEEK,
    scene: updatesScene,
  });
}

export { GET as HEAD };
