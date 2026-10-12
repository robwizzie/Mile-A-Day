import Image from "next/image";
import { Flame, Smartphone, Users, Watch, Activity, Award, Shield, Footprints, PersonStanding } from "lucide-react";

const topFeatures = [
  {
    icon: Flame,
    title: "Streak Tracking",
    description:
      "Track your daily mile streak and watch it climb. Life gets in the way? Streak Tokens can cover a missed day — one you earn, one that saves itself, and one a friend gives you.",
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
      "Seamlessly syncs with Apple Health. Your miles automatically count from workouts, walks, and runs — no manual logging. Strava, Garmin and the rest count too, with duplicates removed.",
    color: "#8b1538",
  },
  {
    icon: Award,
    title: "Medals & Records",
    description:
      "Unlock 100+ medals as you hit milestones. Track your fastest mile, longest streak, and personal bests.",
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
            <div className="mb-4 flex flex-col gap-4 sm:flex-row sm:items-start">
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
                  Your mile is everywhere. Start a walk or run from your wrist,
                  keep Flamey and your streak on the Home Screen, and watch the
                  mile fill in the Dynamic Island. Or just ask Siri to start it.
                </p>
              </div>
            </div>

            {/* Devices. The widgets are REAL Home Screen captures (Streak
                Flame medium + streak ring small, Oct 2026). The Watch and the
                Dynamic Island are drawn from source: Watch ContentView
                (progress ring, streak pill with held tokens, Start Run / Start
                Walk) and WorkoutLiveActivity's compact presentation (walk
                figure leading, daily-progress ring trailing). */}
            <div className="mt-6 flex flex-col items-center gap-6">
              <div className="flex flex-wrap items-end justify-center gap-4">
                <figure className="flex flex-col items-center gap-2">
                  <Image
                    src="/images/widgets/streak-flame-medium.png"
                    alt="Mile A Day Streak Flame widget: 511 day streak, best ever, 3 tokens"
                    width={666}
                    height={312}
                    sizes="260px"
                    className="w-[260px] rounded-[22px] border border-white/[0.06]"
                  />
                  <figcaption className="text-[10px] text-[#555]">Streak Flame widget</figcaption>
                </figure>
                <figure className="flex flex-col items-center gap-2">
                  <Image
                    src="/images/widgets/streak-small.png"
                    alt="Mile A Day small streak widget showing 511"
                    width={310}
                    height={310}
                    sizes="122px"
                    className="w-[122px] rounded-[22px] border border-white/[0.06]"
                  />
                  <figcaption className="text-[10px] text-[#555]">Streak widget</figcaption>
                </figure>
              </div>

              <div className="flex flex-wrap items-end justify-center gap-8">
                {/* Apple Watch home */}
                <figure className="flex flex-col items-center gap-2">
                  <div className="flex h-[176px] w-[144px] flex-col items-center justify-center gap-2 rounded-[34px] border-[5px] border-[#222] bg-black px-3 shadow-[0_0_0_1px_rgba(255,255,255,0.08)]">
                    <div className="relative h-[54px] w-[54px]">
                      <svg viewBox="0 0 56 56" className="h-full w-full -rotate-90">
                        <circle cx="28" cy="28" r="23" fill="none" stroke="rgba(255,255,255,0.08)" strokeWidth="5" />
                        <circle cx="28" cy="28" r="23" fill="none" stroke="#D94059" strokeWidth="5" strokeLinecap="round" strokeDasharray={`${2 * Math.PI * 23}`} strokeDashoffset={`${2 * Math.PI * 23 * 0.35}`} />
                      </svg>
                      <span className="absolute inset-0 flex items-center justify-center text-[13px] font-bold text-white">0.65</span>
                    </div>
                    <div className="flex items-center gap-1 whitespace-nowrap rounded-full border border-white/10 bg-white/[0.06] px-2 py-0.5">
                      <Flame className="h-2.5 w-2.5 text-[#FF9F0A]" />
                      <span className="text-[10px] font-extrabold text-white">511</span>
                      <span className="text-[8px] text-white/50">day streak</span>
                      <Shield className="ml-0.5 h-2.5 w-2.5 text-[#FFD659]" />
                      <span className="text-[9px] font-extrabold text-[#FFD659]">3</span>
                    </div>
                    <div className="flex w-full flex-col gap-1">
                      <span className="flex items-center justify-center gap-1 rounded-full bg-[#D94059] py-1 text-[9px] font-bold text-white">
                        <Footprints className="h-2.5 w-2.5" /> Start Run
                      </span>
                      <span className="flex items-center justify-center gap-1 rounded-full bg-white/[0.1] py-1 text-[9px] font-bold text-white">
                        <PersonStanding className="h-2.5 w-2.5" /> Start Walk
                      </span>
                    </div>
                  </div>
                  <figcaption className="text-[10px] text-[#555]">Apple Watch</figcaption>
                </figure>

                {/* Dynamic Island, compact: walk figure · (camera) · progress ring */}
                <figure className="flex flex-col items-center gap-2">
                  <div className="flex h-[37px] w-[200px] items-center justify-between rounded-full bg-black px-3 shadow-[0_0_0_1px_rgba(255,255,255,0.08)]">
                    <PersonStanding className="h-[18px] w-[18px] text-white" strokeWidth={2.4} />
                    <svg viewBox="0 0 20 20" className="h-[18px] w-[18px] -rotate-90">
                      <circle cx="10" cy="10" r="8" fill="none" stroke="rgba(255,255,255,0.15)" strokeWidth="2.5" />
                      <circle cx="10" cy="10" r="8" fill="none" stroke="#E64D4D" strokeWidth="2.5" strokeLinecap="round" strokeDasharray={`${2 * Math.PI * 8}`} strokeDashoffset={`${2 * Math.PI * 8 * 0.35}`} />
                    </svg>
                  </div>
                  <figcaption className="text-[10px] text-[#555]">Dynamic Island</figcaption>
                </figure>
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
