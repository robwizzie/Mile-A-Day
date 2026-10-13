"use client";

import Link from "next/link";
import Image from "next/image";
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
            {isCurrent ? "Just shipped" : "Shipped"} · {release.date}
          </span>
          <h2 className="reveal reveal-delay-1 font-heading text-[clamp(40px,6vw,72px)] leading-none tracking-[-1px] text-[#f5f5f5]">
            NEW IN <span className="text-[#c72554]">{release.version}</span>
          </h2>
          <label className="reveal reveal-delay-1 relative mt-5 inline-flex items-center">
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
          <p className="reveal reveal-delay-2 mt-4 text-base leading-relaxed text-[#a0a0a0]">
            {release.summary}
          </p>
        </div>

        {shots.length > 0 && (
          <div key={release.version} className="mb-14 grid gap-x-8 gap-y-12 sm:grid-cols-2 md:grid-cols-3">
            {shots.map((shot) => (
              <div key={shot.title} className={`animate-in fade-in duration-500 flex flex-col items-center text-center`}>
                <div className="phone-mockup w-full max-w-[280px] overflow-hidden p-2.5">
                  <Image
                    src={shot.screenshot!}
                    alt={`${shot.caption} in the Mile A Day app`}
                    width={776}
                    height={1680}
                    sizes="280px"
                    className="w-full rounded-[30px]"
                  />
                </div>
                <h3 className="font-heading mt-6 text-[24px] uppercase tracking-[1px] text-[#f5f5f5]">{shot.caption}</h3>
                <p className="mt-1.5 max-w-xs text-sm leading-relaxed text-[#a0a0a0]">{shot.blurb}</p>
              </div>
            ))}
          </div>
        )}

        <div className="reveal reveal-delay-2 glass-card rounded-2xl p-6 sm:p-8">
          <h3 className="mb-6 text-xs font-semibold uppercase tracking-widest text-[#707070]">
            {shots.length > 0 ? `Also in ${release.version}` : `Everything in ${release.version}`}
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

        {previous && (
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
            <button
              type="button"
              onClick={() => setIndex(index + 1)}
              className="text-sm font-semibold text-[#a0a0a0] transition-colors hover:text-[#f5f5f5]"
            >
              See {previous.version}
            </button>
            <Link
              href="/updates"
              className="inline-flex items-center gap-1.5 text-sm font-semibold text-[#ff4d7d] transition-colors hover:text-[#ff7a9c]"
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
