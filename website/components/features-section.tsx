import { Flame, Watch, Users, Activity, Trophy, Smartphone } from "lucide-react"

const features = [
  {
    icon: Flame,
    title: "Streak Tracking",
    description:
      "Track your daily mile streak and never break the chain. Watch your number climb day after day as your habit grows stronger.",
    color: "#c72554",
  },
  {
    icon: Smartphone,
    title: "Start Runs In-App",
    description:
      "Start your daily walk or run directly from the app. Tap 'Start Mile' and go -- it is that simple. No complicated setup needed.",
    color: "#ff6b6b",
  },
  {
    icon: Watch,
    title: "Apple Watch Support",
    description:
      "Log your mile right from your wrist. Full Apple Watch companion app with HealthKit integration for automatic tracking.",
    color: "#8b1538",
  },
  {
    icon: Users,
    title: "Social & Friends",
    description:
      "Add friends, see their streaks, and keep each other motivated. Nothing like a little friendly accountability.",
    color: "#c72554",
  },
  {
    icon: Trophy,
    title: "Badges & Medals",
    description:
      "Unlock achievements as you hit milestones. From 500 Mile Club to Year in Miles, there is always something to chase.",
    color: "#ff6b6b",
  },
  {
    icon: Activity,
    title: "HealthKit Integration",
    description:
      "Seamlessly syncs with Apple Health. Your miles automatically count from your workouts, walks, and runs.",
    color: "#8b1538",
  },
]

export function FeaturesSection() {
  return (
    <section id="features" className="relative px-6 py-24">
      <div className="pointer-events-none absolute inset-0">
        <div className="absolute top-0 right-0 h-[400px] w-[400px] rounded-full bg-[#8b1538] opacity-[0.04] blur-[150px]" />
      </div>
      <div className="relative mx-auto max-w-6xl">
        <div className="mx-auto mb-16 max-w-2xl text-center">
          <span className="reveal mb-4 inline-block text-sm font-semibold uppercase tracking-widest text-[#c72554]">
            Features
          </span>
          <h2 className="reveal reveal-delay-1 font-heading text-[clamp(40px,6vw,72px)] leading-none tracking-[-1px] text-[#f5f5f5]">
            EVERYTHING YOU NEED.<br />NOTHING YOU DON&apos;T.
          </h2>
          <p className="reveal reveal-delay-2 mt-4 text-base leading-relaxed text-[#a0a0a0]">
            Simple by design. Powerful where it counts.
          </p>
        </div>

        <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
          {features.map((feature, i) => (
            <div
              key={feature.title}
              className={`reveal-scale reveal-delay-${Math.min(i + 1, 5)} glass-card group rounded-2xl p-6 transition-all duration-300 hover:border-[#c72554]/20 hover:-translate-y-1 hover:shadow-[0_10px_40px_-10px_rgba(199,37,84,0.15)]`}
            >
              <div
                className="mb-4 flex h-12 w-12 items-center justify-center rounded-xl"
                style={{
                  background: `linear-gradient(135deg, ${feature.color}20, ${feature.color}08)`,
                }}
              >
                <feature.icon className="h-6 w-6" style={{ color: feature.color }} />
              </div>
              <h3 className="font-heading mb-2 text-[22px] tracking-[1px] text-[#f5f5f5] uppercase">{feature.title}</h3>
              <p className="text-sm leading-relaxed text-[#a0a0a0]">{feature.description}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
