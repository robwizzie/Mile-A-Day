import type { MetadataRoute } from "next";

const BASE_URL = "https://mileaday.run";

// Generates /sitemap.xml. Only the indexable marketing + legal pages are
// listed. Dynamic /u/<username> profiles and the noindex /admin and /users
// routes are intentionally excluded.
export default function sitemap(): MetadataRoute.Sitemap {
  const lastModified = new Date();

  return [
    {
      url: `${BASE_URL}/`,
      lastModified,
      changeFrequency: "weekly",
      priority: 1,
    },
    {
      url: `${BASE_URL}/privacy`,
      lastModified,
      changeFrequency: "yearly",
      priority: 0.3,
    },
    {
      url: `${BASE_URL}/terms`,
      lastModified,
      changeFrequency: "yearly",
      priority: 0.3,
    },
  ];
}
