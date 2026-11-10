import { PanelBand } from "./feature-panels";

// The five modes, named and described as the app's CompetitionType does
// (Models/Competition.swift: tagline + howItWorks, the copy the Compete tab's
// mode gallery shows). Plain text beside the real screenshot: the site shows
// the app, it never redraws it.
const modes = [
  {
    name: "Streaks",
    tagline: "Last one standing.",
    description:
      "Everyone has the same daily goal. Miss a day and you spend a life. Run out of lives and you're out.",
  },
  {
    name: "Apex",
    tagline: "Most miles wins.",
    description:
      "Every counted mile adds to your total. Highest total when the clock runs out wins.",
  },
  {
    name: "Targets",
    tagline: "Hit your goal, bank a point.",
    description:
      "A goal is set for each day. Everyone who hits it banks a point. You're racing the goal, not each other.",
  },
  {
    name: "Clash",
    tagline: "Win the day, take the point.",
    description:
      "Whoever goes furthest that day takes the point. First to the target score wins.",
  },
  {
    name: "Race",
    tagline: "First to the finish line.",
    description:
      "One distance is the finish line. First person there wins. No clock, no daily goals.",
  },
];

/** Competitions, as one more screenshot panel: the real final standings, and the five modes in words. */
export function CompetitionsSection() {
  return (
    <PanelBand
      flip={false}
      panel={{
        id: "competitions",
        eyebrow: "Competitions",
        title: ["Go the extra", "mile."],
        body: "Five modes, solo or in teams, scored on the miles your phone or watch actually tracked.",
        shot: "08-comp",
        alt: "Final standings of a Mile A Day team competition",
        from: "#9452ec",
        to: "#8341db",
      }}
    >
      <dl className="mt-8 max-w-lg divide-y divide-white/20 border-y border-white/20">
        {modes.map((mode) => (
          <div key={mode.name} className="py-3.5">
            <dt className="text-[16px] font-semibold">
              {mode.name}
              <span className="font-normal text-white/80">
                {" "}
                · {mode.tagline}
              </span>
            </dt>
            <dd className="mt-1 text-[14px] leading-relaxed text-white/75">
              {mode.description}
            </dd>
          </div>
        ))}
      </dl>
    </PanelBand>
  );
}
