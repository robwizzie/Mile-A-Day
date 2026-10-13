"use client";

import { useEffect, useState } from "react";

const API_URL = process.env.NEXT_PUBLIC_API_URL || "https://mad.mindgoblin.tech";
const POLL_MS = 20_000;

/** The public desk feed (community totals only), as the JSON string the
 *  box's code reads, refreshed every 20 s while the tab is visible. */
export function useDeskFeed(enabled = true): string | null {
  const [feed, setFeed] = useState<string | null>(null);
  useEffect(() => {
    if (!enabled) return;
    let alive = true;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const load = async () => {
      try {
        const res = await fetch(`${API_URL}/public/desk`, { cache: "no-store" });
        if (res.ok) {
          const text = await res.text();
          if (alive) setFeed(text);
        }
      } catch {
        /* offline: keep the last numbers */
      }
      if (alive) timer = setTimeout(load, document.hidden ? POLL_MS * 3 : POLL_MS);
    };
    load();
    return () => {
      alive = false;
      if (timer) clearTimeout(timer);
    };
  }, [enabled]);
  return feed;
}
