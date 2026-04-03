"use client"

import dynamic from "next/dynamic"
import { Navbar } from "@/components/navbar"
import { HeroSection } from "@/components/hero-section"
import { MarqueeSection } from "@/components/marquee-section"
import { FeaturesSection } from "@/components/features-section"
import { HabitSection } from "@/components/habit-section"
import { CompetitionsSection } from "@/components/competitions-section"
import { StorySection } from "@/components/story-section"
import { Footer } from "@/components/footer"

const ScrollReveal = dynamic(
  () => import("@/components/scroll-reveal").then((m) => m.ScrollReveal),
  { ssr: false }
)

const HowItWorksSection = dynamic(
  () => import("@/components/how-it-works-section").then((m) => m.HowItWorksSection),
  { ssr: false }
)

const CtaSection = dynamic(
  () => import("@/components/cta-section").then((m) => m.CtaSection),
  { ssr: false }
)

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
