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

export default function Home() {
  return (
    <main className="relative min-h-screen overflow-x-hidden bg-[#0a0a0a]">
      <ScrollReveal />
      <Navbar />
      <HeroSection />
      <MarqueeSection />
      <LiveStatsBand />
      <FeedSection />
      <WhatsNewSection />
      <FeaturesSection />
      <BadgeShowcaseSection />
      <HabitSection />
      <CompetitionsSection />
      <SocialSection />
      <HowItWorksSection />
      <StorySection />
      <CtaSection />
      <Footer />
    </main>
  );
}
