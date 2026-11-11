"use client";

import { useEffect, useRef, useState } from "react";
import { Activity, BellRing, Camera, Flame, Footprints, PartyPopper, Route, Users } from "lucide-react";
import { LiveDot, SectionHeader } from "./section-header";
import { useInView } from "./reveal";

const API_URL =
  process.env.NEXT_PUBLIC_API_URL || "https://mad.mindgoblin.tech";
const STATS_URL = `${API_URL}/public/stats`;
const POLL_MS = 60_000;

type PublicStats = {
  total_users: number;
  total_miles: number;
  miles_today: number;
  total_hypes: number;
  total_nudges: number;
  active_7d: number;
  photos_shared: number;
  longest_streak: number;
};

/** Eases a displayed number toward `target`, the same feel as the community
 * counter. Handles decimals so "miles today" can animate to e.g. 41.3. */
function useCountUp(target: number | null, decimals = 0) {
  const [display, setDisplay] = useState(0);
  const displayRef = useRef(0);

  useEffect(() => {
    if (target === null || displayRef.current === target) return;
    const from = displayRef.current;
    const duration = 1600;
    const start = performance.now();
    const factor = Math.pow(10, decimals);
    let frame: number;
    const tick = (now: number) => {
      const t = Math.min((now - start) / duration, 1);
      const eased = 1 - Math.pow(1 - t, 3);
      const val =
        Math.round((from + (target - from) * eased) * factor) / factor;
      displayRef.current = val;
      setDisplay(val);
      if (t < 1) frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [target, decimals]);

  return display;
}

// Each stat in one of the App Store screenshots' colours, with its icon.
const LOOKS = {
  miles: { from: "#ec3047", to: "#c8203a", Icon: Route },
  today: { from: "#ff7555", to: "#ea5a3b", Icon: Footprints },
  members: { from: "#6656ea", to: "#4f3fcf", Icon: Users },
  week: { from: "#16aeb1", to: "#0b9497", Icon: Activity },
  photos: { from: "#3e82f4", to: "#2c6bdc", Icon: Camera },
  streak: { from: "#f7aa2c", to: "#e08a0c", Icon: Flame },
  hypes: { from: "#9452ec", to: "#7a39d4", Icon: PartyPopper },
  nudges: { from: "#2bc189", to: "#17a56f", Icon: BellRing },
} as const;

function StatCard({
  look,
  value,
  suffix,
  label,
  sublabel,
  index,
}: {
  look: keyof typeof LOOKS;
  value: string;
  suffix?: string;
  label: string;
  sublabel: string;
  index: number;
}) {
  const { from, to, Icon } = LOOKS[look];
  return (
    <div
      data-reveal="pop"
      style={
        {
          "--d": `${index * 70}ms`,
          background: `linear-gradient(160deg, ${from} 0%, ${to} 100%)`,
        } as React.CSSProperties
      }
      className="stat-tile lift group relative overflow-hidden rounded-3xl px-5 py-6 text-white sm:px-6 sm:py-7"
    >
      {/* A big faint copy of the icon in the corner, tilting on hover */}
      <Icon
        aria-hidden
        strokeWidth={1.6}
        className="stat-watermark pointer-events-none absolute -bottom-5 -right-4 h-28 w-28 text-white/[0.16] sm:h-32 sm:w-32"
      />
      <span className="relative flex h-10 w-10 items-center justify-center rounded-full bg-white/20">
        <Icon aria-hidden className="h-5 w-5 text-white" strokeWidth={2.4} />
      </span>
      <div className="relative mt-4 font-heading text-[clamp(30px,4vw,48px)] leading-none tabular-nums">
        {value}
        {suffix && (
          <span className="ml-1.5 text-[0.42em] font-semibold tracking-normal text-white/75">
            {suffix}
          </span>
        )}
      </div>
      <div className="relative mt-2.5 text-[15px] font-semibold">{label}</div>
      <div className="relative mt-0.5 text-[13px] text-white/80">{sublabel}</div>
    </div>
  );
}

/** Live community counters: real numbers straight from the Mile A Day API
 * (global aggregates only), refreshed every minute with an animated count-up
 * so the page always shows the movement moving. */
export function LiveStatsBand() {
  const [stats, setStats] = useState<PublicStats | null>(null);

  useEffect(() => {
    let cancelled = false;
    const load = async () => {
      try {
        const res = await fetch(STATS_URL, { cache: "no-store" });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const data = (await res.json()) as PublicStats;
        if (!cancelled && typeof data.total_miles === "number") setStats(data);
      } catch {
        // Fail silently: the band just doesn't render.
      }
    };
    load();
    const id = setInterval(load, POLL_MS);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, []);

  // The numbers count up when the band comes on screen, not while it's
  // still below the fold.
  const [bandRef, inView] = useInView<HTMLElement>(0.2);
  const live = inView ? stats : null;
  const totalMiles = useCountUp(live ? live.total_miles : null);
  const milesToday = useCountUp(live ? live.miles_today : null, 1);
  const totalUsers = useCountUp(live ? live.total_users : null);
  // `?? 0` guards the brief window where the site deploys before the backend
  // ships the new fields; a missing value would otherwise animate to NaN.
  const activeWeek = useCountUp(live ? (live.active_7d ?? 0) : null);
  const photosShared = useCountUp(live ? (live.photos_shared ?? 0) : null);
  const longestStreak = useCountUp(live ? (live.longest_streak ?? 0) : null);
  const hypes = useCountUp(live ? live.total_hypes : null);
  const nudges = useCountUp(live ? live.total_nudges : null);


  return (
    <section ref={bandRef} className="bg-[#0e0809] px-6 py-24 text-white">
      <div className="mx-auto max-w-6xl">
        <SectionHeader
          className="mb-12"
          eyebrow={
            <>
              <LiveDot />
              Live from the community
            </>
          }
          title="The miles are adding up."
          body="Real numbers from real walkers and runners, updating as the community moves."
        />

        <div className="grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-4">
          <StatCard index={0} look="miles" value={Math.round(totalMiles).toLocaleString()} suffix="mi" label="Total miles logged" sublabel="every single one earned" />
          <StatCard index={1} look="today" value={milesToday.toLocaleString(undefined, { minimumFractionDigits: 1, maximumFractionDigits: 1 })} suffix="mi" label="Miles today" sublabel="and the day isn't over" />
          <StatCard index={2} look="members" value={Math.round(totalUsers).toLocaleString()} label="Members strong" sublabel="the whole community" />
          <StatCard index={3} look="week" value={Math.round(activeWeek).toLocaleString()} label="Out moving this week" sublabel="in the last 7 days" />
          <StatCard index={4} look="photos" value={Math.round(photosShared).toLocaleString()} label="Photos shared" sublabel="milestones worth capturing" />
          <StatCard index={5} look="streak" value={Math.round(longestStreak).toLocaleString()} suffix="days" label="Longest active streak" sublabel="unbroken and still going" />
          <StatCard index={6} look="hypes" value={Math.round(hypes).toLocaleString()} label="Hypes sent" sublabel="double-taps of pure support" />
          <StatCard index={7} look="nudges" value={Math.round(nudges).toLocaleString()} label="Nudges delivered" sublabel="friendly kicks off the couch" />
        </div>
      </div>
    </section>
  );
}
