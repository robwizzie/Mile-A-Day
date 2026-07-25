"use client";

import {
  Shield,
  Flame,
  LayoutGrid,
  Timer,
  MessageCircle,
  Images,
  Camera,
  Footprints,
  Flag,
  BarChart3,
  ThumbsUp,
  Activity,
  Award,
  Swords,
  CalendarRange,
  Map,
} from "lucide-react";

// Bump on every App Store release, alongside the app's What's New entry in
// app/Mile A Day/Views/Components/WhatsNewView.swift. The previous release's
// headliners drop into PREVIOUS below rather than disappearing.
const VERSION = "1.3.0";

// Headliners for this release. Copy tracks what the app actually does —
// Streak Tokens are StreakSave/DoubleDown/StreakAssist, the flame lifecycle is
// StreakFlamePhase (coal -> burning -> blazing), and the two dashboard styles
// are DashboardStyle.modern / .fun.
const FEATURES = [
  {
    icon: Shield,
    color: "#FFD966",
    title: "Streak Tokens",
    desc: "Earn Double Down, Streak Save, and Streak Assist by running — then spend them to protect your streak, or rescue a friend's.",
  },
  {
    icon: Flame,
    color: "#FF9F0A",
    title: "A Flame That Burns Down",
    desc: "A coal at midnight, shrinking as your day runs out, and a full blaze the second you bank your mile — on your dashboard and your Home Screen.",
  },
  {
    icon: LayoutGrid,
    color: "#c72554",
    title: "Your Dashboard, Your Way",
    desc: "One card for your mile, streak, and tokens. Pick Modern for a calm, focused layout or Fun for the animated flame buddy.",
  },
  {
    icon: Timer,
    color: "#5AC8FA",
    title: "Lock Screen Countdown",
    desc: "Streak on the line in the evening? A live countdown to midnight lands on your Lock Screen and Dynamic Island, with one-tap Start Mile.",
  },
  {
    icon: MessageCircle,
    color: "#BF5AF2",
    title: "Comments & Collabs",
    desc: "Comment, reply, and @mention friends — and share a run together as a co-post that lands on both your profiles.",
  },
  {
    icon: Images,
    color: "#ff4d7d",
    title: "Stories & A Faster Feed",
    desc: "Swipe between friends' stories, spot fresh miles at a glance, and come back to a feed that has already refreshed.",
  },
];

// Second tier: real shipped features, just not the headline. Rendered as a
// compact strip so the section stays scannable instead of becoming 12 cards.
const ALSO_NEW = [
  { icon: Footprints, label: "Walks that agree between friends" },
  { icon: Camera, label: "Pinch-to-zoom camera + 0.5x lens" },
  { icon: Activity, label: "Treadmill + Apple Health auto-import" },
  { icon: Flag, label: "Road to your next streak club" },
  { icon: BarChart3, label: "Your month, wrapped" },
  { icon: ThumbsUp, label: "Unlimited hypes" },
];

// Previous release. Kept visible — these are still new to anyone discovering
// the app now — but demoted to a slim list so the current release leads.
const PREVIOUS = [
  {
    icon: Timer,
    color: "#c72554",
    title: "Race PRs",
    desc: "Automatic records for every standard distance",
  },
  {
    icon: Award,
    color: "#FF9900",
    title: "3D Medals",
    desc: "Tiltable medals and a shelf of social awards",
  },
  {
    icon: Swords,
    color: "#D94059",
    title: "Head-to-Head",
    desc: "Call out a friend, settle it by sundown",
  },
  {
    icon: LayoutGrid,
    color: "#33B34D",
    title: "Widgets",
    desc: "Streak, today's progress, friends leaderboard",
  },
  {
    icon: CalendarRange,
    color: "#5AC8FA",
    title: "Weekly Recap",
    desc: "Your week in miles, wrapped",
  },
  {
    icon: Map,
    color: "#ff4d7d",
    title: "Heatmap & Memories",
    desc: "Every route you've run on one glowing map",
  },
];

export function WhatsNewSection() {
  return (
    <section className="section-lazy relative px-6 py-24">
      <div className="relative mx-auto max-w-6xl">
        <div className="mx-auto mb-14 max-w-2xl text-center">
          <span className="reveal mb-4 inline-block text-sm font-semibold uppercase tracking-widest text-[#c72554]">
            Just shipped
          </span>
          <h2 className="reveal reveal-delay-1 font-heading text-[clamp(40px,6vw,72px)] leading-none tracking-[-1px] text-[#f5f5f5]">
            NEW IN <span className="text-[#c72554]">{VERSION}</span>
          </h2>
          <p className="reveal reveal-delay-2 mt-4 text-base leading-relaxed text-[#a0a0a0]">
            The biggest update yet — a dashboard that reacts to your day, tokens
            that protect your streak, and a feed worth coming back to.
          </p>
        </div>

        <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
          {FEATURES.map((feature, i) => (
            <div
              key={feature.title}
              className={`reveal-scale reveal-delay-${(i % 3) + 1} glass-card type-card group relative overflow-hidden rounded-2xl p-6`}
              style={{ "--accent": feature.color } as React.CSSProperties}
            >
              <div
                className="pointer-events-none absolute -right-8 -top-8 h-28 w-28 rounded-full opacity-[0.07] blur-2xl transition-opacity duration-300 group-hover:opacity-20"
                style={{ background: feature.color }}
              />
              <div
                className="relative mb-4 flex h-12 w-12 items-center justify-center rounded-xl"
                style={{
                  background: `linear-gradient(135deg, ${feature.color}20, ${feature.color}08)`,
                }}
              >
                <feature.icon
                  className="h-6 w-6"
                  style={{ color: feature.color }}
                />
              </div>
              <h3 className="font-heading relative mb-2 text-[22px] uppercase tracking-[1px] text-[#f5f5f5]">
                {feature.title}
              </h3>
              <p className="relative text-sm leading-relaxed text-[#a0a0a0]">
                {feature.desc}
              </p>
            </div>
          ))}
        </div>

        <div className="reveal reveal-delay-2 mt-6 flex flex-wrap justify-center gap-2.5">
          {ALSO_NEW.map((item) => (
            <span
              key={item.label}
              className="inline-flex items-center gap-2 rounded-full border border-white/[0.08] bg-white/[0.03] px-4 py-2 text-sm text-[#a0a0a0]"
            >
              <item.icon className="h-4 w-4 shrink-0 text-[#c72554]" />
              {item.label}
            </span>
          ))}
        </div>

        <div className="reveal reveal-delay-3 glass-card mt-14 rounded-2xl p-6 sm:p-8">
          <h3 className="mb-6 text-xs font-semibold uppercase tracking-widest text-[#707070]">
            Still new to you
          </h3>
          <div className="grid gap-x-8 gap-y-5 sm:grid-cols-2 lg:grid-cols-3">
            {PREVIOUS.map((item) => (
              <div key={item.title} className="flex items-start gap-3">
                <item.icon
                  className="mt-0.5 h-5 w-5 shrink-0"
                  style={{ color: item.color }}
                />
                <div>
                  <p className="text-[15px] font-semibold text-[#f5f5f5]">
                    {item.title}
                  </p>
                  <p className="text-sm leading-relaxed text-[#a0a0a0]">
                    {item.desc}
                  </p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
