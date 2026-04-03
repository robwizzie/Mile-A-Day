"use client"

import Image from "next/image"
import { useEffect, useState } from "react"

const API_URL = process.env.NEXT_PUBLIC_API_URL || "https://mad.mindgoblin.tech"

function getStreakDays(): number {
  const start = new Date(2025, 4, 13) // May 13, 2025
  const now = new Date()
  const diff = now.getTime() - start.getTime()
  return Math.floor(diff / (1000 * 60 * 60 * 24))
}

async function getProfileImageUrl(username: string): Promise<string | null> {
  try {
    const res = await fetch(`${API_URL}/public/profile-image/${username}`)
    if (!res.ok) return null
    const data = await res.json()
    return data.profile_image_url ? `${API_URL}${data.profile_image_url}` : null
  } catch {
    return null
  }
}

export function StorySection() {
  const streakDays = getStreakDays()
  const [robImage, setRobImage] = useState<string | null>(null)
  const [daveImage, setDaveImage] = useState<string | null>(null)

  useEffect(() => {
    getProfileImageUrl("rob").then(setRobImage)
    getProfileImageUrl("dave").then(setDaveImage)
  }, [])

  return (
    <section id="story" className="relative px-6 py-24">
      <div className="pointer-events-none absolute inset-0">
        <div className="absolute top-20 left-0 h-[350px] w-[350px] rounded-full bg-[#c72554] opacity-[0.04] blur-[120px]" />
      </div>
      <div className="relative mx-auto grid max-w-6xl gap-12 lg:grid-cols-2 lg:gap-20 items-center">
        {/* Left column: narrative */}
        <div>
          <span className="reveal-left mb-4 inline-block text-sm font-semibold uppercase tracking-widest text-[#c72554]">
            Our Story
          </span>
          <h2 className="reveal-left reveal-delay-1 font-heading text-[clamp(40px,6vw,72px)] leading-none tracking-[-1px] text-[#f5f5f5] mb-6">
            IT STARTED WITH<br />A STUPID BET
          </h2>
          <p className="reveal-left reveal-delay-2 text-[17px] leading-[1.8] text-[#a0a0a0] mb-5">
            <span className="font-semibold text-[#f5f5f5]">Rob Wiscount</span> and{" "}
            <span className="font-semibold text-[#f5f5f5]">David Simmerman</span> made a simple
            challenge: walk or run one mile every single day. Whoever broke first had to buy the
            other a Call of Duty skin. That was it. No grand vision. No business plan. Just two
            competitive guys who refused to lose.
          </p>

          {/* Blockquote */}
          <div className="reveal-left reveal-delay-3 rounded-r-2xl border-l-4 border-l-[#c72554] bg-[#1a1a1a]/50 p-6 my-7">
            <p className="text-[17px] font-medium italic leading-[1.7] text-[#f5f5f5]">
              &ldquo;We&apos;re closing in on a full year without breaking. What started as a dumb
              CoD skin bet became the best habit either of us ever built — so we turned it into an
              app.&rdquo;
            </p>
          </div>

          <p className="reveal-left reveal-delay-4 text-[17px] leading-[1.8] text-[#a0a0a0]">
            Mile A Day isn&apos;t backed by venture capital. We&apos;re not in this for the money. We
            built this because this challenge genuinely changed our lives, and we think it can change
            yours too.
          </p>
        </div>

        {/* Right column: founders card */}
        <div className="reveal-right reveal-delay-2 glass-card rounded-3xl p-7 md:p-10 relative overflow-hidden">
          {/* Red gradient top border */}
          <div className="absolute top-0 left-0 right-0 h-[3px] bg-gradient-to-r from-[#8b1538] via-[#c72554] to-[#ff4d7d]" />

          {/* Founder avatars */}
          <div className="flex flex-col gap-5 sm:flex-row sm:gap-6 mb-6">
            <div className="flex items-center gap-3">
              <div className="relative h-12 w-12 shrink-0 overflow-hidden rounded-full border-2 border-[#c72554]/30 bg-gradient-to-br from-[#5a0d24] to-[#8b1538]">
                {robImage && (
                  <Image
                    src={robImage}
                    alt="Rob Wiscount"
                    fill
                    className="object-cover"
                    sizes="48px"
                  />
                )}
              </div>
              <div>
                <div className="text-[15px] font-semibold text-[#f5f5f5]">Rob Wiscount</div>
                <div className="text-xs text-[#c72554]">Co-Founder & Developer</div>
              </div>
            </div>
            <div className="flex items-center gap-3">
              <div className="relative h-12 w-12 shrink-0 overflow-hidden rounded-full border-2 border-[#c72554]/30 bg-gradient-to-br from-[#5a0d24] to-[#8b1538]">
                {daveImage && (
                  <Image
                    src={daveImage}
                    alt="David Simmerman"
                    fill
                    className="object-cover"
                    sizes="48px"
                  />
                )}
              </div>
              <div>
                <div className="text-[15px] font-semibold text-[#f5f5f5]">David Simmerman</div>
                <div className="text-xs text-[#c72554]">Co-Founder & Developer</div>
              </div>
            </div>
          </div>

          <h3 className="font-heading text-[26px] tracking-[1px] text-[#f5f5f5] mb-4">
            THE COD SKIN BET
          </h3>
          <p className="text-[15px] leading-[1.8] text-[#a0a0a0] mb-3">
            It was supposed to be a quick thing. &ldquo;Let&apos;s see who breaks first — loser buys
            a Call of Duty skin.&rdquo; Days turned into weeks. Weeks turned into months. Neither of
            us would quit.
          </p>
          <p className="text-[15px] leading-[1.8] text-[#a0a0a0] mb-3">
            We realized we&apos;d accidentally built the most consistent fitness habit of our lives.
            So we thought: what if everyone could feel this? The accountability. The streak you
            refuse to break. The friendly competition that makes you lace up on days you really
            don&apos;t want to.
          </p>
          <p className="text-[15px] leading-[1.8] text-[#a0a0a0] mb-5">
            That&apos;s how Mile A Day was born.
          </p>

          {/* Streak badge */}
          <div className="font-heading glass-card-highlight inline-flex items-center gap-2 rounded-xl px-4 py-2 text-[18px] text-[#c72554]">
            <span className="text-[20px]">🔥</span> Founders&apos; Streak: {streakDays} Days & Counting
          </div>
        </div>
      </div>
    </section>
  )
}
