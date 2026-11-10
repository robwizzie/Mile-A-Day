const phases = [
  {
    days: "1–21",
    title: "The grind",
    body: "It's hard. You'll want to skip. But your streak is on the line, and that little number keeps you lacing up when the couch is calling.",
  },
  {
    days: "22–66",
    title: "The shift",
    body: "It gets easier. You start looking forward to it. Your body expects it. Missing a day feels wrong, not tempting.",
  },
  {
    days: "67+",
    title: "Automatic",
    body: "It's just what you do now. You don't negotiate with yourself. You lace up and go. Congratulations, you're a walker. Or a runner. Either counts.",
  },
];

const records = [
  { label: "Fastest mile", value: "5:12", color: "#2bc189" },
  { label: "Longest streak", value: "511 days", color: "#f7aa2c" },
  { label: "Most in one day", value: "26.2 mi", color: "#9452ec" },
];

/** Why one mile works: the 66-day habit research, on the warm light band. */
export function HabitSection() {
  return (
    <section
      id="habit"
      className="scroll-mt-20 bg-[#f6f1ec] px-6 py-24 text-[#1d1214]"
    >
      <div className="mx-auto max-w-6xl">
        <div className="grid items-end gap-10 lg:grid-cols-[auto_minmax(0,1fr)] lg:gap-16">
          <div>
            <p className="mb-2 text-[13px] font-semibold uppercase tracking-[0.18em] text-[#c72554]">
              The science
            </p>
            <h2 className="font-heading leading-[0.9]">
              <span className="block text-[clamp(120px,18vw,220px)] text-[#ec3047]">
                66
              </span>
              <span className="block text-[clamp(32px,4vw,52px)]">
                days to build a habit.
              </span>
            </h2>
          </div>
          <div className="max-w-2xl space-y-5 text-[17px] leading-[1.75] text-[#4a3a3d] lg:pb-2">
            <p>
              Research from University College London found it takes an average
              of 66 days for a new behavior to become automatic. That&apos;s
              just over two months of showing up before your daily mile stops
              feeling like effort and starts feeling like second nature.
            </p>
            <p>
              The best part? Once it clicks, you don&apos;t have to think about
              it anymore. Your mile becomes as automatic as brushing your teeth.
              You just do it. And Mile A Day is designed to get you there: the
              streak, the accountability and the competition all keep you going
              until the habit takes hold.
            </p>
          </div>
        </div>

        <ol className="mt-14 grid gap-4 md:grid-cols-3">
          {phases.map((phase) => (
            <li key={phase.title} className="rounded-3xl bg-white px-7 py-8">
              <div className="font-heading text-[40px] leading-none text-[#ec3047]">
                {phase.days}
              </div>
              <h3 className="mt-4 font-heading text-[24px]">{phase.title}</h3>
              <p className="mt-2 text-[15px] leading-relaxed text-[#4a3a3d]">
                {phase.body}
              </p>
            </li>
          ))}
        </ol>

        <div className="mt-14">
          <h3 className="font-heading text-[26px]">
            Track your personal bests.
          </h3>
          <div className="mt-5 grid gap-4 sm:grid-cols-3">
            {records.map((record) => (
              <div
                key={record.label}
                className="rounded-3xl px-6 py-6 text-white"
                style={{ background: record.color }}
              >
                <div className="text-[13px] font-semibold uppercase tracking-[0.14em] text-white/85">
                  {record.label}
                </div>
                <div className="mt-2 font-heading text-[40px] leading-none">
                  {record.value}
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
