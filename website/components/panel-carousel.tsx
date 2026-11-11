"use client";

import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { useInView } from "./reveal";

export type Slide = {
  key: string;
  label: string;
  color: string;
  node: ReactNode;
};

const AUTOPLAY_MS = 7000;

/**
 * The colour panels as one band you swipe or tab through, instead of six
 * full-height panels stacked down the page. A native scroll-snap track (so
 * touch, trackpad and keyboard all just work), tab pills over the top in each
 * panel's colour, arrows on wider screens, and a gentle autoplay that runs
 * only while the band is on screen and stops for good once someone takes the
 * wheel. `/#<slide key>` (e.g. /#competitions) lands on that slide.
 */
export function PanelCarousel({
  slides,
  id,
}: {
  slides: Slide[];
  id?: string;
}) {
  const track = useRef<HTMLDivElement>(null);
  const [active, setActive] = useState(0);
  const [touched, setTouched] = useState(false);
  const [hovering, setHovering] = useState(false);
  const [bandRef, inView] = useInView<HTMLElement>(0.35);
  const reduceMotion = useRef(false);

  const go = useCallback(
    (i: number, smooth = true) => {
      const el = track.current;
      if (!el) return;
      const n = slides.length;
      const j = ((i % n) + n) % n;
      el.scrollTo({
        left: j * el.clientWidth,
        behavior: smooth && !reduceMotion.current ? "smooth" : "auto",
      });
    },
    [slides.length],
  );

  // Which slide is showing, read from the scroll position.
  useEffect(() => {
    reduceMotion.current = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;
    const el = track.current;
    if (!el) return;
    let frame = 0;
    const onScroll = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() =>
        setActive(Math.round(el.scrollLeft / Math.max(1, el.clientWidth))),
      );
    };
    el.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      el.removeEventListener("scroll", onScroll);
      cancelAnimationFrame(frame);
    };
  }, []);

  // A link to one slide (/#competitions) opens on it.
  useEffect(() => {
    const open = () => {
      const key = decodeURIComponent(location.hash.slice(1));
      const i = slides.findIndex((s) => s.key === key);
      if (i >= 0) {
        setTouched(true);
        go(i, false);
      }
    };
    open();
    window.addEventListener("hashchange", open);
    return () => window.removeEventListener("hashchange", open);
  }, [slides, go]);

  // Autoplay: only on screen, never under a hover, never after a touch.
  useEffect(() => {
    if (!inView || touched || hovering || reduceMotion.current) return;
    const t = setTimeout(() => go(active + 1), AUTOPLAY_MS);
    return () => clearTimeout(t);
  }, [active, inView, touched, hovering, go]);

  const take = () => setTouched(true);

  return (
    <section
      ref={bandRef}
      id={id}
      aria-roledescription="carousel"
      aria-label="What's inside the app"
      className="relative scroll-mt-16"
      onMouseEnter={() => setHovering(true)}
      onMouseLeave={() => setHovering(false)}
      onKeyDown={(e) => {
        if (e.key === "ArrowRight") (take(), go(active + 1));
        if (e.key === "ArrowLeft") (take(), go(active - 1));
      }}
    >
      {/* Every slide's anchor, so /#competitions scrolls the page here too */}
      {slides.map((s) => (
        <span
          key={s.key}
          id={s.key}
          className="absolute top-0 scroll-mt-16"
          aria-hidden
        />
      ))}

      <div
        ref={track}
        onPointerDown={take}
        onWheel={(e) => Math.abs(e.deltaX) > Math.abs(e.deltaY) && take()}
        className="no-scrollbar flex snap-x snap-mandatory overflow-x-auto overscroll-x-contain"
      >
        {slides.map((s, i) => (
          <div
            key={s.key}
            role="group"
            aria-roledescription="slide"
            aria-label={`${i + 1} of ${slides.length}: ${s.label}`}
            aria-hidden={i !== active}
            className="w-full shrink-0 snap-start snap-always"
          >
            {s.node}
          </div>
        ))}
      </div>

      {/* Tabs over the top of the band */}
      <div className="pointer-events-none absolute inset-x-0 top-5 z-10 px-4 md:top-7">
        <div className="no-scrollbar pointer-events-auto mx-auto flex max-w-6xl gap-2 overflow-x-auto md:justify-center">
          {slides.map((s, i) => {
            const on = i === active;
            return (
              <button
                key={s.key}
                type="button"
                data-track={`carousel:${s.key}`}
                onClick={() => (take(), go(i))}
                aria-current={on}
                className={`relative shrink-0 overflow-hidden rounded-full px-4 py-2 text-[13px] font-semibold transition-colors ${
                  on ? "bg-white" : "bg-black/20 text-white hover:bg-black/30"
                }`}
                style={on ? { color: s.color } : undefined}
              >
                {s.label}
                {/* The autoplay countdown, as a thin bar under the active tab */}
                {on && !touched && inView && !hovering && (
                  <span
                    key={`${active}-${s.key}`}
                    className="carousel-progress absolute bottom-0 left-0 h-[3px]"
                    style={{
                      background: s.color,
                      animationDuration: `${AUTOPLAY_MS}ms`,
                    }}
                  />
                )}
              </button>
            );
          })}
        </div>
      </div>

      {/* Arrows (pointer screens; phones swipe) */}
      {[
        { dir: -1, Icon: ChevronLeft, side: "left-4", label: "Previous" },
        { dir: 1, Icon: ChevronRight, side: "right-4", label: "Next" },
      ].map(({ dir, Icon, side, label }) => (
        <button
          key={dir}
          type="button"
          aria-label={label}
          data-track={dir < 0 ? "carousel_prev" : "carousel_next"}
          onClick={() => (take(), go(active + dir))}
          className={`absolute ${side} top-1/2 z-10 hidden h-12 w-12 -translate-y-1/2 items-center justify-center rounded-full bg-white/90 text-[#16090c] shadow-lg hover:bg-white xl:flex`}
        >
          <Icon className="h-6 w-6" />
        </button>
      ))}
    </section>
  );
}
