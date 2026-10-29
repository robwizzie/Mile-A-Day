import { SITE_URL } from "@/lib/site";
import { VIDEO } from "./config";

// The og:video tags for a page whose segment has an og.mp4 route. Kept apart
// from the renderer so a page's metadata never imports the canvas/encoder.
// The PNG from the page's opengraph-image stays as og:image: the poster, and
// the whole preview wherever og:video isn't played (X, LinkedIn, WhatsApp…).
export function ogVideos(path: string) {
  const url = `${SITE_URL}${path}`;
  return [
    {
      url,
      secureUrl: url,
      type: "video/mp4",
      width: VIDEO.width,
      height: VIDEO.height,
    },
  ];
}
