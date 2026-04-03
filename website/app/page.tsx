import { Navbar } from "@/components/navbar"
import { HeroSection } from "@/components/hero-section"
import { MarqueeSection } from "@/components/marquee-section"
import { FeaturesSection } from "@/components/features-section"
import { HabitSection } from "@/components/habit-section"
import { CompetitionsSection } from "@/components/competitions-section"
import { HowItWorksSection } from "@/components/how-it-works-section"
import { StorySection } from "@/components/story-section"
import { CtaSection } from "@/components/cta-section"
import { Footer } from "@/components/footer"
import { ScrollReveal } from "@/components/scroll-reveal"

export default function Home() {
  return (
    <main className="relative min-h-screen overflow-x-hidden bg-[#0a0a0a]">
      <ScrollReveal />
      <Navbar />
      <HeroSection />
      <MarqueeSection />
      <FeaturesSection />
      <HabitSection />
      <CompetitionsSection />
      <HowItWorksSection />
      <StorySection />
      <CtaSection />
      <Footer />
    </main>
  )
}
