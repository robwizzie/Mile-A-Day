import { Flame, Smartphone, Users, Watch, Activity, Award } from "lucide-react";

const topFeatures = [
  {
    icon: Flame,
    title: "Streak Tracking",
    description:
      "Track your daily mile streak and never break the chain. Watch your number climb day after day as your habit grows stronger.",
    color: "#D94059",
  },
  {
    icon: Smartphone,
    title: "Start Runs In-App",
    description:
      "Start your daily walk or run directly from the app. Tap 'Start Mile' and go — it is that simple. No complicated setup needed.",
    color: "#FF6B6B",
  },
  {
    icon: Users,
    title: "Social & Friends",
    description:
      "Share your runs to the feed, post stories, and hype your friends' miles. Nudge slackers, flex your wins, and compete head-to-head.",
    color: "#D94059",
  },
];

const bottomFeatures = [
  {
    icon: Activity,
    title: "HealthKit Sync",
    description:
      "Seamlessly syncs with Apple Health. Your miles automatically count from workouts, walks, and runs — no manual logging.",
    color: "#8b1538",
  },
  {
    icon: Award,
    title: "Medals & Records",
    description:
      "Unlock 63 medals as you hit milestones. Track your fastest mile, longest streak, and personal bests.",
    color: "#FF6B6B",
  },
];

