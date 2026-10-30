import { ogVideoResponse } from "../../_og/video/serve";
import { deskScene } from "../../_og/video/scenes/desk";

// /desk's og:video: the box's own code drawing the live community numbers,
// so it's redrawn every ten minutes (in the background, serving the last one).
export const dynamic = "force-dynamic";
export const maxDuration = 60;

export function GET(req: Request) {
  return ogVideoResponse(req, { key: "desk", ttl: 600, scene: deskScene });
}

export { GET as HEAD };
