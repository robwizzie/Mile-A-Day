"use client"

import { Flame, CircleArrowUp, Target, Zap, Flag, Trophy, Timer, Footprints, Crown } from "lucide-react"
import { ProfileAvatar } from "@/components/profile-avatar"
import { usePublicUser } from "@/lib/public-user"

// Competition types — names, icons, gradients, and descriptions mirror the
// app's CompetitionType enum exactly (Models/Competition.swift). The cards
// mirror the app's type picker (CompetitionTypeCard): gradient-tinted icon
// in a soft circle, type name, then the description.
const competitions = [
  {
    icon: Flame,
    name: "Streaks",
    gradient: ["#FF6B6B", "#FF8E53"],
    description: "Hold a running streak as long as you can. First to break the streak loses.",
  },
  {
    icon: CircleArrowUp,
    name: "Apex",
    gradient: ["#4ECDC4", "#44A08D"],
    description: "Over a period of time (ex: 1 week) whoever has the most distance during that time wins.",
  },
  {
    icon: Target,
    name: "Targets",
    gradient: ["#F7971E", "#FFD200"],
    description: "Anyone who completes the goal in a given day gets a point. Whoever has the most points at the end of the period wins.",
  },
  {
    icon: Zap,
    name: "Clash",
    gradient: ["#C33764", "#1D2671"],
    description: "Whoever goes the furthest each day wins a point. First to reach the target score or most points at the end wins.",
  },
  {
    icon: Flag,
    name: "Race",
    gradient: ["#667EEA", "#764BA2"],
    description: "There is a distance goal set and whoever gets there first wins.",
  },
]

// App medal colors (LeaderboardSection.swift): gold / silver / bronze.
const MEDAL_GOLD = "#FFD133"
const MEDAL_SILVER = "#C7C7C7"
const MEDAL_BRONZE = "#D18C4D"
const MAD_RED = "#D94059"

const medalColor = (rank: number) =>
  rank === 0 ? MEDAL_GOLD : rank === 1 ? MEDAL_SILVER : MEDAL_BRONZE

// The app's actual leaderboard metrics (LeaderboardService.swift) and periods.
const leaderboardMetrics = [
  { label: "Miles · Ran", icon: Footprints },
  { label: "Miles · Total", icon: Footprints },
  { label: "Pace", icon: Timer },
  { label: "Streak", icon: Flame },
]
const leaderboardPeriods = ["Today", "Week", "Month", "Year", "All-Time"]

// Podium + rows feature real Mile A Day accounts — profile photos and streaks
// are pulled LIVE from the public API (see usePublicUser). The miles values are
// illustrative for the leaderboard demo; per-day miles aren't exposed publicly.
// Podium order matches the app: 2nd · 1st · 3rd, 1st elevated with a crown.
const podium = [
  { name: "David", username: "dave", initials: "DS", value: "13.8 mi", rank: 1, size: 56 },
  { name: "Rob", username: "rob", initials: "RW", value: "14.2 mi", rank: 0, size: 68, isYou: true },
  { name: "Megs", username: "MegsMiles", initials: "MM", value: "11.4 mi", rank: 2, size: 52 },
]
const leaderboardRows = [
  { rank: 4, name: "Aaron", username: "Aaron", initials: "AA", value: "8.9 mi" },
  { rank: 5, name: "MAD", username: "mad", initials: "M", value: "7.4 mi" },
]

/** A rank-4+ leaderboard row with the user's real photo and live streak. */
function LeaderRow({ row }: { row: (typeof leaderboardRows)[number] }) {
  const user = usePublicUser(row.username)
  return (
    <div className="flex items-center gap-3 rounded-2xl bg-white/[0.04] border border-white/[0.06] px-4 py-2.5">
      <span className="w-5 text-sm font-semibold text-white/50">{row.rank}</span>
      <ProfileAvatar username={row.username} initials={row.initials} size={32} className="border border-white/10" />
      <span className="text-sm font-medium text-[#f5f5f5]">{row.name}</span>
      {user && (
        <span className="flex items-center gap-0.5 text-[11px] font-bold text-[#FF9900]">
          <Flame className="h-3 w-3" />
          {user.currentStreak}
        </span>
      )}
      <span className="ml-auto text-sm font-semibold text-white/70">{row.value}</span>
    </div>
  )
}

