"use client";

import { useEffect, useState } from "react";
import { founderStreakDays } from "@/lib/story";

/** The founders' streak, counted on the visitor's clock (the page itself is static). */
export function FounderStreak({ className = "" }: { className?: string }) {
  const [days, setDays] = useState<number | null>(null);
  useEffect(() => {
    setDays(founderStreakDays());
    const id = setInterval(() => setDays(founderStreakDays()), 60_000);
    return () => clearInterval(id);
  }, []);
  return (
    <span className={`tabular-nums ${className}`}>
      {days === null ? "…" : days.toLocaleString()}
    </span>
  );
}
