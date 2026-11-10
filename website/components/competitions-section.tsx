"use client"

import { Flame, CircleArrowUp, Target, Zap, Flag, Timer, Footprints, Crown } from "lucide-react"
import { SectionHeader } from "./section-header"
import { ProfileAvatar } from "@/components/profile-avatar"
import { usePublicUser } from "@/lib/public-user"

// Competition types — names, icons, gradients, taglines and rules mirror the
// app's CompetitionType enum exactly (Models/Competition.swift: tagline +
// howItWorks, the copy the Compete tab's mode gallery and explainer show). The cards
// mirror the app's type picker (CompetitionTypeCard): gradient-tinted icon
// in a soft circle, type name, then the description.
const competitions = [
  {
    icon: Flame,
    name: "Streaks",
    gradient: ["#FF6B6B", "#FF8E53"],
    tagline: "Last one standing.",
    description: "Everyone has to hit the same daily goal. Miss a day and you spend one of your lives. Run out of lives and you're out. Last one alive wins.",
  },
  {
    icon: CircleArrowUp,
    name: "Apex",
    gradient: ["#4ECDC4", "#44A08D"],
    tagline: "Most miles wins.",
    description: "Run and walk as normal for the set window. Every counted mile adds to your total. Highest total when the clock runs out wins.",
  },
  {
    icon: Target,
    name: "Targets",
    gradient: ["#F7971E", "#FFD200"],
    tagline: "Hit your goal, bank a point.",
    description: "A goal is set for each day. Everyone who hits it that day banks a point. Most points at the end wins. You're racing the goal, not each other.",
  },
  {
    icon: Zap,
    name: "Clash",
    gradient: ["#C33764", "#1D2671"],
    tagline: "Win the day, take the point.",
    description: "Every day is its own mini-contest. Whoever goes furthest that day takes the point. First to the target score wins, or most points when time's up.",
  },
  {
    icon: Flag,
    name: "Race",
    gradient: ["#667EEA", "#764BA2"],
    tagline: "First to the finish line.",
    description: "One distance is set as the finish line. Every mile you log moves you toward it. First person there wins. No clock, no daily goals.",
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
  { name: "@dave", username: "dave", initials: "DS", value: "13.8 mi", rank: 1, size: 56 },
  { name: "@rob", username: "rob", initials: "RW", value: "14.2 mi", rank: 0, size: 68, isYou: true },
  { name: "@MegsMiles", username: "MegsMiles", initials: "MM", value: "11.4 mi", rank: 2, size: 52 },
]
const leaderboardRows = [
  { rank: 4, name: "@Aaron", username: "Aaron", initials: "AA", value: "8.9 mi" },
  { rank: 5, name: "@mad", username: "mad", initials: "M", value: "7.4 mi" },
]

/** A rank-4+ leaderboard row with the user's real photo and live streak. */
function LeaderRow({ row }: { row: (typeof leaderboardRows)[number] }) {
  const user = usePublicUser(row.username)
  return (
    <div className="flex items-center gap-3 rounded-2xl bg-white/[0.05] px-4 py-2.5">
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
      className="scroll-mt-20 bg-[#140b0e] px-6 py-24 text-white"
    >
      <div className="mx-auto max-w-6xl">
        <SectionHeader
          className="mb-14"
          eyebrow="Competitions"
          title="Go the extra mile."
          body="Five competition modes, solo or in teams, that turn your daily mile into something you can't afford to skip. Scored on the miles your phone or watch actually tracked."
        />

        {/* All five modes, each in the colour the app's mode gallery gives it */}
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-6">
          {competitions.map((comp, i) => (
            <div
              key={comp.name}
              className={`relative overflow-hidden rounded-3xl p-7 ${
                i < 3 ? "lg:col-span-2" : "lg:col-span-3"
              }`}
              style={{
                background: `linear-gradient(160deg, ${comp.gradient[0]} 0%, ${comp.gradient[1]} 100%)`,
              }}
            >
              {/* Targets' yellow is too light for white type */}
              <div className={comp.name === "Targets" ? "text-[#2b1800]" : "text-white"}>
                <comp.icon className="h-7 w-7" aria-hidden="true" />
                <h3 className="mt-5 font-heading text-[30px] leading-none">{comp.name}</h3>
                <p className="mt-2 text-[16px] font-semibold">{comp.tagline}</p>
                <p className="mt-2 text-[15px] leading-relaxed opacity-85">{comp.description}</p>
              </div>
            </div>
          ))}
        </div>

        {/* Leaderboard preview — mirrors the app's leaderboard: metric tabs,
            period pills, podium (2nd · 1st · 3rd with crown), then ranked rows */}
        <div className="mt-20 grid items-center gap-10 lg:grid-cols-2 lg:gap-16">
          <div>
            <h3 className="font-heading text-[clamp(32px,4vw,48px)] leading-[0.95]">
              Leaderboards.
            </h3>
            <p className="mt-4 max-w-md text-[17px] leading-relaxed text-white/70">
              Every friend, ranked, in the Friends tab, any day of the week. Sort by
              miles, pace or streak, today or all-time.
            </p>
          </div>

          <div className="mx-auto w-full max-w-xl rounded-3xl bg-white/[0.04] p-5">
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