export function CompetitionsSection() {
  return (
    <section
      id="competitions"
      className="section-lazy relative px-6 py-24"
      style={{ background: "radial-gradient(ellipse 500px 500px at 100% 50%, rgba(139,21,56,0.04) 0%, transparent 70%), #080808" }}
    >
      <div className="relative mx-auto max-w-6xl">
        <div className="mx-auto mb-16 max-w-2xl text-center">
          <span className="reveal mb-4 inline-block text-sm font-semibold uppercase tracking-widest text-[#c72554]">
            Competitions
          </span>
          <h2 className="reveal reveal-delay-1 font-heading text-[clamp(40px,6vw,72px)] leading-none tracking-[-1px] text-[#f5f5f5]">
            GO THE EXTRA MILE
          </h2>
          <p className="reveal reveal-delay-2 mt-4 text-base leading-relaxed text-[#a0a0a0]">
            Five competition modes that turn your daily mile into something you can&apos;t afford to skip.
          </p>
        </div>

        {/* All five modes at once — app's competition type cards */}
        <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-6">
          {competitions.map((comp, i) => (
            <div
              key={comp.name}
              className={`type-card reveal-scale reveal-delay-${Math.min(i + 1, 5)} rounded-[20px] p-6 backdrop-blur-xl ${
                i < 3 ? "lg:col-span-2" : "lg:col-span-3"
              }`}
              style={{
                background: "rgba(255,255,255,0.05)",
                "--accent": comp.gradient[0],
              } as React.CSSProperties}
            >
              <div
                className="flex h-[50px] w-[50px] items-center justify-center rounded-full"
                style={{ background: `${comp.gradient[0]}26` }}
              >
                <comp.icon className="h-6 w-6" style={{ color: comp.gradient[0] }} />
              </div>

              <h3 className="font-heading mt-4 text-[24px] tracking-[1px] text-white">{comp.name}</h3>

              <p className="mt-2 text-[15px] leading-relaxed text-white/70">{comp.description}</p>

              {/* Gradient accent bar — echoes the app's per-type gradient */}
              <div
                className="mt-5 h-1 w-12 rounded-full"
                style={{ background: `linear-gradient(90deg, ${comp.gradient[0]}, ${comp.gradient[1]})` }}
              />
            </div>
          ))}
        </div>

        {/* Leaderboard preview — mirrors the app's leaderboard: metric tabs,
            period pills, podium (2nd · 1st · 3rd with crown), then ranked rows */}
        <div className="reveal reveal-delay-4 mx-auto mt-20 max-w-xl">
          <div className="mb-8 flex items-center justify-center gap-3">
            <Trophy className="h-5 w-5" style={{ color: MAD_RED }} />
            <h3 className="font-heading text-[28px] tracking-[2px] text-[#f5f5f5]">LEADERBOARDS</h3>
          </div>

          <div
            className="rounded-[20px] overflow-hidden border border-white/[0.08] p-5"
            style={{ background: "linear-gradient(180deg, rgba(26,26,26,0.6) 0%, rgba(10,10,10,0.9) 100%)" }}
          >
            {/* Metric tabs — the app's four leaderboard metrics */}
            <div className="flex flex-wrap justify-center gap-1.5">
              {leaderboardMetrics.map((metric, i) => (
                <div
                  key={metric.label}
                  className="flex items-center gap-1.5 rounded-full px-3 py-1.5"
                  style={
                    i === 0
                      ? { background: MAD_RED }
                      : { background: "rgba(255,255,255,0.06)" }
                  }
                >
                  <metric.icon
                    className="h-3 w-3"
                    style={{ color: i === 0 ? "#fff" : "rgba(255,255,255,0.4)" }}
                  />
                  <span
                    className="text-[11px] font-semibold"
                    style={{ color: i === 0 ? "#fff" : "rgba(255,255,255,0.4)" }}
                  >
                    {metric.label}
                  </span>
                </div>
              ))}
            </div>

            {/* Period pills */}
            <div className="mt-3 flex justify-center gap-1.5">
              {leaderboardPeriods.map((period) => (
                <span
                  key={period}
                  className={`rounded-full px-2.5 py-1 text-[10px] font-semibold ${
                    period === "Week"
                      ? "bg-white/[0.12] text-white"
                      : "text-white/30"
                  }`}
                >
                  {period}
                </span>
              ))}
            </div>

            {/* Podium: 2nd · 1st · 3rd, first place elevated with crown */}
            <div className="mt-8 flex items-end justify-center gap-8">
              {podium.map((entry) => (
                <div key={entry.name} className="flex flex-col items-center" style={{ marginBottom: entry.rank === 0 ? 16 : 0 }}>
                  <div className="relative">
                    <ProfileAvatar
                      username={entry.username}
                      initials={entry.initials}
                      size={entry.size}
                      style={{ border: `${entry.rank === 0 ? 3 : 2}px solid ${medalColor(entry.rank)}` }}
                    />
                    <span
                      className="absolute -right-1 -top-1 flex h-5 w-5 items-center justify-center rounded-full text-[10px] font-bold text-black"
                      style={{ background: medalColor(entry.rank) }}
                    >
                      {entry.rank + 1}
                    </span>
                  </div>
                  {entry.rank === 0 && (
                    <Crown className="mt-1.5 h-4 w-4" style={{ color: MEDAL_GOLD }} />
                  )}
                  <div className="mt-1 flex items-center gap-1.5">
                    <span className="text-xs font-semibold text-white">{entry.name}</span>
                    {entry.isYou && (
                      <span className="rounded-full px-1.5 py-0.5 text-[8px] font-bold text-white" style={{ background: MAD_RED }}>
                        YOU
                      </span>
                    )}
                  </div>
                  <span className="text-xs font-bold" style={{ color: medalColor(entry.rank) }}>
                    {entry.value}
                  </span>
                </div>
              ))}
            </div>

            {/* Rank 4+ rows */}
            <div className="mt-6 space-y-2">
              {leaderboardRows.map((row) => (
                <LeaderRow key={row.rank} row={row} />
              ))}
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
