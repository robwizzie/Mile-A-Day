import type { MetadataRoute } from "next";

// /manifest.webmanifest: names and colours for "Add to Home Screen" and for
// browsers/search engines that read it. The real app is on the App Store —
// `related_applications` says so, and `prefer_related_applications` stays
// false because this site is a page, not a stand-in for the app.
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Mile A Day",
    short_name: "Mile A Day",
    description:
      "Walk or run a mile every day. Build your streak, compete with friends, and earn medals.",
    start_url: "/",
    display: "standalone",
    background_color: "#0a0a0a",
    theme_color: "#0a0a0a",
    icons: [
      {
        src: "/images/mad-circle-icon.png",
        sizes: "256x256",
        type: "image/png",
      },
    ],
    related_applications: [
      {
        platform: "itunes",
        url: "https://apps.apple.com/us/app/mile-a-day/id6746970905",
        id: "6746970905",
      },
    ],
    prefer_related_applications: false,
  };
}
