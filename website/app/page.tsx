import type { Metadata } from "next";
import { Navbar } from "@/components/navbar";
import { HeroSection } from "@/components/hero-section";
import { FeaturePanels } from "@/components/feature-panels";
import { NumbersSection } from "@/components/numbers-section";
import { WhatsNewSection } from "@/components/whats-new-section";
import { StorySection } from "@/components/story-section";
import { SupportSection } from "@/components/support-section";
import { DeskTeaserSection } from "@/components/desk-teaser-section";
import { CtaSection } from "@/components/cta-section";
import { Footer } from "@/components/footer";
import { CURRENT_RELEASE } from "@/lib/releases";
import { APP_STORE_URL, SITE_URL, SUPPORT_EMAIL } from "@/lib/site";
import { ogVideos } from "./_og/video/meta";

export const metadata: Metadata = {
  alternates: { canonical: "/" },
  // Restated in full: a page's openGraph replaces the root one rather than
  // merging, and og:url is the piece only the home page should carry.
  openGraph: {
    title: "Mile A Day - Walk or Run a Mile Every Single Day",
    description:
      "Build an unbreakable habit. Track your streak, compete with friends, and Go the Extra Mile.",
    url: "/",
    type: "website",
    siteName: "Mile A Day",
    locale: "en_US",
    videos: ogVideos("/og.mp4"),
  },
  // Smart App Banner: iOS Safari offers "Get"/"Open" for the app up top.
  itunes: { appId: "6746970905" },
};

// schema.org data so search engines know mileaday.run is the home of a free
// iPhone + Apple Watch app (and who makes it). Facts only — nothing here may
// claim a rating or review count the App Store doesn't publish for us.
const structuredData = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "Organization",
      "@id": `${SITE_URL}/#organization`,
      name: "Mile A Day",
      url: SITE_URL,
      logo: `${SITE_URL}/images/mad-circle-icon.png`,
      email: SUPPORT_EMAIL,
      contactPoint: {
        "@type": "ContactPoint",
        contactType: "customer support",
        email: SUPPORT_EMAIL,
      },
      founder: [
        { "@type": "Person", name: "Rob Wiscount" },
        { "@type": "Person", name: "David Simmerman" },
      ],
      sameAs: [
        APP_STORE_URL,
        "https://www.instagram.com/mileadayapp",
        "https://www.tiktok.com/@mileadayapp",
        "https://x.com/mileadayapp",
      ],
    },
    {
      "@type": "WebSite",
      "@id": `${SITE_URL}/#website`,
      url: SITE_URL,
      name: "Mile A Day",
      inLanguage: "en-US",
      publisher: { "@id": `${SITE_URL}/#organization` },
    },
    {
      "@type": "MobileApplication",
      "@id": `${SITE_URL}/#app`,
      name: "Mile A Day",
      operatingSystem: "iOS, watchOS",
      applicationCategory: "HealthApplication",
      description:
        "Walk or run a mile every day, build streaks, earn medals, and compete with friends. Free on iPhone and Apple Watch.",
      url: SITE_URL,
      image: `${SITE_URL}/images/mad-circle-icon.png`,
      screenshot: `${SITE_URL}/images/hero/dashboard-2026-10.webp`,
      inLanguage: "en-US",
      isAccessibleForFree: true,
      featureList: [
        "Daily mile streak tracking",
        "Apple Health and Apple Watch sync",
        "In-app GPS walk and run tracking",
        "Friends feed, hypes and nudges",
        "Competitions and head-to-head challenges",
        "Medals and milestones",
        "Walk together with friends in real time",
        "Route Art and route Flyovers",
        "Flamey, a mascot you dress with the medals you earn",
        "Weekly recap",
      ],
      downloadUrl: APP_STORE_URL,
      installUrl: APP_STORE_URL,
      softwareVersion: CURRENT_RELEASE.version,
      publisher: { "@id": `${SITE_URL}/#organization` },
      offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
    },
  ],
};

// Escape "<" so no string in the data can close the script tag early.
const structuredDataJson = JSON.stringify(structuredData).replace(/</g, "\\u003c");

// The page is the App Store listing, told at web size: the header panel,
// then one colour panel per screenshot (copy and phones from
// marketing/app-store/<version>/), then plain proof (real numbers, what just
// shipped, who made it), help, and one last ask.
export default function Home() {
  return (
    <main className="relative min-h-screen overflow-x-hidden bg-[#0e0809]">
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: structuredDataJson }}
      />
      <Navbar />
      <HeroSection />
      <FeaturePanels />
      <NumbersSection />
      <WhatsNewSection />
      <StorySection />
      <SupportSection />
      <DeskTeaserSection />
      <CtaSection />
      <Footer />
    </main>
  );
}
