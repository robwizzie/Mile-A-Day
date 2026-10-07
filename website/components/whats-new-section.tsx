"use client";

import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { RELEASES, CURRENT_RELEASE, releaseAnchor } from "@/lib/releases";
import {
  ClosetMockup,
  RouteCardMockup,
  WeeklyRecapMockup,
} from "@/components/feature-mockups";

// The current release, shown off. Copy comes from lib/releases.ts (the site's
// copy of the app's WhatsNewCatalog) — ship a release by adding it there, and
// this section and /updates both move to it.

// The three headliners get a drawn screen each; every other feature of the
// release is listed under them. Titles must match lib/releases.ts.
const SHOWCASE = [
  {
    title: "Flamey's Closet",
    caption: "Flamey's Closet",
    blurb:
      "Every medal unlocks something for Flamey to wear. Name him, dress him, save the outfits you love.",
    Mockup: ClosetMockup,
  },
  {
    title: "Your Flamey, on your walks",
    caption: "Your walks, drawn",
    blurb:
      "Route Art on the feed, Flamey running beside you, and a Flyover of the whole walk — with your start and finish kept private.",
    Mockup: RouteCardMockup,
  },
  {
    title: "Weekly Recap",
    caption: "Weekly Recap",
    blurb:
      "Every Saturday evening: your miles, your best day, and how your friends did.",
    Mockup: WeeklyRecapMockup,
  },
];

const SHOWN = new Set([
  "Flamey's Closet",
  "Your Flamey, on your walks",
  "Weekly Recap",
]);

export function WhatsNewSection() {
  const release = CURRENT_RELEASE;
  const previous = RELEASES[1];
  const rest = release.features.filter((f) => !SHOWN.has(f.title));

  return (
    <section
      id="whats-new"
      className="section-lazy relative scroll-mt-20 px-6 py-24"
    >
      <div
        className="pointer-events-none absolute inset-x-0 top-0 h-[520px]"
        style={{
          background:
            "radial-gradient(ellipse 700px 380px at 50% 0%, rgba(255,138,61,0.07), transparent 70%)",
        }}
      />
      <div className="relative mx-auto max-w-6xl">
        <div className="mx-auto mb-14 max-w-2xl text-center">
          <span className="reveal mb-4 inline-flex items-center gap-2 rounded-full border border-[#c72554]/30 bg-[#c72554]/10 px-3.5 py-1.5 text-xs font-semibold uppercase tracking-widest text-[#ff4d7d]">
            Just shipped · {release.date}
          </span>
          <h2 className="reveal reveal-delay-1 font-heading text-[clamp(40px,6vw,72px)] leading-none tracking-[-1px] text-[#f5f5f5]">
            NEW IN <span className="text-[#c72554]">{release.version}</span>
          </h2>
          <p className="reveal reveal-delay-2 mt-4 text-base leading-relaxed text-[#a0a0a0]">
            {release.summary}
          </p>
        </div>

        {/* Subgrid rows: the three screens share one height and the captions
            start on one line, whatever each caption's length. */}
        <div className="grid gap-x-6 gap-y-10 md:grid-cols-3 md:grid-rows-[1fr_auto] md:gap-y-0">
          {SHOWCASE.map(({ caption, blurb, Mockup }, i) => (
            <div
              key={caption}
              className={`reveal-scale reveal-delay-${i + 1} flex flex-col md:row-span-2 md:grid md:grid-rows-subgrid`}
            >
              <div className="glass-card flex-1 rounded-[30px] p-2.5">
                <Mockup />
              </div>
              <div>
                <h3 className="font-heading mt-5 text-[24px] uppercase tracking-[1px] text-[#f5f5f5]">
                  {caption}
                </h3>
                <p className="mt-1.5 text-sm leading-relaxed text-[#a0a0a0]">
                  {blurb}
                </p>
              </div>
            </div>
          ))}
        </div>

        <div className="reveal reveal-delay-2 glass-card mt-14 rounded-2xl p-6 sm:p-8">
          <h3 className="mb-6 text-xs font-semibold uppercase tracking-widest text-[#707070]">
            Also in {release.version}
          </h3>
          <div className="grid gap-x-8 gap-y-6 sm:grid-cols-2 lg:grid-cols-4">
            {rest.map((item) => (
              <div key={item.title} className="flex items-start gap-3.5">
                <div
                  className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl"
                  style={{ background: `${item.color}1f` }}
                >
                  <item.icon
                    className="h-5 w-5"
                    style={{ color: item.color }}
                  />
                </div>
                <div className="min-w-0">
                  <p className="text-[15px] font-semibold text-[#f5f5f5]">
                    {item.title}
                  </p>
                  <p className="mt-0.5 text-sm leading-relaxed text-[#a0a0a0]">
                    {item.desc}
                  </p>
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="reveal reveal-delay-3 mt-6 flex flex-col items-center justify-between gap-4 rounded-2xl border border-white/[0.06] px-6 py-5 sm:flex-row">
          <p className="text-center text-sm text-[#a0a0a0] sm:text-left">
            <span className="font-semibold text-[#f5f5f5]">
              Previously, in {previous.version}:
            </span>{" "}
            {previous.features
              .slice(0, 5)
              .map((f) => f.title)
              .join(" · ")}{" "}
            and more.
          </p>
          <div className="flex shrink-0 items-center gap-5">
            <Link
              href={`/updates#${releaseAnchor(previous.version)}`}
              className="text-sm font-semibold text-[#a0a0a0] transition-colors hover:text-[#f5f5f5]"
            >
              {previous.version} notes
            </Link>
            <Link
              href="/updates"
              className="inline-flex items-center gap-1.5 text-sm font-semibold text-[#ff4d7d] transition-colors hover:text-[#ff7a9c]"
            >
              Every update <ArrowRight className="h-4 w-4" />
            </Link>
          </div>
        </div>
      </div>
    </section>
  );
}
