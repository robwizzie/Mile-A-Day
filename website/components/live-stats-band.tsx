"use client";

import { useEffect, useRef, useState } from "react";
import { Route, Flame, Heart, Bell } from "lucide-react";

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
};

/** Eases a displayed number toward `target` — same feel as the community
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
  icon: Icon,
  color,
  value,
  suffix,
  label,
  sublabel,
  delay,
}: {
  icon: typeof Route;
  color: string;
  value: string;
  suffix?: string;
  label: string;
  sublabel: string;
  delay: number;
}) {
  return (
    <div
      className={`reveal-scale reveal-delay-${delay} glass-card type-card group relative overflow-hidden rounded-2xl px-6 py-7 text-center`}
      style={{ "--accent": color } as React.CSSProperties}
    >
      {/* Accent glow that breathes on hover */}
      <div
        className="pointer-events-none absolute -top-10 left-1/2 h-24 w-24 -translate-x-1/2 rounded-full opacity-[0.12] blur-2xl transition-opacity duration-300 group-hover:opacity-30"
        style={{ background: color }}
      />
      <div
        className="relative mx-auto mb-4 flex h-11 w-11 items-center justify-center rounded-2xl"
        style={{ background: `${color}1F`, border: `1px solid ${color}33` }}
      >
        <Icon className="h-5 w-5" style={{ color }} />
      </div>
      <div className="relative font-heading text-[clamp(34px,4.5vw,52px)] leading-none tracking-[0.5px] text-[#f5f5f5] tabular-nums">
        {value}
        {suffix && (
          <span className="ml-1 text-[0.45em] text-[#a0a0a0]">{suffix}</span>
        )}
      </div>
      <div className="relative mt-2 text-sm font-semibold text-[#f5f5f5]/90">
        {label}
      </div>
      <div className="relative mt-0.5 text-xs text-[#a0a0a0]">{sublabel}</div>
    </div>
  );
}

/** Live community counters — real numbers straight from the Mile A Day API
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
        // Fail silently — the band just doesn't render.
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
  const hypes = useCountUp(stats ? stats.total_hypes : null);
  const nudges = useCountUp(stats ? stats.total_nudges : null);

  if (stats === null) return null;

  return (
    <section
      className="section-lazy relative px-6 py-20"
      style={{
        background:
          "radial-gradient(ellipse 800px 400px at 50% 0%, rgba(199,37,84,0.06) 0%, transparent 70%)",
      }}
    >
      <div className="relative mx-auto max-w-6xl">
        <div className="mx-auto mb-12 max-w-2xl text-center">
          <span className="reveal mb-4 inline-flex items-center gap-2 text-sm font-semibold uppercase tracking-widest text-[#c72554]">
            <span className="relative flex h-2.5 w-2.5">
              <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-[#33B34D] opacity-75" />
              <span className="relative inline-flex h-2.5 w-2.5 rounded-full bg-[#33B34D]" />
            </span>
            Live from the community
          </span>
          <h2 className="reveal reveal-delay-1 font-heading text-[clamp(40px,6vw,72px)] leading-none tracking-[-1px] text-[#f5f5f5]">
            THE MILES ARE <span className="text-[#c72554]">ADDING UP</span>
          </h2>
          <p className="reveal reveal-delay-2 mt-4 text-base leading-relaxed text-[#a0a0a0]">
            Real numbers from real runners — updating as the community moves.
          </p>
        </div>

        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4 lg:gap-6">
          <StatCard
            icon={Route}
            color="#c72554"
            value={Math.round(totalMiles).toLocaleString()}
            suffix="mi"
            label="Total miles logged"
            sublabel="every single one earned"
            delay={1}
          />
          <StatCard
            icon={Flame}
            color="#33B34D"
            value={milesToday.toLocaleString(undefined, {
              minimumFractionDigits: 1,
              maximumFractionDigits: 1,
            })}
            suffix="mi"
            label="Miles today"
            sublabel="and the day isn't over"
            delay={2}
          />
          <StatCard
            icon={Heart}
            color="#D94059"
            value={Math.round(hypes).toLocaleString()}
            label="Hypes sent"
            sublabel="double-taps of pure support"
            delay={3}
          />
          <StatCard
            icon={Bell}
            color="#FF9900"
            value={Math.round(nudges).toLocaleString()}
            label="Nudges delivered"
            sublabel="friendly kicks off the couch"
            delay={4}
          />
        </div>
      </div>
    </section>
  );
}
