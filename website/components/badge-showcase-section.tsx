"use client"

import { useState } from "react"
import { LayoutGrid, Flame, Zap, Footprints, Route, Lock } from "lucide-react"

type Rarity = "legendary" | "rare" | "common"
type Category = "streaks" | "miles" | "speed" | "distance"

// Rarity colors mirror the app exactly: medal gradients from
// PremiumBadgeCard.medalGradientColors, accents from BadgeRarity.color
// (legendary = orange, rare = purple, common = blue).
const rarityStyles: Record<Rarity, { from: string; to: string; accent: string; label: string }> = {
  legendary: { from: "#FFD966", to: "#D98C26", accent: "#FF9F0A", label: "LEGENDARY" },
  rare: { from: "#B380E6", to: "#804DBF", accent: "#BF5AF2", label: "RARE" },
  common: { from: "#73A6F2", to: "#4D80CC", accent: "#0A84FF", label: "COMMON" },
}

const TOTAL_MEDALS = 63

// Real medals from the app's catalog — names, requirements, and rarities
// match backend/scripts/badges-seed.sql. Representative subset of the 63.
const medals: {
  name: string
  req: string
  rarity: Rarity
  category: Category
  unlocked: boolean
  earned?: string
}[] = [
  // Streaks
  { name: "Getting Started", req: "3 day streak", rarity: "common", category: "streaks", unlocked: true, earned: "May 15, 2025" },
  { name: "Week Warrior", req: "7 day streak", rarity: "common", category: "streaks", unlocked: true, earned: "May 19, 2025" },
  { name: "Monthly Master", req: "30 day streak", rarity: "common", category: "streaks", unlocked: true, earned: "Jun 11, 2025" },
  { name: "Century Club", req: "100 day streak", rarity: "rare", category: "streaks", unlocked: true, earned: "Aug 20, 2025" },
  { name: "Year Warrior", req: "365 day streak", rarity: "legendary", category: "streaks", unlocked: true, earned: "May 13, 2026" },
  { name: "Immortal", req: "1000 day streak", rarity: "legendary", category: "streaks", unlocked: false },
  // Speed
  { name: "Getting Faster", req: "Sub-12 minute mile", rarity: "common", category: "speed", unlocked: true, earned: "May 22, 2025" },
  { name: "Double Digits", req: "Sub-10 minute mile", rarity: "common", category: "speed", unlocked: true, earned: "Jul 3, 2025" },
  { name: "Fast Runner", req: "Sub-8 minute mile", rarity: "rare", category: "speed", unlocked: true, earned: "Oct 9, 2025" },
  { name: "Speed Demon", req: "Sub-6 minute mile", rarity: "legendary", category: "speed", unlocked: false },
  { name: "Elite Speed", req: "Sub-5 minute mile", rarity: "legendary", category: "speed", unlocked: false },
  // Miles
  { name: "50 Mile Club", req: "Ran 50 total miles", rarity: "common", category: "miles", unlocked: true, earned: "Jun 28, 2025" },
  { name: "Century Runner", req: "Ran 100 total miles", rarity: "common", category: "miles", unlocked: true, earned: "Aug 16, 2025" },
  { name: "500 Mile Club", req: "Ran 500 total miles", rarity: "rare", category: "miles", unlocked: false },
  { name: "1000 Mile Club", req: "Ran 1000 total miles", rarity: "legendary", category: "miles", unlocked: false },
  // Daily distance
  { name: "5K Runner", req: "Ran a 5K in one day", rarity: "common", category: "distance", unlocked: true, earned: "Jun 2, 2025" },
  { name: "Half Marathon", req: "13.1+ miles in one day", rarity: "rare", category: "distance", unlocked: false },
  { name: "Marathon Runner", req: "26.2+ miles in one day", rarity: "legendary", category: "distance", unlocked: false },
]

// Filter chips match the app's Medals screen.
const filters: { id: Category | "all"; label: string; icon: typeof Flame }[] = [
  { id: "all", label: "All", icon: LayoutGrid },
  { id: "streaks", label: "Streaks", icon: Flame },
  { id: "miles", label: "Miles", icon: Footprints },
  { id: "speed", label: "Speed", icon: Zap },
  { id: "distance", label: "Distance", icon: Route },
]

