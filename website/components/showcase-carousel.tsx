"use client";

import Image from "next/image";
import { useCallback, useEffect, useRef, useState } from "react";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { ScreenshotLoader } from "@/components/screenshot-loader";

export type ShowcaseSlide = {
  title: string;
  caption: string;
  blurb: string;
  screenshot: string;
  /** The feature's colour from RELEASES — tints the glow behind the phone. */
  color: string;
};

// Captures are iPhone Mirroring window grabs, cropped to the bare screen.
const SHOT_W = 776;
const SHOT_H = 1680;

/**
 * The release's headline screenshots as a snap carousel, on every screen size:
 * the slide in the middle is full size and lit, its neighbours shrink and dim,
 * and the track pads itself by half a viewport so the first and last slide can
 * sit dead centre too — which is also what centres a release with ONE shot.
 * Arrows on wider screens, dots everywhere, swipe/trackpad/keyboard all move it.
 */
export function ShowcaseCarousel({ slides, label = "Feature screenshots" }: { slides: ShowcaseSlide[]; label?: string }) {
  const trackRef = useRef<HTMLDivElement>(null);
  const [active, setActive] = useState(0);

  // The active slide is whichever centre is nearest the track's centre.
  const measure = useCallback(() => {
    const track = trackRef.current;
    if (!track) return;
    const mid = track.scrollLeft + track.clientWidth / 2;
    let best = 0;
    let bestDist = Infinity;
    Array.from(track.children).forEach((child, i) => {
      const el = child as HTMLElement;
      const d = Math.abs(el.offsetLeft + el.offsetWidth / 2 - mid);
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    });
    setActive(best);
  }, []);

  useEffect(() => {
    const track = trackRef.current;
    if (!track) return;
    let frame = 0;
    const onScroll = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(measure);
    };
    track.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll);
    measure();
    return () => {
      cancelAnimationFrame(frame);
      track.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", onScroll);
    };
  }, [measure]);

  const go = useCallback((i: number) => {
    const track = trackRef.current;
    if (!track) return;
    const clamped = Math.max(0, Math.min(slides.length - 1, i));
    const el = track.children[clamped] as HTMLElement | undefined;
    if (!el) return;
    track.scrollTo({
      left: el.offsetLeft + el.offsetWidth / 2 - track.clientWidth / 2,
      behavior: "smooth",
    });
  }, [slides.length]);

  const many = slides.length > 1;

  return (
    <div
      className="relative -mx-6 sm:mx-0"
      role="region"
      aria-roledescription="carousel"
      aria-label={label}
      onKeyDown={(e) => {
        if (e.key === "ArrowRight") { e.preventDefault(); go(active + 1); }
        if (e.key === "ArrowLeft") { e.preventDefault(); go(active - 1); }
      }}
    >
      <div
        ref={trackRef}
        className="no-scrollbar flex snap-x snap-mandatory gap-4 overflow-x-auto pt-6 pb-4 sm:gap-8"
        style={{ paddingInline: "calc(50% - var(--slide-w) / 2)", ["--slide-w" as string]: "min(260px, 68vw)" }}
      >
        {slides.map((slide, i) => {
          const isActive = i === active;
          return (
            <figure
              key={slide.title}
              className="flex w-[var(--slide-w)] shrink-0 snap-center flex-col items-center text-center"
              aria-roledescription="slide"
              aria-label={`${i + 1} of ${slides.length}: ${slide.caption}`}
            >
              <button
                type="button"
                tabIndex={isActive ? -1 : 0}
                onClick={() => !isActive && go(i)}
                aria-label={isActive ? undefined : `Show ${slide.caption}`}
                className={`relative block w-full origin-center transition-[transform,opacity,filter] duration-500 ease-out motion-reduce:transition-none ${
                  isActive ? "scale-100 opacity-100" : "scale-[0.86] cursor-pointer opacity-45 saturate-[0.6]"
                }`}
              >
                {/* Feature-coloured glow, only behind the lit phone. */}
                <span
                  aria-hidden
                  className={`pointer-events-none absolute inset-x-[-18%] top-[8%] bottom-[8%] rounded-full blur-3xl transition-opacity duration-500 ${isActive ? "opacity-100" : "opacity-0"}`}
                  style={{ background: `radial-gradient(closest-side, ${slide.color}55, transparent)` }}
                />
                <span className="iphone-frame relative block">
                  <ShotImage
                    src={slide.screenshot}
                    alt={`${slide.caption} in the Mile A Day app`}
                  />
                </span>
              </button>
              <figcaption
                className={`mt-6 transition-opacity duration-500 ${isActive ? "opacity-100" : "opacity-0"}`}
                aria-hidden={!isActive}
              >
                <h3 className="font-heading text-[24px] uppercase tracking-[1px] text-[#f5f5f5]">
                  {slide.caption}
                </h3>
                <p className="mx-auto mt-1.5 max-w-[17rem] text-sm leading-relaxed text-[#a0a0a0]">
                  {slide.blurb}
                </p>
              </figcaption>
            </figure>
          );
        })}
      </div>

      {many && (
        <>
          <button
            type="button"
            onClick={() => go(active - 1)}
            disabled={active === 0}
            aria-label="Previous screenshot"
            className="absolute left-2 top-[calc(50%-48px)] hidden h-11 w-11 -translate-y-1/2 items-center justify-center rounded-full border border-white/10 bg-black/60 text-white backdrop-blur transition hover:bg-black/80 disabled:pointer-events-none disabled:opacity-0 sm:flex"
          >
            <ChevronLeft className="h-5 w-5" />
          </button>
          <button
            type="button"
            onClick={() => go(active + 1)}
            disabled={active === slides.length - 1}
            aria-label="Next screenshot"
            className="absolute right-2 top-[calc(50%-48px)] hidden h-11 w-11 -translate-y-1/2 items-center justify-center rounded-full border border-white/10 bg-black/60 text-white backdrop-blur transition hover:bg-black/80 disabled:pointer-events-none disabled:opacity-0 sm:flex"
          >
            <ChevronRight className="h-5 w-5" />
          </button>
          <div className="mt-2 flex justify-center gap-2">
            {slides.map((slide, i) => (
              <button
                key={slide.title}
                type="button"
                onClick={() => go(i)}
                aria-label={`Show ${slide.caption}`}
                aria-current={i === active}
                className={`h-2 rounded-full transition-all duration-300 ${i === active ? "w-6 bg-[#c72554]" : "w-2 bg-white/25 hover:bg-white/40"}`}
              />
            ))}
          </div>
        </>
      )}
    </div>
  );
}

/**
 * One screenshot at its true aspect ratio, with the loader on the screen until
 * the picture has arrived; then the picture fades in over it. The box is sized
 * up front, so nothing in the carousel moves when it lands.
 */
function ShotImage({ src, alt }: { src: string; alt: string }) {
  const [loaded, setLoaded] = useState(false);
  return (
    <span className="relative block" style={{ aspectRatio: `${SHOT_W} / ${SHOT_H}` }}>
      {!loaded && <ScreenshotLoader />}
      <Image
        src={src}
        alt={alt}
        width={SHOT_W}
        height={SHOT_H}
        // Pre-sized WebP served straight from the CDN: the optimizer's
        // first-request AVIF encode of a full-screen capture is what made
        // these slow to appear.
        unoptimized
        onLoad={() => setLoaded(true)}
        className={`block h-full w-full transition-opacity duration-500 motion-reduce:transition-none ${loaded ? "opacity-100" : "opacity-0"}`}
      />
    </span>
  );
}
