"use client";

import { useEffect, useRef, useState } from "react";
import { LiveDot, SectionHeader } from "./section-header";

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

function StatCard({
  color,
  value,
  suffix,
  label,
  sublabel,
}: {
  color: string;
  value: string;
  suffix?: string;
  label: string;
  sublabel: string;
}) {
  return (
    <div className="rounded-3xl bg-white/[0.04] px-6 py-7">
      <div className="mb-5 h-1 w-10 rounded-full" style={{ background: color }} />
      <div className="font-heading text-[clamp(34px,4.2vw,50px)] leading-none text-white tabular-nums">
        {value}
        {suffix && (
          <span className="ml-1.5 text-[0.42em] font-semibold tracking-normal text-white/50">
            {suffix}
          </span>
        )}
      </div>
      <div className="mt-3 text-[15px] font-semibold text-white">{label}</div>
      <div className="mt-0.5 text-[13px] text-white/55">{sublabel}</div>
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

  const totalMiles = useCountUp(stats ? stats.total_miles : null);
  const milesToday = useCountUp(stats ? stats.miles_today : null, 1);
  const totalUsers = useCountUp(stats ? stats.total_users : null);
  // `?? 0` guards the brief window where the site deploys before the backend
  // ships the new fields; a missing value would otherwise animate to NaN.
  const activeWeek = useCountUp(stats ? (stats.active_7d ?? 0) : null);
  const photosShared = useCountUp(stats ? (stats.photos_shared ?? 0) : null);
  const longestStreak = useCountUp(stats ? (stats.longest_streak ?? 0) : null);
  const hypes = useCountUp(stats ? stats.total_hypes : null);
  const nudges = useCountUp(stats ? stats.total_nudges : null);

  if (stats === null) return null;

  return (
    <section className="bg-[#0e0809] px-6 py-24 text-white">
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
          <StatCard color="#ec3047" value={Math.round(totalMiles).toLocaleString()} suffix="mi" label="Total miles logged" sublabel="every single one earned" />
          <StatCard color="#2bc189" value={milesToday.toLocaleString(undefined, { minimumFractionDigits: 1, maximumFractionDigits: 1 })} suffix="mi" label="Miles today" sublabel="and the day isn't over" />
          <StatCard color="#3e82f4" value={Math.round(totalUsers).toLocaleString()} label="Members strong" sublabel="the whole community" />
          <StatCard color="#16aeb1" value={Math.round(activeWeek).toLocaleString()} label="Out moving this week" sublabel="logging miles right now" />
          <StatCard color="#6656ea" value={Math.round(photosShared).toLocaleString()} label="Photos shared" sublabel="milestones worth capturing" />
          <StatCard color="#f7aa2c" value={Math.round(longestStreak).toLocaleString()} suffix="days" label="Longest active streak" sublabel="unbroken and still going" />
          <StatCard color="#ff7555" value={Math.round(hypes).toLocaleString()} label="Hypes sent" sublabel="double-taps of pure support" />
          <StatCard color="#9452ec" value={Math.round(nudges).toLocaleString()} label="Nudges delivered" sublabel="friendly kicks off the couch" />
        </div>
      </div>
    </section>
  );
}
