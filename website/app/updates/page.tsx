import type { Metadata } from "next";
import { Mail } from "lucide-react";
import { Navbar } from "@/components/navbar";
import { Footer } from "@/components/footer";
import {
  RELEASES,
  CURRENT_RELEASE,
  RELEASE_SHOWCASE,
  releaseAnchor,
  type Release,
} from "@/lib/releases";
import { ShowcaseCarousel, type ShowcaseSlide } from "@/components/showcase-carousel";
import { ReleaseFeatureList } from "@/components/release-feature-list";
import { AppStoreButton } from "@/components/app-store-button";
import { APP_STORE_URL, SUPPORT_EMAIL, SUPPORT_MAILTO } from "@/lib/site";
import { ogVideos } from "../_og/video/meta";

const TITLE = "What's New";
const DESCRIPTION = `Release notes for every Mile A Day update on iPhone and Apple Watch. Now on version ${CURRENT_RELEASE.version}: ${CURRENT_RELEASE.headline}.`;

export const metadata: Metadata = {
  title: TITLE,
  description: DESCRIPTION,
  alternates: { canonical: "/updates" },
  // A page's openGraph/twitter REPLACE the root ones, so restate what a share
  // needs; the card image comes from this segment's opengraph-image.
  openGraph: {
    title: `${TITLE} | Mile A Day`,
    description: DESCRIPTION,
    url: "/updates",
    type: "website",
    siteName: "Mile A Day",
    videos: ogVideos("/updates/og.mp4"),
  },
  twitter: {
    card: "summary_large_image",
    site: "@mileadayapp",
    title: `${TITLE} | Mile A Day`,
    description: DESCRIPTION,
  },
};

export default function UpdatesPage() {
  return (
    <main className="relative min-h-screen overflow-x-hidden bg-[#0e0809]">
      <Navbar />

      {/* The hero's red: the newest release, then the button */}
      <header
        className="relative overflow-hidden px-6 pb-16 pt-36 text-white"
        style={{ background: "linear-gradient(180deg, #ec3047 0%, #dc253b 100%)" }}
      >
        <div
          aria-hidden="true"
          className="pointer-events-none absolute bottom-[-30%] right-[-8%] h-[150%] w-[55%] opacity-[0.09]"
          style={{
            background:
              "url(/images/app-store/flamey-silhouette.svg) no-repeat bottom center / contain",
          }}
        />
        <div className="relative mx-auto grid max-w-6xl items-end gap-10 md:grid-cols-[minmax(0,1fr)_auto]">
          <div>
            <p className="mad-rise mb-4 text-[13px] font-semibold uppercase tracking-[0.18em] text-white/85">
              Release notes
            </p>
            <h1
              className="mad-rise font-heading text-[clamp(56px,10vw,120px)] leading-[0.9]"
              style={{ "--d": "80ms" } as React.CSSProperties}
            >
              What&apos;s new.
            </h1>
            <p
              className="mad-rise mt-5 max-w-xl text-[18px] leading-relaxed text-white/90"
              style={{ "--d": "160ms" } as React.CSSProperties}
            >
              Every Mile A Day update for iPhone and Apple Watch, newest first.
            </p>
          </div>
          <div
            className="mad-rise md:text-right"
            style={{ "--d": "240ms" } as React.CSSProperties}
          >
            <p className="text-[13px] font-semibold uppercase tracking-[0.18em] text-white/85">
              Now on
            </p>
            <p className="font-heading text-[clamp(64px,9vw,104px)] leading-none">
              {CURRENT_RELEASE.version}
            </p>
            <p className="mt-2 text-[15px] font-semibold text-white/90">
              {CURRENT_RELEASE.date} · {CURRENT_RELEASE.headline}
            </p>
            <div className="mt-5 flex md:justify-end">
              <AppStoreButton />
            </div>
          </div>
        </div>
      </header>

      <div className="px-6 pb-24 pt-16">
        {/* minmax(0,1fr) on phones too: an `auto` column takes the min-content
            width of what's inside it, and a carousel's track is every slide
            side by side, so each release card went 1090px wide and was clipped. */}
        <div className="mx-auto grid max-w-6xl grid-cols-[minmax(0,1fr)] gap-10 lg:grid-cols-[250px_minmax(0,1fr)] lg:gap-14">
          {/* Version index: a sticky list on desktop, a wrapping row of chips on phones. */}
          <nav
            aria-label="Versions"
            className="lg:sticky lg:top-28 lg:self-start"
          >
            <p className="mb-3 text-[13px] font-semibold uppercase tracking-[0.18em] text-white/50">
              All versions
            </p>
            <ul className="flex flex-wrap gap-2 lg:flex-col lg:gap-1">
              {RELEASES.map((r, i) => (
                <li key={r.version}>
                  <a
                    href={`#${releaseAnchor(r.version)}`}
                    className="flex items-center gap-3 rounded-full bg-white/[0.04] px-4 py-2 transition-colors hover:bg-white/[0.08] lg:bg-transparent"
                  >
                    <span className="font-heading text-[20px] leading-none text-white">
                      {r.version}
                    </span>
                    <span className="whitespace-nowrap text-xs text-white/50">{r.date}</span>
                    {i === 0 && (
                      <span className="rounded-full bg-[#ec3047] px-2 py-0.5 text-[10px] font-bold uppercase tracking-wider text-white">
                        Current
                      </span>
                    )}
                  </a>
                </li>
              ))}
            </ul>

            <div className="mt-8 hidden rounded-3xl bg-white/[0.04] p-5 lg:block">
              <p className="text-sm font-semibold text-white">
                Something not working?
              </p>
              <a
                href={SUPPORT_MAILTO}
                className="mt-2 inline-flex items-center gap-1.5 text-sm font-semibold text-white underline decoration-white/30 underline-offset-4 hover:decoration-white"
              >
                <Mail className="h-4 w-4" />
                {SUPPORT_EMAIL}
              </a>
            </div>
          </nav>

          <div className="relative">
            {RELEASES.map((release, i) => (
              <ReleaseEntry
                key={release.version}
                release={release}
                current={i === 0}
              />
            ))}
          </div>
        </div>
      </div>

      <Footer />
    </main>
  );
}

