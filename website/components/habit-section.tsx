import { Phone } from "./feature-panels";

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

/** Why one mile works: the 66-day habit research, beside the app's real milestone screen. */
export function HabitSection() {
  return (
    <section
      id="habit"
      className="scroll-mt-20 bg-[#f6f1ec] px-6 pt-24 text-[#1d1214]"
    >
      <div className="mx-auto max-w-6xl">
        <div className="grid gap-12 lg:grid-cols-[minmax(0,1.3fr)_minmax(0,1fr)] lg:gap-16">
          <div className="pb-4 lg:pb-24">
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
            <div className="mt-8 max-w-2xl space-y-5 text-[17px] leading-[1.75] text-[#4a3a3d]">
              <p>
                Research from University College London found it takes an
                average of 66 days for a new behavior to become automatic.
                That&apos;s just over two months of showing up before your daily
                mile stops feeling like effort and starts feeling like second
                nature.
              </p>
              <p>
                The best part? Once it clicks, you don&apos;t have to think
                about it anymore. Your mile becomes as automatic as brushing
                your teeth. You just do it. And Mile A Day is designed to get
                you there: the streak, the accountability and the competition
                all keep you going until the habit takes hold. Every milestone
                on the way gets its moment, and a medal to keep.
              </p>
            </div>

            <ol className="mt-10 space-y-3">
              {phases.map((phase) => (
                <li
                  key={phase.title}
                  className="grid grid-cols-[88px_minmax(0,1fr)] gap-4 rounded-3xl bg-white px-6 py-5"
                >
                  <div className="font-heading text-[28px] leading-none text-[#ec3047]">
                    {phase.days}
                  </div>
                  <div>
                    <h3 className="font-heading text-[20px] leading-none">
                      {phase.title}
                    </h3>
                    <p className="mt-2 text-[15px] leading-relaxed text-[#4a3a3d]">
                      {phase.body}
                    </p>
                  </div>
                </li>
              ))}
            </ol>
          </div>

          {/* The real 500-day celebration, rising from the bottom like the panels */}
          <div className="flex items-end justify-center">
            <Phone
              shot="07-milestone"
              alt="The 500 day streak celebration in Mile A Day"
            />
          </div>
        </div>
      </div>
    </section>
  );
}
