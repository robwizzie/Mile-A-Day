import type { MetadataRoute } from "next";

const BASE_URL = "https://mileaday.run";

// Generates /robots.txt. Allow crawling of the marketing pages, keep crawlers
// out of the admin console and the noindex utility routes, and point them at
// the sitemap so Google can discover everything in one hop.
export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      userAgent: "*",
      allow: "/",
      disallow: ["/admin", "/admin/", "/users"],
    },
    sitemap: `${BASE_URL}/sitemap.xml`,
    host: BASE_URL,
  };
}
