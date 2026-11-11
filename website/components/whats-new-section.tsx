"use client";

import Link from "next/link";
import {
  ShowcaseCarousel,
  type ShowcaseSlide,
} from "@/components/showcase-carousel";
import { useState } from "react";
import { ArrowRight, ChevronDown } from "lucide-react";
import {
  RELEASES,
  CURRENT_RELEASE,
  RELEASE_SHOWCASE,
} from "@/lib/releases";
import { ReleaseFeatureList } from "./release-feature-list";

// One release at a time, newest by default; the dropdown walks back through
// RELEASES and the screenshots and list follow it. Copy comes from
// lib/releases.ts (the site's copy of the app's WhatsNewCatalog): ship a
// release by adding it there, and this section and /updates both move to it.
// Screenshots live in RELEASE_SHOWCASE: a headliner shows only once its real
// capture is set, until then it stays in the list.

export function WhatsNewSection() {
  const [index, setIndex] = useState(0);
  const release = RELEASES[index];
  const isCurrent = release === CURRENT_RELEASE;
  const previous = RELEASES[index + 1];
  const shots = (RELEASE_SHOWCASE[release.version] ?? []).filter(
    (s) => s.screenshot,
  );
  const shown = new Set(shots.map((s) => s.title));
  const rest = release.features.filter((f) => !shown.has(f.title));
  const slides: ShowcaseSlide[] = shots.map((s) => ({
    ...s,
    screenshot: s.screenshot!,
    color:
      release.features.find((f) => f.title === s.title)?.color ?? "#c72554",
  }));

  return (
    <section
      id="whats-new"
      className="relative scroll-mt-20 bg-[#140b0e] px-6 py-24 text-white"
    >
      <div className="mx-auto grid max-w-6xl gap-12 lg:grid-cols-[minmax(0,5fr)_minmax(0,7fr)] lg:gap-16">
        {/* The release, on the left; it stays put while the list scrolls past */}
        <div data-reveal="" className="lg:sticky lg:top-28 lg:self-start">
          <p className="mb-4 text-[13px] font-semibold uppercase tracking-[0.18em] text-[#ff5a6e]">
            {isCurrent ? "Just shipped" : "Shipped"} · {release.date}
          </p>
          <h2 className="font-heading text-[clamp(40px,5.5vw,72px)] leading-[0.95]">
            New in {release.version}.
          </h2>
          <p className="mt-5 text-[20px] font-semibold leading-snug">
            {release.headline}
          </p>
          <p className="mt-3 text-[17px] leading-relaxed text-white/70">
            {release.summary}
          </p>

          <div className="mt-7 flex flex-wrap items-center gap-x-5 gap-y-3">
            <label className="relative inline-flex items-center">
              <span className="sr-only">Show the release notes for</span>
              <select
                value={index}
                onChange={(e) => setIndex(Number(e.target.value))}
                className="cursor-pointer appearance-none rounded-full bg-white/[0.08] py-2.5 pl-4 pr-10 text-sm font-semibold text-white transition-colors hover:bg-white/[0.12] focus:outline-none focus-visible:ring-2 focus-visible:ring-[#ec3047]"
              >
                {RELEASES.map((r, i) => (
                  <option key={r.version} value={i} className="bg-[#140b0e]">
                    {r.version} · {r.headline}
                    {i === 0 ? " (latest)" : ""}
                  </option>
                ))}
              </select>
              <ChevronDown className="pointer-events-none absolute right-3.5 h-4 w-4 text-white/60" />
            </label>
            <Link
              href="/updates"
              data-track="whats_new_all"
              className="inline-flex items-center gap-1.5 text-[15px] font-semibold text-white underline decoration-white/30 underline-offset-4 hover:decoration-white"
            >
              Every update <ArrowRight className="h-4 w-4" />
            </Link>
          </div>
        </div>

        {/* key: switching release replays the reveal */}
        <div key={release.version} className="min-w-0">
          {slides.length > 0 && (
            <div className="animate-in fade-in mb-12 duration-500">
              <ShowcaseCarousel slides={slides} />
            </div>
          )}
          {slides.length > 0 && rest.length > 0 && (
            <h3 className="mb-6 text-[13px] font-semibold uppercase tracking-[0.18em] text-white/50">
              Also in {release.version}
            </h3>
          )}
          <ReleaseFeatureList features={rest} />

          {previous && (
            <div className="mt-12 flex flex-col justify-between gap-3 rounded-3xl bg-white/[0.04] p-5 sm:flex-row sm:items-center">
              <p className="text-[15px] text-white/60">
                <span className="font-semibold text-white">
                  Previously, in {previous.version}:
                </span>{" "}
                {previous.features
                  .slice(0, 3)
                  .map((f) => f.title)
                  .join(", ")}{" "}
                and more.
              </p>
              <button
                type="button"
                onClick={() => setIndex(index + 1)}
                data-track="whats_new_previous"
                className="lift shrink-0 rounded-full bg-white/[0.08] px-4 py-2 text-[14px] font-semibold text-white hover:bg-white/[0.12]"
              >
                See {previous.version}
              </button>
            </div>
          )}
        </div>
      </div>
    </section>
  );
}
