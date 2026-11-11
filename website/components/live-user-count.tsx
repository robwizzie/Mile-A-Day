"use client";

import { useEffect, useState } from "react";

const API_URL =
  process.env.NEXT_PUBLIC_API_URL || "https://mad.mindgoblin.tech";
const USER_COUNT_URL = `${API_URL}/public/user-count`;

/** One plain line under the hero's button. Renders nothing until the real number arrives. */
export function LiveUserCount() {
  const [count, setCount] = useState<number | null>(null);

  useEffect(() => {
    let cancelled = false;
    fetch(USER_COUNT_URL)
      .then((res) =>
        res.ok ? res.json() : Promise.reject(new Error(`HTTP ${res.status}`)),
      )
      .then((data) => {
        if (!cancelled && typeof data.count === "number") setCount(data.count);
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, []);

  if (count === null) return null;

  return (
    <p className="text-[15px] text-white/80">
      {count.toLocaleString()} people are walking or running a mile a day with
      us.
    </p>
  );
}
