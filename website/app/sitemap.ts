import type { MetadataRoute } from "next";

const BASE_URL = "https://mileaday.run";

// /sitemap.xml: the indexable static pages. Profiles (/u/<username>) aren't
// listed — there's no public directory of users, and they're discovered by
// the links people share. `lastModified` is the real edit date, not the build
// time: a lastmod that changes on every deploy teaches Google to ignore it.
// Bump the legal dates alongside their `lastUpdated` in the page.
export default function sitemap(): MetadataRoute.Sitemap {
  return [
    {
      url: `${BASE_URL}/`,
      changeFrequency: "weekly",
      priority: 1,
    },
    {
      url: `${BASE_URL}/privacy`,
      lastModified: "2026-05-16",
      changeFrequency: "yearly",
      priority: 0.3,
    },
    {
      url: `${BASE_URL}/terms`,
      lastModified: "2026-05-16",
      changeFrequency: "yearly",
      priority: 0.3,
    },
  ];
}