function ReleaseEntry({
  release,
  current,
}: {
  release: Release;
  current: boolean;
}) {
  // The same real captures the home page's What's New shows for this version.
  const slides: ShowcaseSlide[] = (RELEASE_SHOWCASE[release.version] ?? [])
    .filter((s) => s.screenshot)
    .map((s) => ({
      ...s,
      screenshot: s.screenshot!,
      color: release.features.find((f) => f.title === s.title)?.color ?? "#c72554",
    }));

  return (
    <article
      id={releaseAnchor(release.version)}
      className="relative scroll-mt-28 border-l border-white/10 pb-16 pl-7 last:pb-0 sm:pl-10"
    >
      {/* The timeline's dot for this release */}
      <span
        aria-hidden="true"
        className={`absolute -left-[7px] top-3 h-[13px] w-[13px] rounded-full ${
          current ? "bg-[#ec3047] ring-4 ring-[#ec3047]/25" : "bg-white/30"
        }`}
      />
      <div data-reveal="">
        <div className="flex flex-wrap items-baseline gap-x-4 gap-y-1">
          <h2 className="font-heading text-[48px] leading-none text-white">{release.version}</h2>
          <span className="text-sm font-medium text-white/50">{release.date}</span>
          {current && (
            <span className="rounded-full bg-[#ec3047] px-2.5 py-0.5 text-[11px] font-bold uppercase tracking-wider text-white">
              Latest
            </span>
          )}
        </div>
        <p className="mt-3 text-[22px] font-semibold leading-snug text-white">{release.headline}</p>
        <p className="mt-2 max-w-2xl text-[16px] leading-relaxed text-white/70">{release.summary}</p>
      </div>

      {slides.length > 0 && (
        <div className="mt-8" data-reveal="">
          <ShowcaseCarousel slides={slides} label={`${release.version} screenshots`} />
        </div>
      )}

      <div className="mt-8">
        <ReleaseFeatureList features={release.features} />
      </div>
    </article>
  );
}
