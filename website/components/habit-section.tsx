import { Timer, Flame, TrendingUp } from "lucide-react"

export function HabitSection() {
  return (
    <section
      id="habit"
      className="section-lazy relative px-6 py-24"
      style={{ background: "radial-gradient(ellipse 500px 500px at 50% 100%, rgba(199,37,84,0.04) 0%, transparent 70%)" }}
    >
      <div className="relative mx-auto max-w-4xl text-center">
        <span className="reveal mb-4 inline-block text-sm font-semibold uppercase tracking-widest text-[#c72554]">
          The Science
        </span>

        {/* Giant 66 */}
        <div className="reveal-scale reveal-delay-1 font-heading bg-gradient-to-r from-[#c72554] to-[#ff4d7d] bg-clip-text text-transparent text-[clamp(120px,20vw,220px)] leading-none">
          66
        </div>

        <h2 className="reveal reveal-delay-1 font-heading text-[clamp(32px,5vw,56px)] tracking-[2px] text-[#a0a0a0] mb-8">
          DAYS TO BUILD A HABIT
        </h2>

        <p className="reveal reveal-delay-2 mx-auto max-w-2xl text-[17px] leading-[1.8] text-[#a0a0a0] mb-5">
          Research from University College London found it takes an average of 66 days for a new
          behavior to become automatic. That&apos;s just over two months of showing up before your
          daily mile stops feeling like effort and starts feeling like second nature.
        </p>

        <p className="reveal reveal-delay-3 mx-auto max-w-2xl text-[17px] leading-[1.8] text-[#a0a0a0] mb-12">
          The best part? Once it clicks, you don&apos;t have to think about it anymore. Your mile
          becomes as automatic as brushing your teeth. You just do it. And Mile A Day is designed to
          get you there — the streak, the accountability, the competition all keep you going until the
          habit takes hold.
        </p>

        {/* Three phases */}
        <div className="grid gap-4 md:grid-cols-3">
          <div className="reveal-scale glass-card rounded-2xl p-7 text-center">
            <div className="font-heading text-[42px] text-[#c72554] leading-none mb-1">
              1–21
            </div>
            <h3 className="font-heading text-[20px] tracking-[1px] text-[#f5f5f5] mb-2">
              THE GRIND
            </h3>
            <p className="text-[13px] leading-relaxed text-[#a0a0a0]">
              It&apos;s hard. You&apos;ll want to skip. But your streak is on the line, and that
              little number keeps you lacing up when the couch is calling.
            </p>
          </div>

          <div className="reveal-scale reveal-delay-1 glass-card rounded-2xl p-7 text-center">
            <div className="font-heading text-[42px] text-[#c72554] leading-none mb-1">
              22–66
            </div>
            <h3 className="font-heading text-[20px] tracking-[1px] text-[#f5f5f5] mb-2">
              THE SHIFT
            </h3>
            <p className="text-[13px] leading-relaxed text-[#a0a0a0]">
              It gets easier. You start looking forward to it. Your body expects it. Missing a day
              feels wrong, not tempting.
            </p>
          </div>

          <div className="reveal-scale reveal-delay-2 glass-card rounded-2xl p-7 text-center">
            <div className="font-heading text-[42px] text-[#c72554] leading-none mb-1">
              67+
            </div>
            <h3 className="font-heading text-[20px] tracking-[1px] text-[#f5f5f5] mb-2">
              AUTOMATIC
            </h3>
            <p className="text-[13px] leading-relaxed text-[#a0a0a0]">
              It&apos;s just what you do now. You don&apos;t negotiate with yourself. You lace up and
              go. Congratulations — you&apos;re a runner.
            </p>
          </div>
        </div>

        {/* Personal Records */}
        <div className="mt-16">
          <h3 className="reveal font-heading text-[24px] tracking-[2px] text-center text-[#a0a0a0] mb-6">
            TRACK YOUR PERSONAL BESTS
          </h3>
          <div className="grid gap-4 sm:grid-cols-3">
            {[
              { icon: Timer, label: "Fastest Mile", value: "5:12", color: "#33B34D" },
              { icon: Flame, label: "Longest Streak", value: "288 days", color: "#FF9900" },
              { icon: TrendingUp, label: "Most In A Day", value: "26.2 mi", color: "#D94059" },
            ].map((record, i) => (
              <div
                key={record.label}
                className={`reveal-scale reveal-delay-${i + 1} glass-card rounded-2xl p-5 text-center`}
              >
                <record.icon className="mx-auto mb-2 h-5 w-5" style={{ color: record.color }} />
                <div className="font-heading text-[32px] leading-none text-[#f5f5f5]">{record.value}</div>
                <div className="mt-1 text-xs font-semibold uppercase tracking-wider" style={{ color: record.color }}>
                  {record.label}
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  )
}
