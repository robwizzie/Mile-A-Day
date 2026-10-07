import type { MetadataRoute } from "next";

const BASE_URL = "https://mileaday.run";

// /robots.txt: crawl the marketing site, profiles and post signposts (post
// pages carry their own noindex), stay out of the admin console, the internal
// live counter, the API and the desk-preview assets, and point at the sitemap.
export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      userAgent: "*",
      allow: "/",
      disallow: ["/admin", "/users", "/api/", "/desk/"],
    },
    sitemap: `${BASE_URL}/sitemap.xml`,
    host: BASE_URL,
  };
}
