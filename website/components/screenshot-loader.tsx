"use client";

import { useEffect, useId, useState } from "react";

// What a screenshot shows while it downloads: the app's own goal ring filling
// to a mile, the miles ticking up beside it, and a warm-up line that changes
// each lap. It sits in the phone frame's screen at the screenshot's exact size,
// so nothing jumps when the picture fades in over it.

const LINES = [
  "Lacing up…",
  "Stretching…",
  "Warming up…",
  "Hitting Start Mile…",
  "Almost a mile…",
];
const LAP_MS = 1600;
const R = 38;
const C = 2 * Math.PI * R;

export function ScreenshotLoader() {
  const [reduceMotion, setReduceMotion] = useState(false);
  const [miles, setMiles] = useState(0);
  const [lap, setLap] = useState(0);
  const gradientId = `loader-ring-${useId().replace(/:/g, "")}`;

  useEffect(() => {
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    setReduceMotion(mq.matches);
    if (mq.matches) return;
    const start = performance.now();
    let frame = 0;
    const tick = (now: number) => {
      const t = (now - start) / LAP_MS;
      setMiles(t % 1);
      setLap(Math.floor(t));
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, []);

  // Ease the fill so it surges and settles like a real walk, not a metronome.
  const eased = 1 - Math.pow(1 - miles, 2.2);

  return (
    <span
      role="status"
      aria-label="Loading screenshot"
      className="absolute inset-0 flex flex-col items-center justify-center gap-4 overflow-hidden"
      style={{
        borderRadius: "14% / 6.5%",
        background:
          "radial-gradient(120% 70% at 50% 30%, #2a1218 0%, #120a0c 55%, #0a0a0a 100%)",
      }}
    >
      <span className="relative block h-[96px] w-[96px]">
        <svg
          viewBox="0 0 96 96"
          className="h-full w-full -rotate-90"
          aria-hidden
        >
          <defs>
            <linearGradient id={gradientId} x1="0" y1="0" x2="1" y2="1">
              <stop offset="0%" stopColor="#c72554" />
              <stop offset="100%" stopColor="#FF9F0A" />
            </linearGradient>
          </defs>
          <circle
            cx="48"
            cy="48"
            r={R}
            fill="none"
            stroke="rgba(255,255,255,0.08)"
            strokeWidth="8"
          />
          <circle
            cx="48"
            cy="48"
            r={R}
            fill="none"
            stroke={`url(#${gradientId})`}
            strokeWidth="8"
            strokeLinecap="round"
            strokeDasharray={C}
            strokeDashoffset={reduceMotion ? C * 0.25 : C * (1 - eased)}
          />
        </svg>
        <span className="absolute inset-0 flex flex-col items-center justify-center leading-none">
          <span className="font-heading text-[26px] tabular-nums text-white">
            {reduceMotion ? "…" : eased.toFixed(2)}
          </span>
          <span className="mt-0.5 text-[9px] font-semibold uppercase tracking-[0.18em] text-white/50">
            mi
          </span>
        </span>
      </span>
      <span className="text-[12px] font-semibold tracking-wide text-white/70">
        {reduceMotion ? "Loading…" : LINES[lap % LINES.length]}
      </span>
    </span>
  );
}
