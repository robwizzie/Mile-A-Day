import Image from "next/image"

export function HeroSection() {
  return (
    <section className="relative min-h-screen overflow-hidden px-6 pt-32 pb-20">
      {/* Background orbs */}
      <div className="pointer-events-none absolute inset-0 overflow-hidden">
        <div className="animate-pulse-glow absolute -top-40 left-1/2 h-[600px] w-[600px] -translate-x-1/2 rounded-full bg-[#c72554] opacity-[0.07] blur-[150px]" />
        <div className="animate-pulse-glow absolute -bottom-20 -left-40 h-[400px] w-[400px] rounded-full bg-[#8b1538] opacity-[0.05] blur-[120px]" style={{ animationDelay: "2s" }} />
      </div>

      <div className="relative mx-auto flex max-w-6xl flex-col items-center gap-16 lg:flex-row lg:items-center lg:gap-20">
        {/* Left: copy */}
        <div className="flex flex-1 flex-col items-center text-center lg:items-start lg:text-left">
          <div className="reveal glass-card-highlight mb-6 inline-flex items-center gap-2 rounded-full px-4 py-2">
            <span className="relative flex h-2 w-2">
              <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-[#c72554] opacity-75" />
              <span className="relative inline-flex h-2 w-2 rounded-full bg-[#c72554]" />
            </span>
            <span className="text-xs font-medium tracking-wide text-[#c72554]">
              Available on iOS & Apple Watch
            </span>
          </div>

          <h1 className="reveal reveal-delay-1 font-heading text-[clamp(60px,11vw,150px)] leading-[0.9] tracking-[-2px]">
            <span className="text-[#f5f5f5]">ONE MILE.</span>
            <br />
            <span className="bg-gradient-to-r from-[#c72554] to-[#ff4d7d] bg-clip-text text-transparent">
              EVERY DAY.
            </span>
          </h1>

          <p className="reveal reveal-delay-2 mt-6 max-w-lg text-lg leading-relaxed text-[#a0a0a0]">
            The simplest fitness challenge that will change your life. No complicated programs. No expensive gear. Just lace up, tap Start Mile, and go. Walk it or run it — just get it done.
          </p>

          <div className="reveal reveal-delay-3 mt-8 flex flex-col items-center gap-4 sm:flex-row">
            <a
              href="https://apps.apple.com/us/app/mile-a-day/id6504697812"
              target="_blank"
              rel="noopener noreferrer"
              className="glass-button inline-flex items-center gap-3 rounded-2xl px-9 py-4 text-base font-semibold text-[#ffffff]"
            >
              <svg className="h-5 w-5" viewBox="0 0 24 24" fill="currentColor">
                <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
              </svg>
              Download for iPhone
            </a>
            <a
              href="#story"
              className="glass-card inline-flex items-center gap-2 rounded-2xl px-9 py-4 text-base font-semibold text-[#f5f5f5] transition-all hover:border-[#c72554]/20"
            >
              Our Story
            </a>
          </div>

          {/* Social proof stats */}
          <div className="reveal reveal-delay-4 mt-10 flex gap-8 sm:gap-12">
            <div className="text-center lg:text-left">
              <div className="font-heading text-[28px] text-[#f5f5f5]">365+</div>
              <div className="text-xs text-[#a0a0a0]">Day Streaks</div>
            </div>
            <div className="text-center lg:text-left">
              <div className="font-heading text-[28px] text-[#c72554]">$0</div>
              <div className="text-xs text-[#a0a0a0]">Always Free</div>
            </div>
            <div className="text-center lg:text-left">
              <div className="font-heading text-[28px] text-[#f5f5f5]">1 MILE</div>
              <div className="text-xs text-[#a0a0a0]">That&apos;s It</div>
            </div>
          </div>
        </div>

        {/* Right: phone mockup */}
        <div className="reveal-scale reveal-delay-2 relative flex flex-1 items-center justify-center">
          <div className="animate-float phone-mockup relative overflow-hidden p-3" style={{ width: 290 }}>
            <Image
              src="/images/app-dashboard.png"
              alt="Mile A Day app dashboard showing a 288 day streak"
              width={580}
              height={1200}
              className="w-full rounded-[32px]"
              priority
            />
          </div>
          {/* Glow behind phone */}
          <div className="animate-pulse-glow absolute -z-10 h-[400px] w-[400px] rounded-full bg-[#c72554] opacity-[0.08] blur-[100px]" />
        </div>
      </div>
    </section>
  )
}
