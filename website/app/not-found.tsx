import Link from "next/link";
import { APP_STORE_URL } from "@/lib/site";
import { Navbar } from "@/components/navbar";
import { LostFlamey } from "@/components/lost-flamey";

// Every unknown path (and /u/<name> or /p/<id> when the backend has no such
// profile or post) lands here instead of Next's default white 404: the hero's
// red, a lost route wandering off the page, and Flamey reacting to each poke.
export default function NotFound() {
  return (
    <main
      className="relative flex min-h-screen flex-col overflow-hidden text-white"
      style={{
        background: "linear-gradient(180deg, #ec3047 0%, #dc253b 100%)",
      }}
    >
      <Navbar />

      {/* A route that loses its way: dashes drawing in, ending in a question mark pin */}
      <svg
        aria-hidden="true"
        viewBox="0 0 1200 800"
        preserveAspectRatio="xMidYMid slice"
        className="pointer-events-none absolute inset-0 h-full w-full"
      >
        <path
          className="lost-route"
          d="M-40 700 C 160 640, 220 520, 360 560 S 560 720, 640 600 S 560 380, 760 360 S 1000 470, 1040 300 S 900 120, 1080 90"
          fill="none"
          stroke="rgba(255,255,255,0.22)"
          strokeWidth="10"
          strokeLinecap="round"
          strokeDasharray="2 26"
        />
        <g className="lost-pin" transform="translate(1080 90)">
          <circle r="30" fill="rgba(255,255,255,0.18)" />
          <text
            y="12"
            textAnchor="middle"
            fontSize="36"
            fontWeight="800"
            fill="rgba(255,255,255,0.7)"
            fontFamily="system-ui, sans-serif"
          >
            ?
          </text>
        </g>
      </svg>

      <div className="relative mx-auto flex w-full max-w-5xl flex-1 flex-col items-center justify-center gap-10 px-6 pb-16 pt-28 md:flex-row md:justify-between md:gap-16">
        <div className="max-w-md text-center md:text-left">
          <p className="mad-rise text-[13px] font-semibold uppercase tracking-[0.18em] text-white/85">
            404 · Off route
          </p>
          <h1
            className="mad-rise mt-3 font-heading text-[clamp(56px,10vw,104px)] leading-[0.9]"
            style={{ "--d": "80ms" } as React.CSSProperties}
          >
            Wrong turn.
          </h1>
          <p
            className="mad-rise mt-5 text-[18px] leading-relaxed text-white/90"
            style={{ "--d": "160ms" } as React.CSSProperties}
          >
            This page doesn&apos;t exist, or the profile or post it pointed to
            is gone. Good news: a wrong turn still counts toward your mile.
          </p>
          <div
            className="mad-rise mt-8 flex flex-col items-center gap-3 sm:flex-row md:items-start"
            style={{ "--d": "240ms" } as React.CSSProperties}
          >
            <Link
              href="/"
              className="lift rounded-full bg-white px-6 py-3.5 text-[15px] font-semibold text-[#16090c] hover:bg-white/90"
            >
              Take me home
            </Link>
            <a
              href={APP_STORE_URL} data-track="app_store:404"
              className="lift rounded-full bg-black/20 px-6 py-3.5 text-[15px] font-semibold text-white hover:bg-black/30"
            >
              Get the app
            </a>
          </div>
        </div>

        <div className="mad-phone-in">
          <LostFlamey />
        </div>
      </div>
    </main>
  );
}
