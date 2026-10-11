"use client";

import { useEffect, useRef, useState } from "react";
import { drawLeds, frameToImage, loadDeskEngine, localDate, type DeskEngine } from "@/lib/desk-engine";

/**
 * A live Mile A Day desk box: the box's own code running here on real
 * community numbers, drawn as an LED panel in its case.
 *
 * Like the real box: tap it for a little hop, double-tap for the next style,
 * and shake it (drag it side to side fast) and the mascot gets dizzy.
 */
export function DeskBox({ feed, style, mascot, bare = false, interactive = true, onNextStyle, className, maxDpr = 2 }: {
  feed: string | null;          // the /public/desk JSON
  style: number;
  mascot: number;
  bare?: boolean;               // just the LEDs (TV mode), no case
  interactive?: boolean;
  onNextStyle?: () => void;
  className?: string;
  maxDpr?: number;
}) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const halo = useRef<HTMLCanvasElement>(null);
  const engine = useRef<DeskEngine | null>(null);
  const t0 = useRef(0);
  const started = useRef(false);
  const [state, setState] = useState<"loading" | "ok" | "error">("loading");
  const [jiggle, setJiggle] = useState(0);
  const [tilt, setTilt] = useState({ x: 0, y: 0 });
  const now = () => (performance.now() - t0.current) / 1000;

  // start once the first feed is in
  useEffect(() => {
    if (!feed || started.current) return;
    let alive = true;
    let raf = 0;
    let last = 0;
    loadDeskEngine()
      .then((eng) => {
        if (!alive) return;
        engine.current = eng;
        t0.current = performance.now();
        eng.start(feed, style, mascot);
        eng.set_date(localDate());
        eng.sleep(1, -1, -1, 0);                       // a showpiece never sleeps
        started.current = true;
        setState("ok");
        const small = halo.current?.getContext("2d");
        const img = small?.createImageData(64, 32);
        const draw = (ts: number) => {
          raf = requestAnimationFrame(draw);
          if (ts - last < 40) return;                   // ~24 fps, like the box
          last = ts;
          const c = canvas.current;
          const ctx = c?.getContext("2d");
          if (!c || !ctx) return;
          const rgb = eng.frame(now());
          const w = c.width, h = c.height;
          drawLeds(ctx, rgb, 0, 0, w, h, w >= 400);
          if (small && img) {
            frameToImage(rgb, img);
            small.putImageData(img, 0, 0);
          }
        };
        raf = requestAnimationFrame(draw);
      })
      .catch(() => alive && setState("error"));
    return () => {
      alive = false;
      cancelAnimationFrame(raf);
      started.current = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [feed === null]);

  useEffect(() => {
    if (started.current && engine.current && feed) engine.current.feed(feed, now());
  }, [feed]);

  useEffect(() => {
    if (started.current && engine.current) engine.current.choose(style, mascot, now());
  }, [style, mascot]);

  // crisp canvas at the size it's shown
  useEffect(() => {
    const c = canvas.current;
    if (!c) return;
    const fit = () => {
      const dpr = Math.min(maxDpr, window.devicePixelRatio || 1);
      const w = Math.max(128, Math.round(c.clientWidth * dpr));
      c.width = w;
      c.height = Math.round(w / 2);
    };
    fit();
    const ro = new ResizeObserver(fit);
    ro.observe(c);
    return () => ro.disconnect();
  }, [maxDpr]);

  // tap / double-tap / shake (drag side to side)
  const gesture = useRef<{ x: number; at: number; moved: number; dir: number; flips: number[]; startX: number } | null>(null);
  const lastTap = useRef(0);
  const down = (e: React.PointerEvent) => {
    if (!interactive) return;
    (e.target as HTMLElement).setPointerCapture?.(e.pointerId);
    gesture.current = { x: e.clientX, at: performance.now(), moved: 0, dir: 0, flips: [], startX: e.clientX };
  };
  const move = (e: React.PointerEvent) => {
    if (!interactive) return;
    const g = gesture.current;
    if (!g) {
      const r = (e.currentTarget as HTMLElement).getBoundingClientRect();
      setTilt({ x: ((e.clientY - r.top) / r.height - 0.5) * -5, y: ((e.clientX - r.left) / r.width - 0.5) * 7 });
      return;
    }
    const dx = e.clientX - g.x;
    if (Math.abs(dx) < 3) return;
    const dir = Math.sign(dx);
    const t = performance.now();
    if (g.dir && dir !== g.dir) g.flips.push(t);
    g.dir = dir;
    g.moved += Math.abs(dx);
    g.x = e.clientX;
    setJiggle(Math.max(-18, Math.min(18, e.clientX - g.startX)));
    g.flips = g.flips.filter((f) => t - f < 1100);
    if (g.flips.length >= 4 && g.moved > 140 && engine.current) {
      engine.current.dizzy(now());
      g.flips = [];
      g.moved = 0;
    }
  };
  const up = () => {
    const g = gesture.current;
    gesture.current = null;
    setJiggle(0);
    if (!g || !engine.current) return;
    if (g.moved < 8 && performance.now() - g.at < 350) {
      const t = performance.now();
      if (t - lastTap.current < 380) {
        lastTap.current = 0;
        onNextStyle?.();
      } else {
        lastTap.current = t;
        engine.current.poke(now());
      }
    }
  };
  const leave = () => { setTilt({ x: 0, y: 0 }); up(); };

  if (bare) {
    return (
      <div className={className} style={{ position: "relative", aspectRatio: "2 / 1", width: "100%" }}>
        <canvas ref={halo} width={64} height={32} aria-hidden
                style={{ position: "absolute", inset: "-6%", width: "112%", height: "112%", filter: "blur(40px)", opacity: 0.45 }} />
        <canvas ref={canvas} role="img" aria-label="Mile A Day desk box, live"
                style={{ position: "relative", display: "block", width: "100%", aspectRatio: "2 / 1" }} />
        {state !== "ok" && <Loading state={state} />}
      </div>
    );
  }

  return (
    <div className={`desk-scene ${className ?? ""}`}
         onPointerDown={down} onPointerMove={move} onPointerUp={up} onPointerCancel={up} onPointerLeave={leave}
         style={{ touchAction: interactive ? "pan-y" : undefined }}>
      <div className="desk-box"
           style={{ transform: `translateX(${jiggle}px) rotateX(${tilt.x}deg) rotateY(${tilt.y}deg) rotateZ(${jiggle * 0.15}deg)` }}>
        <div className="desk-bezel">
          <div className="desk-screen">
            <canvas ref={halo} width={64} height={32} aria-hidden className="desk-halo" />
            <canvas ref={canvas} role="img" aria-label="Mile A Day desk box showing live community stats"
                    className="desk-leds" />
            {state !== "ok" && <Loading state={state} />}
          </div>
          <span className="desk-board" aria-hidden />
          <svg className="desk-cable" viewBox="0 0 95 220" aria-hidden>
            <rect x="0" y="0" width="16" height="12" rx="3" fill="#2a2a2c" />
            <path d="M14 6 C 60 6, 80 40, 70 110 S 40 200, 95 215" fill="none" stroke="#151516" strokeWidth="7" strokeLinecap="round" />
            <path d="M14 5 C 60 5, 79 39, 69 109 S 39 199, 94 214" fill="none" stroke="rgba(255,255,255,0.08)" strokeWidth="1.5" />
          </svg>
        </div>
        <div className="desk-chin">
          <span className="desk-brand">MILE A DAY</span>
        </div>
      </div>
      <div className="desk-shadow" />
    </div>
  );
}

function Loading({ state }: { state: "loading" | "error" | "ok" }) {
  return (
    <div style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", justifyContent: "center",
                  color: "rgba(255,255,255,0.45)", fontSize: 12, letterSpacing: "0.08em", textTransform: "uppercase" }}>
      {state === "loading" ? "Powering on…" : "Couldn't start the preview"}
    </div>
  );
}