const categoryIcon: Record<Category, typeof Flame> = {
  streaks: Flame,
  miles: Footprints,
  speed: Zap,
  distance: Route,
}

const earnedCount = medals.filter((m) => m.unlocked).length

export function BadgeShowcaseSection() {
  const [filter, setFilter] = useState<Category | "all">("all")

  const visible = filter === "all" ? medals : medals.filter((m) => m.category === filter)

  return (
    <section className="section-lazy relative px-6 py-24 overflow-hidden">
      <div className="relative mx-auto max-w-6xl">
        <div className="mx-auto mb-16 max-w-2xl text-center">
          <span className="reveal mb-4 inline-block text-sm font-semibold uppercase tracking-widest text-[#c72554]">
            Gamification
          </span>
          <h2 className="reveal reveal-delay-1 font-heading text-[clamp(40px,6vw,72px)] leading-none tracking-[-1px] text-[#f5f5f5]">
            COLLECT EVERY MEDAL
          </h2>
          <p className="reveal reveal-delay-2 mt-4 text-base leading-relaxed text-[#a0a0a0]">
            63 medals to earn. From your first mile to your thousandth day, there&apos;s always something to chase.
          </p>
        </div>

        {/* Stats header card — matches app's Medals screen header */}
        <div className="reveal reveal-delay-2 mx-auto mb-10 max-w-xl">
          <div className="glass-card rounded-[20px] p-6">
            <div className="flex items-center justify-between">
              <div className="text-center flex-1">
                <div className="font-heading text-[36px] leading-none text-[#f5f5f5]">{earnedCount}</div>
                <div className="mt-1 text-[11px] font-semibold uppercase tracking-[1.2px] text-[#a0a0a0]">Earned</div>
              </div>

              {/* Progress ring — madRed gradient like the app */}
              <div className="relative mx-6 h-20 w-20 shrink-0">
                <svg viewBox="0 0 80 80" className="h-20 w-20 -rotate-90">
                  <circle cx="40" cy="40" r="34" fill="none" stroke="#222" strokeWidth="6" />
                  <circle
                    cx="40" cy="40" r="34" fill="none" strokeWidth="6" strokeLinecap="round"
                    stroke="url(#badgeProgress)"
                    strokeDasharray={`${2 * Math.PI * 34}`}
                    strokeDashoffset={`${2 * Math.PI * 34 * (1 - earnedCount / TOTAL_MEDALS)}`}
                  />
                  <defs>
                    <linearGradient id="badgeProgress" x1="0%" y1="0%" x2="100%" y2="0%">
                      <stop offset="0%" stopColor="#D94059" />
                      <stop offset="100%" stopColor="#FF6B6B" />
                    </linearGradient>
                  </defs>
                </svg>
                <span className="absolute inset-0 flex items-center justify-center font-heading text-[18px] text-[#f5f5f5]">
                  {Math.round((earnedCount / TOTAL_MEDALS) * 100)}%
                </span>
              </div>

              <div className="text-center flex-1">
                <div className="font-heading text-[36px] leading-none text-[#f5f5f5]/50">{TOTAL_MEDALS}</div>
                <div className="mt-1 text-[11px] font-semibold uppercase tracking-[1.2px] text-[#a0a0a0]">Total</div>
              </div>
            </div>

            {/* Rarity breakdown pills — app style: tinted capsule + dot + count */}
            <div className="mt-4 flex justify-center gap-2">
              {(["legendary", "rare", "common"] as Rarity[]).map((rarity) => {
                const count = medals.filter((m) => m.rarity === rarity && m.unlocked).length
                const style = rarityStyles[rarity]
                return (
                  <div
                    key={rarity}
                    className="flex items-center gap-1.5 rounded-full px-3 py-1"
                    style={{ background: `${style.accent}26` }}
                  >
                    <span className="h-2 w-2 rounded-full" style={{ background: style.accent }} />
                    <span className="text-[10px] font-bold tracking-wider" style={{ color: style.accent }}>
                      {count} {style.label}
                    </span>
                  </div>
                )
              })}
            </div>
          </div>
        </div>

        {/* Filter chips — same set as the app's Medals screen */}
        <div className="reveal reveal-delay-3 mb-8 flex flex-wrap justify-center gap-2">
          {filters.map((f) => {
            const selected = filter === f.id
            return (
              <button
                key={f.id}
                onClick={() => setFilter(f.id)}
                className="flex items-center gap-1.5 rounded-full px-4 py-2 text-[12px] font-semibold transition-colors duration-200"
                style={
                  selected
                    ? { background: "#D94059", color: "#fff" }
                    : { background: "rgba(255,255,255,0.06)", color: "rgba(255,255,255,0.45)" }
                }
              >
                <f.icon className="h-3.5 w-3.5" />
                {f.label}
              </button>
            )
          })}
        </div>

        {/* Medal cards — replicas of the app's PremiumBadgeCard */}
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
          {visible.map((medal) => {
            const style = rarityStyles[medal.rarity]
            const Icon = categoryIcon[medal.category]
            return (
              <div
                key={medal.name}
                className="medal-card flex flex-col items-center rounded-[20px] px-3 pb-5 pt-4 text-center"
                style={{
                  "--accent": style.accent,
                  background: medal.unlocked
                    ? `linear-gradient(135deg, ${style.accent}14, rgba(255,255,255,0.05))`
                    : "linear-gradient(135deg, rgba(255,255,255,0.03), rgba(255,255,255,0.02))",
                  border: `1px solid ${medal.unlocked ? `${style.accent}40` : "rgba(255,255,255,0.06)"}`,
                } as React.CSSProperties}
              >
                {/* Medal — radial glow, gradient base, stroke, inner ring */}
                <div className="relative flex h-[96px] w-[96px] items-center justify-center">
                  {medal.unlocked && (
                    <div
                      className="absolute inset-0 rounded-full"
                      style={{ background: `radial-gradient(circle, ${style.accent}5C 18%, transparent 65%)` }}
                    />
                  )}
                  <div
                    className="relative flex h-[68px] w-[68px] items-center justify-center rounded-full"
                    style={{
                      background: medal.unlocked
                        ? `linear-gradient(135deg, ${style.from}, ${style.to})`
                        : "linear-gradient(135deg, #404040, #262626)",
                      border: medal.unlocked
                        ? "2px solid rgba(255,255,255,0.5)"
                        : "2px solid rgba(255,255,255,0.08)",
                      boxShadow: medal.unlocked ? `0 6px 12px ${style.accent}66` : "none",
                    }}
                  >
                    {medal.unlocked && (
                      <div className="pointer-events-none absolute inset-[6px] rounded-full border border-white/20" />
                    )}
                    <Icon
                      className={medal.unlocked ? "h-7 w-7 text-white drop-shadow-md" : "h-7 w-7 text-white/15"}
                    />
                    {!medal.unlocked && (
                      <Lock className="absolute right-0.5 top-0.5 h-3.5 w-3.5 text-white/40" />
                    )}
                  </div>
                </div>

                {/* Name — two lines reserved so every card matches height */}
                <span
                  className={`mt-2 flex h-9 items-start justify-center text-[13px] font-bold leading-tight ${
                    medal.unlocked ? "text-white" : "text-white/40"
                  }`}
                >
                  {medal.name}
                </span>

                {/* Rarity pill */}
                <span
                  className="rounded-full px-2.5 py-1 text-[9px] font-black tracking-[1.2px]"
                  style={
                    medal.unlocked
                      ? { background: `${style.accent}26`, color: style.accent }
                      : { background: "rgba(255,255,255,0.05)", color: "rgba(255,255,255,0.25)" }
                  }
                >
                  {style.label}
                </span>

                {/* Earned date or requirement */}
                <span className={`mt-2 text-[10px] font-medium ${medal.unlocked ? "text-white/50" : "text-white/30"}`}>
                  {medal.unlocked ? medal.earned : medal.req}
                </span>
              </div>
            )
          })}
        </div>

        <p className="reveal mt-10 text-center text-sm text-[#666]">
          …and {TOTAL_MEDALS - medals.length} more to discover, including daily challenge and special medals.
        </p>
      </div>
    </section>
  )
}
