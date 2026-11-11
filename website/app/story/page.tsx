import type { CSSProperties } from "react";
import type { Metadata } from "next";
import { Navbar } from "@/components/navbar";
import { Footer } from "@/components/footer";
import { StorySection } from "@/components/story-section";
import { AppStoreButton } from "@/components/app-store-button";
import { SectionHeader } from "@/components/section-header";
import { InstagramPosts } from "@/components/instagram-posts";
import { FounderStreak } from "@/components/founder-streak";
import { RELEASES } from "@/lib/releases";
import { monthOfDay } from "@/lib/story";
import { ogVideos } from "../_og/video/meta";

const TITLE = "Our story";
const DESCRIPTION =
  "Two friends bet a Call of Duty skin on who'd miss a daily mile first. Nobody has. That bet became Mile A Day.";

export const metadata: Metadata = {
  title: TITLE,
  description: DESCRIPTION,
  alternates: { canonical: "/story" },
  // A page's openGraph replaces the root one, so restate it (the card image
  // comes from this segment's opengraph-image).
  openGraph: {
    title: `${TITLE} | Mile A Day`,
    description: DESCRIPTION,
    url: "/story",
    type: "website",
    siteName: "Mile A Day",
    videos: ogVideos("/og.mp4"),
  },
  twitter: {
    card: "summary_large_image",
    site: "@mileadayapp",
    title: `${TITLE} | Mile A Day`,
    description: DESCRIPTION,
  },
};

// The story so far, oldest first: the streak's own milestones (dated from the
// day of the bet) and every App Store release (lib/releases.ts).
function milestones() {
  const streak = [
    {
      when: "May 2025",
      title: "The bet",
      body: "Rob and Dave start walking or running a mile a day. Whoever misses first buys the other a Call of Duty skin.",
      day: 1,
    },
    {
      when: monthOfDay(100),
      title: "Day 100",
      body: "Still no skin bought. It stops being a bet and starts being a habit.",
      day: 100,
    },
    {
      when: monthOfDay(365),
      title: "A full year",
      body: "365 days without missing one. Time to build the app they wished they'd had.",
      day: 365,
    },
    {
      when: monthOfDay(500),
      title: "Day 500",
      body: "Half a thousand. The streak screen throws them a party.",
      day: 500,
    },
  ];
  const releases = [...RELEASES].reverse().map((r) => ({
    when: r.date,
    title:
      r.version === "1.0"
        ? "Mile A Day launches on the App Store"
        : `${r.version}: ${r.headline}`,
    body: r.summary,
    day: null as number | null,
  }));
  // Interleave by date: launch (June 2026) sits between day 365 and day 500.
  return [
    streak[0],
    streak[1],
    streak[2],
    ...releases.filter((r) => /June|July|August/.test(r.when)),
    streak[3],
    ...releases.filter((r) => !/June|July|August/.test(r.when)),
  ];
}

