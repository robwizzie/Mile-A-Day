import { Flame, TrendingUp, Target, Zap, Flag } from "lucide-react"

const competitions = [
  {
    icon: Flame,
    name: "Streaks",
    description: "Hold a running streak as long as you can. First to break the streak loses.",
    color: "#ff6b6b",
  },
  {
    icon: TrendingUp,
    name: "Apex",
    description:
      "Over a period of time (e.g. 1 week) whoever has the most distance during that time wins.",
    color: "#2dd4bf",
  },
  {
    icon: Target,
    name: "Targets",
    description:
      "Anyone who completes the goal in a given day gets a point. Whoever has the most points at the end wins.",
    color: "#fbbf24",
  },
  {
    icon: Zap,
    name: "Clash",
    description:
      "Whoever goes the furthest each day wins a point. First to reach the target score or most points wins.",
    color: "#a855f7",
  },
  {
    icon: Flag,
    name: "Race",
    description: "There is a distance goal set and whoever gets there first wins.",
    color: "#6366f1",
  },
]

export function CompetitionsSection() {
  return (
    <section id="competitions" className="relative px-6 py-24 bg-[#080808]">
      <div className="pointer-events-none absolute inset-0">
        <div className="absolute top-1/2 right-0 h-[400px] w-[400px] -translate-y-1/2 rounded-full bg-[#8b1538] opacity-[0.04] blur-[150px]" />
      </div>
      <div className="relative mx-auto max-w-6xl">
        <div className="mx-auto mb-16 max-w-2xl text-center">
          <span className="reveal mb-4 inline-block text-sm font-semibold uppercase tracking-widest text-[#c72554]">
            Competitions
          </span>
          <h2 className="reveal reveal-delay-1 font-heading text-[clamp(40px,6vw,72px)] leading-none tracking-[-1px] text-[#f5f5f5]">
            GO THE EXTRA MILE
          </h2>
          <p className="reveal reveal-delay-2 mt-4 text-base leading-relaxed text-[#a0a0a0]">
            Five competition modes that turn your daily mile into something you can&apos;t afford to skip. Challenge friends, set the stakes, and find out who really shows up.
          </p>
        </div>

        <div className="mx-auto max-w-2xl">
          <div className="grid gap-4">
            {competitions.map((comp, i) => (
              <div
                key={comp.name}
                className={`reveal reveal-delay-${Math.min(i + 1, 5)} glass-card flex items-start gap-4 rounded-2xl p-5 transition-all duration-300 hover:border-[#c72554]/20 hover:-translate-y-1`}
              >
                <div
                  className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl"
                  style={{
                    background: `linear-gradient(135deg, ${comp.color}25, ${comp.color}10)`,
                  }}
                >
                  <comp.icon className="h-5 w-5" style={{ color: comp.color }} />
                </div>
                <div>
                  <h3 className="font-heading text-[20px] tracking-[1px] text-[#f5f5f5]">{comp.name}</h3>
                  <p className="mt-1 text-sm leading-relaxed text-[#a0a0a0]">{comp.description}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  )
}
