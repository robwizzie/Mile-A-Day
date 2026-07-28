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

// Structured data (schema.org) so Google can render a rich result and
// understand that mileaday.run is the home of a free iOS/Apple Watch app.
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
      description:
        "Mile A Day is the free iOS & Apple Watch app that turns one mile a day into an unbreakable habit.",
      publisher: { "@id": `${SITE_URL}/#organization` },
    },
    {
      "@type": "MobileApplication",
      "@id": `${SITE_URL}/#app`,
      name: "Mile A Day",
      operatingSystem: "iOS, watchOS",
      applicationCategory: "HealthApplication",
      description:
        "Run or walk a mile every day, build streaks, earn badges, and compete with friends. Free on iPhone and Apple Watch.",
      url: SITE_URL,
      downloadUrl: APP_STORE_URL,
      installUrl: APP_STORE_URL,
      publisher: { "@id": `${SITE_URL}/#organization` },
      offers: {
        "@type": "Offer",
        price: "0",
        priceCurrency: "USD",
      },
    },
  ],
};

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
        dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData) }}
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