export default function StoryPage() {
  return (
    <main className="relative min-h-screen overflow-x-hidden bg-[#0e0809] text-white">
      <Navbar />

      {/* Header: the hero red, the live streak front and centre */}
      <header
        className="relative overflow-hidden px-6 pb-20 pt-36 text-center"
        style={{
          background: "linear-gradient(180deg, #ec3047 0%, #dc253b 100%)",
        }}
      >
        <div
          aria-hidden="true"
          className="pointer-events-none absolute bottom-[-25%] left-1/2 h-[140%] w-[70%] -translate-x-1/2 opacity-[0.09]"
          style={{
            background:
              "url(/images/app-store/flamey-silhouette.svg) no-repeat bottom center / contain",
          }}
        />
        <div className="relative mx-auto max-w-3xl">
          <p className="mad-rise text-[13px] font-semibold uppercase tracking-[0.18em] text-white/85">
            Our story
          </p>
          <h1
            className="mad-rise mt-3 font-heading text-[clamp(48px,8vw,96px)] leading-[0.92]"
            style={{ "--d": "80ms" } as CSSProperties}
          >
            Two friends.
            <br />
            One mile.
            <br />
            Every day.
          </h1>
          <p
            className="mad-rise mx-auto mt-6 max-w-xl text-[18px] leading-relaxed text-white/90"
            style={{ "--d": "160ms" } as CSSProperties}
          >
            It started as a bet over a Call of Duty skin. Neither of them has
            missed a day since.
          </p>
          <div
            className="mad-rise mt-9 inline-flex flex-col items-center rounded-3xl bg-black/20 px-8 py-5"
            style={{ "--d": "240ms" } as CSSProperties}
          >
            <span className="text-[13px] font-semibold uppercase tracking-[0.18em] text-white/80">
              🔥 Founders&apos; streak
            </span>
            <span className="mt-1 font-heading text-[clamp(56px,9vw,88px)] leading-none">
              <FounderStreak />
            </span>
            <span className="mt-1 text-[15px] font-semibold text-white/85">
              days and counting
            </span>
          </div>
        </div>
      </header>

      {/* The bet, as told on the home page */}
      <StorySection />

      {/* The road so far */}
      <section className="px-6 py-24">
        <div className="mx-auto max-w-4xl">
          <SectionHeader
            eyebrow="The road so far"
            title="From a bet to an app."
            body="The streak's milestones, and every update since Mile A Day reached the App Store."
          />
          <ol className="mt-14 border-l border-white/10">
            {milestones().map((m, i) => (
              <li
                key={`${m.when}-${m.title}`}
                data-reveal=""
                style={{ "--d": `${Math.min(i, 6) * 60}ms` } as CSSProperties}
                className="relative pb-10 pl-8 last:pb-0 sm:pl-10"
              >
                <span
                  aria-hidden="true"
                  className={`absolute -left-[7px] top-1.5 h-[13px] w-[13px] rounded-full ${m.day ? "bg-[#ec3047] ring-4 ring-[#ec3047]/25" : "bg-white/40"}`}
                />
                <p className="text-[13px] font-semibold uppercase tracking-[0.16em] text-[#ff5a6e]">
                  {m.when}
                </p>
                <h3 className="mt-1 font-heading text-[clamp(22px,3vw,30px)] leading-tight">
                  {m.title}
                </h3>
                <p className="mt-1.5 max-w-2xl text-[15px] leading-relaxed text-white/65">
                  {m.body}
                </p>
              </li>
            ))}
            <li className="relative pl-8 pt-2 sm:pl-10" data-reveal="">
              <span
                aria-hidden="true"
                className="absolute -left-[9px] top-3 flex h-[17px] w-[17px]"
              >
                <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-[#ec3047] opacity-60 motion-reduce:animate-none" />
                <span className="relative inline-flex h-[17px] w-[17px] rounded-full bg-[#ec3047]" />
              </span>
              <p className="text-[13px] font-semibold uppercase tracking-[0.16em] text-[#ff5a6e]">
                Today
              </p>
              <h3 className="mt-1 font-heading text-[clamp(22px,3vw,30px)] leading-tight">
                Day <FounderStreak /> and still going.
              </h3>
            </li>
          </ol>
        </div>
      </section>

      {/* Instagram */}
      <section className="bg-[#140b0e] px-6 py-24">
        <div className="mx-auto max-w-6xl">
          <SectionHeader
            eyebrow="On Instagram"
            title="Behind the streak."
            body="The bet, the builds, and a lot of Flamey."
            className="mb-12"
          />
          <InstagramPosts />
        </div>
      </section>

      {/* The ask */}
      <section
        className="relative overflow-hidden px-6 py-24 text-center"
        style={{
          background: "linear-gradient(180deg, #ec3047 0%, #dc253b 100%)",
        }}
      >
        <div className="relative mx-auto max-w-2xl" data-reveal="">
          <h2 className="font-heading text-[clamp(44px,7vw,80px)] leading-[0.95]">
            Start your own streak.
          </h2>
          <p className="mx-auto mt-5 max-w-md text-[18px] leading-relaxed text-white/90">
            One mile a day, walked or run. Free on iPhone and Apple Watch.
          </p>
          <div className="mt-8 flex justify-center">
            <AppStoreButton place="story" />
          </div>
        </div>
      </section>

      <Footer />
    </main>
  );
}
