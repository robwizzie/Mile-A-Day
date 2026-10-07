import type { Metadata } from "next";
import { Navbar } from "@/components/navbar";
import { HeroSection } from "@/components/hero-section";
import { MarqueeSection } from "@/components/marquee-section";
import { LiveStatsBand } from "@/components/live-stats-band";
import { FeedSection } from "@/components/feed-section";
import { WhatsNewSection } from "@/components/whats-new-section";
import { FeaturesSection } from "@/components/features-section";
import { BadgeShowcaseSection } from "@/components/badge-showcase-section";
import { HabitSection } from "@/components/habit-section";
import { CompetitionsSection } from "@/components/competitions-section";
import { SocialSection } from "@/components/social-section";
import { HowItWorksSection } from "@/components/how-it-works-section";
import { StorySection } from "@/components/story-section";
import { CtaSection } from "@/components/cta-section";
import { Footer } from "@/components/footer";
import { ScrollReveal } from "@/components/scroll-reveal";


const SITE_URL = "https://mileaday.run";
const APP_STORE_URL = "https://apps.apple.com/us/app/mile-a-day/id6746970905";

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
      screenshot: `${SITE_URL}/images/app-dashboard.png`,
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
      ],
      downloadUrl: APP_STORE_URL,
      installUrl: APP_STORE_URL,
      publisher: { "@id": `${SITE_URL}/#organization` },
      offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
    },
  ],
};

// Escape "<" so no string in the data can close the script tag early.
const structuredDataJson = JSON.stringify(structuredData).replace(/</g, "\\u003c");

// Section order tells the story top to bottom: hook (hero) → live proof the
// community is real (stats band) → what the app does (features) → the new
// social experience (feed, then friends/nudges) → the competitive layer
// (competitions, medals) → what just shipped (2.0) → why one mile works
// (habit) → how to start → who built it → download.
export default function Home() {
  return (
    <main className="relative min-h-screen overflow-x-hidden bg-[#0a0a0a]">
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: structuredDataJson }}
      />
      <ScrollReveal />
      <Navbar />
      <HeroSection />
      <MarqueeSection />
      <LiveStatsBand />
      <FeaturesSection />
      <FeedSection />
      <SocialSection />
      <CompetitionsSection />
      <BadgeShowcaseSection />
      <WhatsNewSection />
      <HabitSection />
      <HowItWorksSection />
      <StorySection />
      <CtaSection />
      <Footer />
    </main>
  );
}
