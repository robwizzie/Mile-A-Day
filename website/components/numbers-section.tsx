"use client";

import { useEffect, useState } from "react";

const API_URL =
  process.env.NEXT_PUBLIC_API_URL || "https://mad.mindgoblin.tech";
const STATS_URL = `${API_URL}/public/stats`;

type PublicStats = {
  total_miles: number;
  miles_today: number;
  longest_streak: number;
  total_hypes: number;
};

/** Four real numbers from the community, plain. Nothing renders until they arrive. */
export function NumbersSection() {
  const [stats, setStats] = useState<PublicStats | null>(null);

  useEffect(() => {
    let cancelled = false;
    const load = () =>
      fetch(STATS_URL)
        .then((r) => (r.ok ? r.json() : Promise.reject()))
        .then((d) => !cancelled && setStats(d))
        .catch(() => {});
    load();
    const id = setInterval(load, 60_000);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, []);

  const rows: Array<[string, string]> = stats
    ? [
        [
          Math.round(stats.total_miles).toLocaleString(),
          "miles walked and run",
        ],
        [
          stats.miles_today.toLocaleString(undefined, {
            maximumFractionDigits: 1,
          }),
          "miles so far today",
        ],
        [
          `${(stats.longest_streak ?? 0).toLocaleString()} days`,
          "longest streak still going",
        ],
        [
          (stats.total_hypes ?? 0).toLocaleString(),
          "hypes sent between friends",
        ],
      ]
    : [];

  return (
    <section className="bg-[#140b0e] px-6 py-24 text-white">
      <div className="mx-auto max-w-6xl">
        <h2 className="font-heading text-[clamp(36px,5vw,60px)] leading-[1]">
          Real people.
          <br />
          Real miles.
        </h2>
        <p className="mt-4 max-w-lg text-[17px] text-white/70">
          Straight from the app, updated every minute.
        </p>
        <div className="mt-12 grid min-h-[96px] grid-cols-2 gap-x-8 gap-y-10 md:grid-cols-4">
          {rows.map(([value, label]) => (
            <div key={label}>
              <div className="font-heading text-[clamp(32px,4vw,48px)] leading-none">
                {value}
              </div>
              <div className="mt-2 text-[15px] text-white/65">{label}</div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
