"use client";

import { useEffect } from "react";
import { usePathname } from "next/navigation";

/**
 * Lands a `/#section` link on its section. Coming from another page, the
 * browser jumps to the anchor the moment the HTML arrives, and then fonts,
 * images and live data above it settle and push it out of place. This
 * re-aims at the target as the page settles (a few times over ~1.5 s, and
 * once everything has loaded), and stops the moment the visitor scrolls
 * themselves. The section's own `scroll-mt-*` keeps it clear of the navbar.
 */
export function HashLander() {
  const pathname = usePathname();

  useEffect(() => {
    let stopped = false;
    const timers: ReturnType<typeof setTimeout>[] = [];

    const target = () => {
      const id = decodeURIComponent(location.hash.slice(1));
      return id ? document.getElementById(id) : null;
    };
    const aim = () => {
      if (stopped) return;
      const el = target();
      if (el) el.scrollIntoView({ block: "start", behavior: "auto" });
    };
    const stop = () => {
      stopped = true;
    };
    const land = () => {
      stopped = false;
      if (!target()) return;
      for (const ms of [0, 120, 400, 900, 1500])
        timers.push(setTimeout(aim, ms));
    };

    land();
    const onLoad = () => aim();
    window.addEventListener("load", onLoad);
    window.addEventListener("hashchange", land);
    // A person scrolling wins: never yank them back.
    window.addEventListener("wheel", stop, { passive: true });
    window.addEventListener("touchmove", stop, { passive: true });
    window.addEventListener("keydown", stop);
    return () => {
      timers.forEach(clearTimeout);
      window.removeEventListener("load", onLoad);
      window.removeEventListener("hashchange", land);
      window.removeEventListener("wheel", stop);
      window.removeEventListener("touchmove", stop);
      window.removeEventListener("keydown", stop);
    };
  }, [pathname]);

  return null;
}
