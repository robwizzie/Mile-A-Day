"use client";

import { useEffect, useState } from "react";

/**
 * One observer for the whole site: anything marked `data-reveal` eases in the
 * first time it scrolls into view (CSS in globals.css; `--d` staggers it).
 * The hidden starting state only applies once this has run (`reveal-on` on
 * <html>), so crawlers, no-JS visitors and Reduce Motion see everything at once.
 */
export function RevealObserver() {
  useEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const root = document.documentElement;
    root.classList.add("reveal-on");

    const io = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-in");
            io.unobserve(entry.target);
          }
        }
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.12 },
    );
    const scan = () =>
      document
        .querySelectorAll("[data-reveal]:not(.is-in)")
        .forEach((el) => io.observe(el));
    scan();
    // Client navigation and late-loading sections add new targets.
    const mo = new MutationObserver(scan);
    mo.observe(document.body, { childList: true, subtree: true });
    return () => {
      io.disconnect();
      mo.disconnect();
      root.classList.remove("reveal-on");
    };
  }, []);
  return null;
}

/**
 * True once the element has been on screen (and stays true). Returns a
 * callback ref, so it also works on an element that mounts later (a section
 * that waits for its data).
 */
export function useInView<T extends Element>(threshold = 0.25) {
  const [el, setEl] = useState<T | null>(null);
  const [inView, setInView] = useState(false);
  useEffect(() => {
    if (!el || inView) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setInView(true);
      return;
    }
    const io = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setInView(true);
          io.disconnect();
        }
      },
      { threshold },
    );
    io.observe(el);
    return () => io.disconnect();
  }, [el, inView, threshold]);
  return [setEl, inView] as const;
}
