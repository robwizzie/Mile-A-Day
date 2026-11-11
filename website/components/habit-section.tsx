"use client";

import { useEffect, useState, type CSSProperties } from "react";
import { Phone } from "./feature-panels";
import { useInView } from "./reveal";

/**
 * The three stretches of the 66 days, each a run of dots on one track that
 * lights up in order (and deepens in colour as the habit sets) once it's on
 * screen. Day 67+ trails off: it doesn't end.
 */
const phases = [
  {
    days: "Days 1–21",
    title: "The grind",
    body: "It's hard. You'll want to skip. But your streak is on the line, and that little number keeps you lacing up when the couch is calling.",
    dots: 21,
    color: "#f59aa5",
  },
  {
    days: "Days 22–66",
    title: "The shift",
    body: "It gets easier. You start looking forward to it. Your body expects it. Missing a day feels wrong, not tempting.",
    dots: 45,
    color: "#ec3047",
  },
  {
    days: "Day 67+",
    title: "Automatic",
    body: "It's just what you do now. You don't negotiate with yourself. You lace up and go. Congratulations, you're a walker. Or a runner. Either counts.",
    dots: 14,
    color: "#a3132b",
    trailing: true,
  },
];

const DOT_STEP_MS = 22;

/** 0 → 66, eased, once the number is on screen. */
function useCountTo(target: number, start: boolean) {
  const [value, setValue] = useState(start ? 0 : target);
  useEffect(() => {
    if (!start) return;
    let frame = 0;
    const t0 = performance.now();
    const tick = (now: number) => {
      const t = Math.min((now - t0) / 1400, 1);
      setValue(Math.round(target * (1 - Math.pow(1 - t, 3))));
      if (t < 1) frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [start, target]);
  return value;
}

/** Why one mile works: the 66-day habit research, beside the app's real milestone screen. */
export function HabitSection() {
  const [numberRef, inView] = useInView<HTMLSpanElement>(0.6);
  const count = useCountTo(66, inView);

  let dayIndex = 0;

  return (
    <section
      id="habit"
      className="scroll-mt-20 overflow-hidden bg-[#f6f1ec] px-6 pt-24 text-[#1d1214]"
    >
      <div className="mx-auto max-w-6xl">
        {/* Row 1: the number and the research, side by side */}
        <div className="grid items-end gap-8 lg:grid-cols-[auto_minmax(0,1fr)] lg:gap-16">
          <div data-reveal="">
            <p className="mb-2 text-[13px] font-semibold uppercase tracking-[0.18em] text-[#c72554]">
              The science
            </p>
            <h2 className="font-heading leading-[0.88]">
              <span
                ref={numberRef}
                className="block text-[clamp(128px,19vw,230px)] tabular-nums text-[#ec3047]"
                aria-label="66"
              >
                {inView ? count : 66}
              </span>
              <span className="block text-[clamp(32px,4vw,52px)]">
                days to build a habit.
              </span>
            </h2>
          </div>

          <div
            data-reveal=""
            style={{ "--d": "100ms" } as CSSProperties}
            className="max-w-2xl space-y-5 text-[17px] leading-[1.75] text-[#4a3a3d] lg:pb-3"
          >
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

        {/* Row 2: the track beside the real milestone screen, which rises from the band's bottom */}
        <div className="mt-12 grid gap-12 lg:grid-cols-[minmax(0,1.35fr)_minmax(0,1fr)] lg:items-end lg:gap-16">
          {/* The track: one dot a day */}
          <ol
            data-reveal=""
            className="habit-track rounded-[28px] bg-white p-6 sm:p-8 lg:mb-24"
          >
            {phases.map((phase, p) => (
              <li
                key={phase.title}
                className={
                  p > 0 ? "mt-7 border-t border-[#1d1214]/[0.07] pt-7" : ""
                }
              >
                <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                  <h3 className="font-heading text-[22px] leading-none">
                    {phase.title}
                  </h3>
                  <span
                    className="text-[13px] font-semibold uppercase tracking-[0.14em]"
                    style={{
                      color:
                        phase.color === "#f59aa5" ? "#d9566a" : phase.color,
                    }}
                  >
                    {phase.days}
                  </span>
                </div>
                <div
                  className="mt-3 flex flex-wrap gap-[5px]"
                  aria-hidden="true"
                >
                  {Array.from({ length: phase.dots }, (_, i) => {
                    const d = dayIndex++ * DOT_STEP_MS;
                    const fade = phase.trailing ? 1 - i / phase.dots : 1;
                    return (
                      <span
                        key={i}
                        className="habit-dot h-[11px] w-[11px] rounded-full"
                        style={
                          {
                            "--dot": phase.color,
                            "--d": `${d}ms`,
                            opacity: fade,
                          } as CSSProperties
                        }
                      />
                    );
                  })}
                </div>
                <p className="mt-3 max-w-xl text-[15px] leading-relaxed text-[#4a3a3d]">
                  {phase.body}
                </p>
              </li>
            ))}
          </ol>

          {/* The real 500-day celebration, climbing out of the bottom of the band */}
          <div className="flex items-end justify-center">
          <div data-reveal="phone">
            <Phone
              shot="07-milestone"
              alt="The 500 day streak celebration in Mile A Day"
            />
          </div>
          </div>
        </div>
      </div>
    </section>
  );
}
