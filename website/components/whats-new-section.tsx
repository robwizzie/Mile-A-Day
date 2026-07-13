"use client";

import {
  Timer,
  Award,
  Swords,
  LayoutGrid,
  CalendarRange,
  Map,
} from "lucide-react";

const FEATURES = [
  {
    icon: Timer,
    color: "#c72554",
    title: "Race PRs",
    desc: "Automatic personal records for 5K, 10K, and every standard distance — with pace, tracked from your real runs.",
  },
  {
    icon: Award,
    color: "#FF9900",
    title: "3D Medals",
    desc: "Milestones now come with premium, tiltable medals — plus a whole shelf of new social awards to chase.",
  },
  {
    icon: Swords,
    color: "#D94059",
    title: "Head-to-Head Challenges",
    desc: "Daily challenges went competitive. Call out a friend, run the same challenge, and settle it by sundown.",
  },
  {
    icon: LayoutGrid,
    color: "#33B34D",
    title: "New Widgets",
    desc: "Your streak, today's progress, and now a live friends leaderboard — right on your home screen.",
  },
  {
    icon: CalendarRange,
    color: "#5AC8FA",
    title: "Weekly Recap",
    desc: "Your week in miles, wrapped: distance, streak days, and the moments worth bragging about.",
  },
  {
    icon: Map,
    color: "#ff4d7d",
    title: "Heatmap & Memories",
    desc: "Every route you've ever run on one glowing map — and yearly memories that resurface your best days.",
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
            NEW IN <span className="text-[#c72554]">2.0</span>
          </h2>
          <p className="reveal reveal-delay-2 mt-4 text-base leading-relaxed text-[#a0a0a0]">
            The biggest update since launch — built from what the community
            asked for.
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
      </div>
    </section>
  );
}
