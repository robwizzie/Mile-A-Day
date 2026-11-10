import Image from "next/image";
import type { ReactNode } from "react";

/**
 * The App Store screenshots, as the site. Each panel is one screenshot's
 * story in its own colour: a small eyebrow, a heavy two-line headline, one
 * plain sentence, and the real phone (cut out of the App Store image, so the
 * site always shows exactly what the store shows) rising from the bottom.
 * Copy and colours mirror marketing/app-store/<version>/ — change them there
 * and here together.
 */
export type Panel = {
  id?: string;
  eyebrow: string;
  title: [string, string];
  body: string;
  /** public/images/app-store/<shot>.webp */
  shot: string;
  alt: string;
  /** Top and bottom of the panel's colour, sampled from the screenshot. */
  from: string;
  to: string;
};

export const PANELS: Panel[] = [
  {
    eyebrow: "Run to unlock",
    title: ["Earn your", "feed."],
    body: "Friends' stories and photos unlock once you walk or run your mile. No scrolling your way out of it.",
    shot: "02-unlock",
    alt: "The Feed, with friends' stories locked until today's mile is done",
    from: "#6656ea",
    to: "#5646d3",
  },
  {
    eyebrow: "Route flyover",
    title: ["Relive every", "route."],
    body: "Replay your walk or run from above, step by step, with everyone who came along.",
    shot: "03-flyover",
    alt: "A flyover replay of a walk over a satellite map",
    from: "#3e82f4",
    to: "#3171e2",
  },
  {
    eyebrow: "Friends",
    title: ["Keep each other", "going."],
    body: "See who's out now, nudge friends who haven't gone yet, and donate a mile to save a streak.",
    shot: "04-friends",
    alt: "The Friends tab with nudges and Donate a Mile",
    from: "#16aeb1",
    to: "#0e9a9c",
  },
  {
    eyebrow: "Flamey's Closet",
    title: ["Dress up", "your Flamey."],
    body: "Name him, dress him up, and unlock new looks with every medal you earn.",
    shot: "05-closet",
    alt: "Flamey's Closet with outfits and flame colors",
    from: "#222a40",
    to: "#192033",
  },
  {
    eyebrow: "Buddy walks",
    title: ["Never walk", "alone."],
    body: "Walk with friends from anywhere, and see each other's routes on one map when you both share.",
    shot: "06-buddy",
    alt: "A buddy walk post with four routes on one map",
    from: "#ff7555",
    to: "#f16446",
  },
  {
    eyebrow: "Milestones",
    title: ["Celebrate every", "milestone."],
    body: "Day 100, 365, 500. Each one gets its moment, and a medal to keep.",
    shot: "07-milestone",
    alt: "The 500 day streak celebration",
    from: "#f7aa2c",
    to: "#e79718",
  },
  {
    id: "competitions",
    eyebrow: "Competitions",
    title: ["Compete with", "your crew."],
    body: "Team comps, head-to-head days, clashes and leaderboards, scored on the miles your phone or watch actually tracked.",
    shot: "08-comp",
    alt: "Final standings of a team competition",
    from: "#9452ec",
    to: "#8341db",
  },
  {
    eyebrow: "Streak tokens",
    title: ["Miss a day?", "Stay on track."],
    body: "Tokens protect your streak when life happens. Earn them by going the extra mile.",
    shot: "09-tokens",
    alt: "Streak Tokens: Double Down, Streak Save and Streak Assist",
    from: "#2bc189",
    to: "#20ae78",
  },
];

/** The faint Flamey the screenshots stand the phone in front of. */
function Silhouette({ side }: { side: "left" | "right" }) {
  return (
    <div
      aria-hidden="true"
      className={`pointer-events-none absolute bottom-[-8%] h-[115%] w-[70%] opacity-[0.09] ${
        side === "right" ? "right-[-12%]" : "left-[-12%]"
      }`}
      style={{
        background:
          "url(/images/app-store/flamey-silhouette.svg) no-repeat bottom center / contain",
      }}
    />
  );
}

export function Phone({
  shot,
  alt,
  priority = false,
}: {
  shot: string;
  alt: string;
  priority?: boolean;
}) {
  return (
    <Image
      src={`/images/app-store/${shot}.webp`}
      alt={alt}
      width={1070}
      height={2053}
      sizes="(min-width: 768px) 380px, 78vw"
      unoptimized
      priority={priority}
      className="relative block h-auto w-[78vw] max-w-[380px] drop-shadow-[0_30px_40px_rgba(0,0,0,0.25)]"
    />
  );
}

/** One colour panel: words on one side, the phone rising from the bottom on the other. */
export function PanelBand({
  panel,
  flip = false,
  heading: Heading = "h2",
  children,
  priority = false,
  hero = false,
}: {
  panel: Panel;
  flip?: boolean;
  heading?: "h1" | "h2";
  /** Extra content under the sentence (the hero's button). */
  children?: ReactNode;
  priority?: boolean;
  /** The top panel: clears the fixed navbar and gives the words more room. */
  hero?: boolean;
}) {
  return (
    <section
      id={panel.id}
      className="relative overflow-hidden text-white"
      style={{
        background: `linear-gradient(180deg, ${panel.from} 0%, ${panel.to} 100%)`,
      }}
    >
      <Silhouette side={flip ? "left" : "right"} />
      <div
        className={`relative mx-auto flex max-w-6xl flex-col gap-10 px-6 md:min-h-[640px] md:flex-row md:items-stretch md:gap-14 ${hero ? "pt-28 md:pt-0" : "pt-20 md:pt-0"} ${
          flip ? "md:flex-row-reverse" : ""
        }`}
      >
        <div className={`flex flex-col justify-center md:py-24 ${hero ? "md:flex-[1.35] md:pt-36" : "flex-1"}`}>
          <p className="mb-4 text-[13px] font-semibold uppercase tracking-[0.18em] text-white/85">
            {panel.eyebrow}
          </p>
          <Heading className="font-heading text-[clamp(40px,4.8vw,68px)] leading-[0.95] text-white">
            {panel.title[0]}
            <br />
            {panel.title[1]}
          </Heading>
          <p className="mt-5 max-w-md text-[18px] leading-relaxed text-white/90 md:text-[20px]">
            {panel.body}
          </p>
          {children}
        </div>
        <div className={`flex flex-1 items-end justify-center ${hero ? "md:pt-32" : "md:pt-20"}`}>
          <Phone shot={panel.shot} alt={panel.alt} priority={priority} />
        </div>
      </div>
    </section>
  );
}

export function FeaturePanels() {
  return (
    <div id="features">
      {PANELS.map((panel, i) => (
        <PanelBand key={panel.shot} panel={panel} flip={i % 2 === 0} />
      ))}
    </div>
  );
}
