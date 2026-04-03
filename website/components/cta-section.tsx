"use client"

import { useState } from "react"

export function CtaSection() {
  const [email, setEmail] = useState("")
  const [submitted, setSubmitted] = useState(false)

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (email) {
      setSubmitted(true)
      setEmail("")
    }
  }

  return (
    <section className="relative px-6 py-24">
      <div className="pointer-events-none absolute inset-0">
        <div className="absolute bottom-0 left-1/2 h-[600px] w-[600px] -translate-x-1/2 rounded-full bg-[#c72554] opacity-[0.08] blur-[150px]" />
      </div>
      <div className="relative mx-auto max-w-3xl text-center">
        <span className="reveal mb-4 inline-block text-sm font-semibold uppercase tracking-widest text-[#c72554]">
          Join the Movement
        </span>
        <h2 className="reveal-scale reveal-delay-1 font-heading text-[clamp(48px,8vw,96px)] leading-[0.95] tracking-[-1px] text-[#f5f5f5]">
          YOUR STREAK<br />STARTS <span className="text-[#c72554]">TODAY</span>
        </h2>
        <p className="reveal reveal-delay-2 mt-6 text-lg leading-relaxed text-[#a0a0a0]">
          One mile. Every day. That&apos;s all it takes to build a habit that lasts a lifetime.
          Download Mile A Day and never look back.
        </p>
        <div className="reveal reveal-delay-3 mt-10 flex flex-col items-center gap-4 sm:flex-row sm:justify-center">
          <a
            href="https://apps.apple.com/us/app/mile-a-day/id6504697812"
            target="_blank"
            rel="noopener noreferrer"
            className="glass-button inline-flex items-center gap-3 rounded-2xl px-7 py-4 text-[#ffffff] transition-all hover:-translate-y-1"
          >
            <svg className="h-7 w-7" viewBox="0 0 24 24" fill="currentColor">
              <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
            </svg>
            <div className="text-left">
              <div className="text-[10px] text-[#a0a0a0] tracking-wide">Download on the</div>
              <div className="text-base font-semibold">App Store</div>
            </div>
          </a>
        </div>

        {/* Android waitlist */}
        <div className="reveal reveal-delay-4 mt-10 mx-auto max-w-md">
          <p className="mb-3 text-sm text-[#a0a0a0]/80">
            On Android? Get notified when we launch.
          </p>
          {submitted ? (
            <div className="glass-card-highlight rounded-xl px-6 py-3 text-sm font-medium text-[#c72554]">
              You&apos;re on the list! We&apos;ll let you know when Android is ready.
            </div>
          ) : (
            <form onSubmit={handleSubmit} className="flex gap-2">
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="your@email.com"
                required
                className="flex-1 rounded-xl border border-[#333333] bg-[#1a1a1a]/60 px-4 py-3 text-sm text-[#f5f5f5] placeholder-[#606060] outline-none transition-colors focus:border-[#c72554]/50 backdrop-blur-sm"
              />
              <button
                type="submit"
                className="glass-button rounded-xl px-5 py-3 text-sm font-semibold text-[#ffffff] whitespace-nowrap"
              >
                Notify Me
              </button>
            </form>
          )}
        </div>
      </div>
    </section>
  )
}
