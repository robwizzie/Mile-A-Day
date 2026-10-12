import type { Metadata } from "next";
import { Mail } from "lucide-react";
import { Navbar } from "@/components/navbar";
import { Footer } from "@/components/footer";
import {
  RELEASES,
  CURRENT_RELEASE,
  releaseAnchor,
  type Release,
} from "@/lib/releases";
import { APP_STORE_URL, SUPPORT_EMAIL, SUPPORT_MAILTO } from "@/lib/site";

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
  },
  twitter: {
    card: "summary_large_image",
    site: "@mileadayapp",
    title: `${TITLE} | Mile A Day`,
    description: DESCRIPTION,
  },
};

const APPLE_LOGO =
  "M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z";

export default function UpdatesPage() {
  return (
    <main className="relative min-h-screen overflow-x-hidden bg-[#0a0a0a]">
      <Navbar />

      <header
        className="relative px-6 pb-14 pt-36"
        style={{
          background:
            "radial-gradient(ellipse 700px 420px at 50% 0%, rgba(199,37,84,0.10), transparent 70%)",
        }}
      >
        <div className="mx-auto max-w-6xl">
          <span className="mb-4 inline-block text-sm font-semibold uppercase tracking-widest text-[#c72554]">
            Release notes
          </span>
          <h1 className="font-heading text-[clamp(56px,10vw,120px)] leading-[0.9] tracking-[-2px] text-[#f5f5f5]">
            WHAT&apos;S NEW
          </h1>
          <p className="mt-5 max-w-xl text-lg leading-relaxed text-[#a0a0a0]">
            Every Mile A Day update for iPhone and Apple Watch, newest first.
          </p>

          <div className="glass-card-highlight mt-10 flex flex-col gap-5 rounded-2xl p-6 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <p className="text-xs font-semibold uppercase tracking-widest text-[#ff4d7d]">
                Current version
              </p>
              <p className="mt-1 text-[#f5f5f5]">
                <span className="font-heading text-[40px] leading-none">
                  {CURRENT_RELEASE.version}
                </span>
                <span className="mt-1 block text-sm text-[#a0a0a0] sm:ml-3 sm:mt-0 sm:inline">
                  {CURRENT_RELEASE.date} · {CURRENT_RELEASE.headline}
                </span>
              </p>
            </div>
            <a
              href={APP_STORE_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="glass-button inline-flex shrink-0 items-center justify-center gap-2.5 rounded-xl px-6 py-3 text-sm font-semibold text-white"
            >
              <svg
                className="h-4 w-4"
                viewBox="0 0 24 24"
                fill="currentColor"
                aria-hidden
              >
                <path d={APPLE_LOGO} />
              </svg>
              Get it on the App Store
            </a>
          </div>
        </div>
      </header>

      <div className="px-6 pb-24">
        <div className="mx-auto grid max-w-6xl gap-10 lg:grid-cols-[250px_minmax(0,1fr)] lg:gap-14">
          {/* Version index: a sticky list on desktop, a wrapping row of chips on phones. */}
          <nav
            aria-label="Versions"
            className="lg:sticky lg:top-28 lg:self-start"
          >
            <p className="mb-3 text-xs font-semibold uppercase tracking-widest text-[#707070]">
              All versions
            </p>
            <ul className="flex flex-wrap gap-2 lg:flex-col lg:gap-1">
              {RELEASES.map((r, i) => (
                <li key={r.version}>
                  <a
                    href={`#${releaseAnchor(r.version)}`}
                    className="flex items-center gap-3 rounded-xl border border-white/[0.06] px-3 py-2 transition-colors hover:border-white/15 hover:bg-white/[0.03] lg:border-transparent"
                  >
                    <span className="font-heading text-[20px] leading-none text-[#f5f5f5]">
                      {r.version}
                    </span>
                    <span className="whitespace-nowrap text-xs text-[#a0a0a0]">{r.date}</span>
                    {i === 0 && (
                      <span className="rounded-full bg-[#c72554]/15 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wider text-[#ff4d7d]">
                        Current
                      </span>
                    )}
                  </a>
                </li>
              ))}
            </ul>

            <div className="mt-8 hidden rounded-2xl border border-white/[0.06] p-4 lg:block">
              <p className="text-sm font-semibold text-[#f5f5f5]">
                Something not working?
              </p>
              <a
                href={SUPPORT_MAILTO}
                className="mt-2 inline-flex items-center gap-1.5 text-sm font-semibold text-[#ff4d7d] hover:underline"
              >
                <Mail className="h-4 w-4" />
                {SUPPORT_EMAIL}
              </a>
            </div>
          </nav>

          <div className="relative space-y-8">
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
  return (
    <article
      id={releaseAnchor(release.version)}
      className={`scroll-mt-28 rounded-3xl p-6 sm:p-8 ${current ? "glass-card" : "border border-white/[0.06]"}`}
    >
      <div className="flex flex-wrap items-baseline gap-x-4 gap-y-1">
        <h2 className="font-heading text-[44px] leading-none text-[#f5f5f5]">
          {release.version}
        </h2>
        <span className="text-sm font-medium text-[#a0a0a0]">
          {release.date}
        </span>
        {current && (
          <span className="rounded-full bg-[#c72554] px-2.5 py-0.5 text-[11px] font-bold uppercase tracking-wider text-white">
            Latest
          </span>
        )}
      </div>
      <p className="mt-3 text-xl font-semibold text-[#f5f5f5]">
        {release.headline}
      </p>
      <p className="mt-1.5 max-w-2xl text-[15px] leading-relaxed text-[#a0a0a0]">
        {release.summary}
      </p>

      <ul className="mt-7 grid gap-x-8 gap-y-5 sm:grid-cols-2">
        {release.features.map((f) => (
          <li key={f.title} className="flex items-start gap-3.5">
            <span
              className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl"
              style={{ background: `${f.color}1f` }}
            >
              <f.icon
                className="h-5 w-5"
                style={{ color: f.color }}
                aria-hidden
              />
            </span>
            <span className="min-w-0">
              <span className="block text-[15px] font-semibold text-[#f5f5f5]">
                {f.title}
              </span>
              <span className="mt-0.5 block text-sm leading-relaxed text-[#a0a0a0]">
                {f.desc}
              </span>
            </span>
          </li>
        ))}
      </ul>
    </article>
  );
}
