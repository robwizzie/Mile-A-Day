export function HabitSection() {
  return (
    <section id="habit" className="relative px-6 py-24">
      <div className="pointer-events-none absolute inset-0">
        <div className="absolute bottom-0 left-1/2 h-[500px] w-[500px] -translate-x-1/2 rounded-full bg-[#c72554] opacity-[0.04] blur-[150px]" />
      </div>
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
      </div>
    </section>
  )
}