export function FeaturesSection() {
  return (
    <section
      id="features"
      className="section-lazy relative px-6 py-24"
      style={{
        background:
          "radial-gradient(ellipse 400px 400px at 90% 0%, rgba(139,21,56,0.04) 0%, transparent 70%)",
      }}
    >
      <div className="relative mx-auto max-w-6xl">
        <div className="mx-auto mb-16 max-w-2xl text-center">
          <span className="reveal mb-4 inline-block text-sm font-semibold uppercase tracking-widest text-[#c72554]">
            Features
          </span>
          <h2 className="reveal reveal-delay-1 font-heading text-[clamp(40px,6vw,72px)] leading-none tracking-[-1px] text-[#f5f5f5]">
            EVERYTHING YOU NEED.
            <br />
            NOTHING YOU DON&apos;T.
          </h2>
          <p className="reveal reveal-delay-2 mt-4 text-base leading-relaxed text-[#a0a0a0]">
            Simple by design. Powerful where it counts.
          </p>
        </div>

        {/* Top row: 3 cards */}
        <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
          {topFeatures.map((feature, i) => (
            <div
              key={feature.title}
              className={`reveal-scale reveal-delay-${i + 1} glass-card type-card group rounded-2xl p-6`}
              style={{ "--accent": feature.color } as React.CSSProperties}
            >
              <div
                className="mb-4 flex h-12 w-12 items-center justify-center rounded-xl"
                style={{
                  background: `linear-gradient(135deg, ${feature.color}20, ${feature.color}08)`,
                }}
              >
                <feature.icon
                  className="h-6 w-6"
                  style={{ color: feature.color }}
                />
              </div>
              <h3 className="font-heading mb-2 text-[22px] tracking-[1px] text-[#f5f5f5] uppercase">
                {feature.title}
              </h3>
              <p className="text-sm leading-relaxed text-[#a0a0a0]">
                {feature.description}
              </p>
            </div>
          ))}
        </div>

        {/* Bottom row: wide device card + 2 stacked cards */}
        <div className="mt-5 grid gap-5 lg:grid-cols-5">
          {/* Wide Watch/Widget/Dynamic Island card */}
          <div
            className="reveal-scale reveal-delay-4 glass-card type-card group rounded-2xl p-6 lg:col-span-3"
            style={{ "--accent": "#D94059" } as React.CSSProperties}
          >
            <div className="flex items-start gap-4 mb-4">
              <div
                className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl"
                style={{
                  background: "linear-gradient(135deg, #8b153820, #8b153808)",
                }}
              >
                <Watch className="h-6 w-6 text-[#8b1538]" />
              </div>
              <div>
                <h3 className="font-heading mb-1 text-[22px] tracking-[1px] text-[#f5f5f5] uppercase">
                  Watch, Widgets & Live Activities
                </h3>
                <p className="text-sm leading-relaxed text-[#a0a0a0]">
                  Your mile is everywhere. Start runs from your wrist, check
                  your streak from the home screen, and track progress in the
                  Dynamic Island.
                </p>
              </div>
            </div>

            {/* Device mockups — matching app's actual UI */}
            <div className="mt-6 flex items-end justify-center gap-6 sm:gap-10">
              {/* Home screen widget mockup — the app's actual streak widget is
                  a progress ring with the day count in orange (StreakCountWidget) */}
              <div className="flex flex-col items-center gap-2">
                <div
                  className="h-[88px] w-[88px] rounded-[18px] border border-white/[0.08] flex items-center justify-center"
                  style={{
                    background:
                      "linear-gradient(180deg, #1a1a1a 0%, #0d0d0d 100%)",
                  }}
                >
                  <div className="relative h-[68px] w-[68px]">
                    <svg viewBox="0 0 68 68" className="h-[68px] w-[68px]">
                      <circle
                        cx="34"
                        cy="34"
                        r="30"
                        fill="rgba(255,153,0,0.10)"
                        stroke="rgba(128,128,128,0.2)"
                        strokeWidth="4"
                      />
                      <circle
                        cx="34"
                        cy="34"
                        r="30"
                        fill="none"
                        stroke="#FF9900"
                        strokeWidth="4"
                        strokeLinecap="round"
                        strokeDasharray={`${2 * Math.PI * 30}`}
                        strokeDashoffset={`${2 * Math.PI * 30 * 0.25}`}
                        transform="rotate(-90 34 34)"
                      />
                    </svg>
                    <div className="absolute inset-0 flex flex-col items-center justify-center">
                      <span className="font-heading text-[22px] leading-none text-[#FF9900]">
                        288
                      </span>
                      <span className="text-[8px] font-medium text-[#FF9900]/80">
                        days
                      </span>
                    </div>
                  </div>
                </div>
                <span className="text-[10px] text-[#555]">Widget</span>
              </div>

              {/* Watch mockup — matches app's watchOS progress ring */}
              <div className="flex flex-col items-center gap-2">
                <div
                  className="relative h-[100px] w-[84px] rounded-[20px] border-2 border-white/[0.08] p-2 flex flex-col items-center justify-center"
                  style={{
                    background:
                      "linear-gradient(180deg, #1a1a1a 0%, #0a0a0a 100%)",
                  }}
                >
                  <div className="relative h-14 w-14 mb-1">
                    <svg viewBox="0 0 56 56" className="h-14 w-14">
                      <circle
                        cx="28"
                        cy="28"
                        r="23"
                        fill="none"
                        stroke="rgba(255,255,255,0.06)"
                        strokeWidth="5"
                      />
                      <circle
                        cx="28"
                        cy="28"
                        r="23"
                        fill="none"
                        strokeWidth="5"
                        strokeLinecap="round"
                        stroke="url(#watchProgress)"
                        strokeDasharray={`${2 * Math.PI * 23}`}
                        strokeDashoffset={`${2 * Math.PI * 23 * 0.25}`}
                        transform="rotate(-90 28 28)"
                      />
                      <defs>
                        <linearGradient
                          id="watchProgress"
                          x1="0%"
                          y1="0%"
                          x2="100%"
                          y2="0%"
                        >
                          <stop offset="0%" stopColor="#D94059" />
                          <stop offset="100%" stopColor="#FF8E53" />
                        </linearGradient>
                      </defs>
                    </svg>
                    <span className="absolute inset-0 flex items-center justify-center font-heading text-[15px] text-white">
                      75%
                    </span>
                  </div>
                  <span className="text-[7px] font-medium text-white/40">
                    0.75 / 1.0 mi
                  </span>
                </div>
                <span className="text-[10px] text-[#555]">Apple Watch</span>
              </div>

              {/* Dynamic Island mockup */}
              <div className="flex flex-col items-center gap-2">
                <div className="flex items-center gap-2.5 rounded-[22px] bg-black border border-white/[0.08] px-4 py-2.5">
                  <div
                    className="h-7 w-7 rounded-full flex items-center justify-center"
                    style={{
                      background:
                        "linear-gradient(135deg, #D9405930, #D9405910)",
                    }}
                  >
                    <Activity className="h-3.5 w-3.5 text-[#D94059]" />
                  </div>
                  <div className="flex flex-col">
                    <span className="text-[11px] font-semibold text-white leading-tight">
                      0.75 mi
                    </span>
                    <span className="text-[8px] text-white/40 leading-tight">
                      7:42 /mi
                    </span>
                  </div>
                  <div className="h-5 w-5 rounded-full flex items-center justify-center ml-1">
                    <svg viewBox="0 0 20 20" className="h-5 w-5">
                      <circle
                        cx="10"
                        cy="10"
                        r="8"
                        fill="none"
                        stroke="rgba(255,255,255,0.08)"
                        strokeWidth="2"
                      />
                      <circle
                        cx="10"
                        cy="10"
                        r="8"
                        fill="none"
                        stroke="#D94059"
                        strokeWidth="2"
                        strokeLinecap="round"
                        strokeDasharray={`${2 * Math.PI * 8}`}
                        strokeDashoffset={`${2 * Math.PI * 8 * 0.25}`}
                        transform="rotate(-90 10 10)"
                      />
                    </svg>
                  </div>
                </div>
                <span className="text-[10px] text-[#555]">Dynamic Island</span>
              </div>
            </div>
          </div>

          {/* Two stacked cards */}
          <div className="flex flex-col gap-5 lg:col-span-2">
            {bottomFeatures.map((feature) => (
              <div
                key={feature.title}
                className="reveal-scale reveal-delay-5 glass-card type-card group flex-1 rounded-2xl p-6"
                style={{ "--accent": feature.color } as React.CSSProperties}
              >
                <div
                  className="mb-4 flex h-12 w-12 items-center justify-center rounded-xl"
                  style={{
                    background: `linear-gradient(135deg, ${feature.color}20, ${feature.color}08)`,
                  }}
                >
                  <feature.icon
                    className="h-6 w-6"
                    style={{ color: feature.color }}
                  />
                </div>
                <h3 className="font-heading mb-2 text-[22px] tracking-[1px] text-[#f5f5f5] uppercase">
                  {feature.title}
                </h3>
                <p className="text-sm leading-relaxed text-[#a0a0a0]">
                  {feature.description}
                </p>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
