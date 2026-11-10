"use client";

import Link from "next/link";
import { ShowcaseCarousel, type ShowcaseSlide } from "@/components/showcase-carousel";
import { useState } from "react";
import { ArrowRight, ChevronDown } from "lucide-react";
import { RELEASES, CURRENT_RELEASE, RELEASE_SHOWCASE } from "@/lib/releases";

// One release at a time, newest by default; the dropdown walks back through
// RELEASES and the screenshots and list follow it. Copy comes from
// lib/releases.ts (the site's copy of the app's WhatsNewCatalog) — ship a
// release by adding it there, and this section and /updates both move to it.
// Screenshots live in RELEASE_SHOWCASE: a headliner shows only once its real
// capture is set, until then it stays in the list below.

export function WhatsNewSection() {
  const [index, setIndex] = useState(0);
  const release = RELEASES[index];
  const isCurrent = release === CURRENT_RELEASE;
  const previous = RELEASES[index + 1];
  const shots = (RELEASE_SHOWCASE[release.version] ?? []).filter((s) => s.screenshot);
  const shown = new Set(shots.map((s) => s.title));
  const rest = release.features.filter((f) => !shown.has(f.title));
  const slides: ShowcaseSlide[] = shots.map((s) => ({
    ...s,
    screenshot: s.screenshot!,
    color: release.features.find((f) => f.title === s.title)?.color ?? "#c72554",
  }));

  return (
    <section id="whats-new" className="relative scroll-mt-20 bg-[#0e0809] px-6 py-24 text-white">
      <div className="relative mx-auto max-w-6xl">
        <div className="mb-14 max-w-2xl">
          <p className="mb-4 text-[13px] font-semibold uppercase tracking-[0.18em] text-white/60">
            {isCurrent ? "Just shipped" : "Shipped"} · {release.date}
          </p>
          <h2 className="font-heading text-[clamp(40px,6vw,72px)] leading-[0.95]">
            New in {release.version}
          </h2>
          <label className="relative mt-5 inline-flex items-center">
            <span className="sr-only">Show the release notes for</span>
            <select
              value={index}
              onChange={(e) => setIndex(Number(e.target.value))}
              className="cursor-pointer appearance-none rounded-full border border-white/[0.1] bg-white/[0.04] py-2 pl-4 pr-10 text-sm font-semibold text-[#f5f5f5] transition-colors hover:border-white/[0.2] focus:outline-none focus-visible:ring-2 focus-visible:ring-[#c72554]"
            >
              {RELEASES.map((r, i) => (
                <option key={r.version} value={i} className="bg-[#141414]">
                  {r.version} · {r.headline}{i === 0 ? " (latest)" : ""}
                </option>
              ))}
            </select>
            <ChevronDown className="pointer-events-none absolute right-3.5 h-4 w-4 text-[#a0a0a0]" />
          </label>
          <p className="mt-4 text-[17px] leading-relaxed text-white/70">
            {release.summary}
          </p>
        </div>

        {slides.length > 0 && (
          <div key={release.version} className="animate-in fade-in mb-14 duration-500">
            <ShowcaseCarousel slides={slides} />
          </div>
        )}

        <div>
          <h3 className="mb-6 text-[13px] font-semibold uppercase tracking-[0.18em] text-white/50">
            {shots.length > 0 ? `Also in ${release.version}` : `Everything in ${release.version}`}
          </h3>
          <div className="grid gap-x-10 gap-y-8 border-t border-white/10 pt-8 sm:grid-cols-2 lg:grid-cols-3">
            {rest.map((item) => (
              <div key={item.title} className="min-w-0">
                <p className="text-[17px] font-semibold">{item.title}</p>
                <p className="mt-1 text-[15px] leading-relaxed text-white/65">{item.desc}</p>
              </div>
            ))}
          </div>
        </div>

        {previous && (
        <div className="mt-12 flex flex-col justify-between gap-4 border-t border-white/10 pt-6 sm:flex-row sm:items-center">
          <p className="text-[15px] text-white/60">
            <span className="font-semibold text-white">
              Previously, in {previous.version}:
            </span>{" "}
            {previous.features
              .slice(0, 5)
              .map((f) => f.title)
              .join(", ")}{" "}
            and more.
          </p>
          <div className="flex shrink-0 items-center gap-5">
            <button
              type="button"
              onClick={() => setIndex(index + 1)}
              className="text-[15px] font-semibold text-white/70 transition-colors hover:text-white"
            >
              See {previous.version}
            </button>
            <Link
              href="/updates"
              className="inline-flex items-center gap-1.5 text-[15px] font-semibold text-white underline decoration-white/30 underline-offset-4 hover:decoration-white"
            >
              Every update <ArrowRight className="h-4 w-4" />
            </Link>
          </div>
        </div>
        )}
      </div>
    </section>
  );
}
