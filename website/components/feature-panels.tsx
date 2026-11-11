import Image from "next/image";
import type { CSSProperties, ReactNode } from "react";

/**
 * The headline features, told the way the App Store screenshots tell them
 * (a curated few, not every screenshot). Each panel is one feature in its
 * screenshot's colour: a small eyebrow, a heavy two-line headline, one
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
    eyebrow: "Friends",
    title: ["Keep each other", "going."],
    body: "See who's out now, nudge friends who haven't gone yet, and donate a mile to save a streak.",
    shot: "04-friends",
    alt: "The Friends tab with nudges and Donate a Mile",
    from: "#16aeb1",
    to: "#0e9a9c",
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
    eyebrow: "Flamey's Closet",
    title: ["Dress up", "your Flamey."],
    body: "Name him, dress him up, and unlock new looks with every medal you earn.",
    shot: "05-closet",
    alt: "Flamey's Closet with outfits and flame colors",
    from: "#222a40",
    to: "#192033",
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
  fill = false,
}: {
  panel: Panel;
  flip?: boolean;
  heading?: "h1" | "h2";
  /** Extra content under the sentence (the hero's button). */
  children?: ReactNode;
  priority?: boolean;
  /** The top panel: clears the fixed navbar and gives the words more room. */
  hero?: boolean;
  /** A carousel slide: fill the slide's height (the tallest slide sets it)
   *  and clear the tab row drawn over the top. */
  fill?: boolean;
}) {
  return (
    <section
      id={fill ? undefined : panel.id}
      className={`relative overflow-hidden text-white ${fill ? "h-full" : ""}`}
      style={{
        background: `linear-gradient(180deg, ${panel.from} 0%, ${panel.to} 100%)`,
      }}
    >
      <Silhouette side={flip ? "left" : "right"} />
      <div
        className={`relative mx-auto flex max-w-6xl flex-col gap-10 px-6 md:min-h-[640px] md:flex-row md:items-stretch md:gap-14 ${hero ? "pt-28 md:pt-0" : fill ? "h-full pt-24 md:pt-6" : "pt-20 md:pt-0"} ${
          flip ? "md:flex-row-reverse" : ""
        }`}
      >
        <div className={`flex flex-col justify-center md:py-24 ${hero ? "md:flex-[1.35] md:pt-36" : "flex-1"}`}>
          {/* The hero plays once on load; every other panel reveals on scroll. */}
          <p
            className={`mb-4 text-[13px] font-semibold uppercase tracking-[0.18em] text-white/85 ${hero ? "mad-rise" : ""}`}
            {...(hero ? {} : { "data-reveal": "" })}
          >
            {panel.eyebrow}
          </p>
          <Heading
            className={`font-heading text-[40px] leading-[0.95] md:text-[clamp(34px,4.6vw,68px)] text-white ${hero ? "mad-rise" : ""}`}
            style={{ "--d": "90ms" } as CSSProperties}
            {...(hero ? {} : { "data-reveal": "" })}
          >
            {panel.title[0]}
            <br />
            {panel.title[1]}
          </Heading>
          <div
            className={hero ? "mad-rise" : ""}
            style={{ "--d": "180ms" } as CSSProperties}
            {...(hero ? {} : { "data-reveal": "" })}
          >
            <p className="mt-5 max-w-md text-[18px] leading-relaxed text-white/90 md:text-[20px]">
              {panel.body}
            </p>
            {children}
          </div>
        </div>
        <div className={`flex flex-1 items-end justify-center ${hero ? "md:pt-32" : "md:pt-20"}`}>
          <div
            className={hero ? "mad-phone-in -mb-12" : ""}
            style={{ "--d": "120ms" } as CSSProperties}
            {...(hero ? {} : { "data-reveal": "phone" })}
          >
            {/* The hero phone floats, so it runs 48px past the band's bottom
                edge (clipped by the section): the cut end of the screenshot
                never shows as it bobs up. */}
            <div className={hero ? "mad-float" : ""}>
              <Phone shot={panel.shot} alt={panel.alt} priority={priority} />
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

/** The feature panels as carousel slides (they alternate sides). */
export function featureSlides() {
  return PANELS.map((panel, i) => ({
    key: panel.shot,
    label: panel.eyebrow,
    color: panel.from,
    node: <PanelBand panel={panel} flip={i % 2 === 0} fill />,
  }));
}
