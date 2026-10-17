"use client";

import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import {
  APP_STORE_URL,
  PRODUCTS,
  SITE_URL,
  SUPPORT_EMAIL,
  checkoutUrl,
  formatPrice,
  isBuyable,
  statusLabel,
  type Product,
} from "@/lib/catalog";
import { THEME_KEY, type ThemeChoice } from "@/lib/theme";
import { FlameyShape, SharedDefs } from "./designs";
import { Garment3D, SIDE_TURN, TURN_EASE, garmentWidth, hungSize } from "./garment";

const pad = (n: number) => String(n).padStart(2, "0");
const SIDE_COS = Math.abs(Math.cos((SIDE_TURN * Math.PI) / 180));

export function Shop() {
  const [active, setActive] = useState(0);
  const [open, setOpen] = useState<number | null>(null);

  // A shared link (mileaday.shop/#extra-mile-hoodie) opens that piece.
  useEffect(() => {
    const i = PRODUCTS.findIndex((p) => `#${p.id}` === window.location.hash);
    if (i >= 0) {
      setActive(i);
      setOpen(i);
    }
  }, []);

  const show = useCallback((i: number | null) => {
    setOpen(i);
    if (i != null) setActive(i);
    window.history.replaceState(null, "", i == null ? window.location.pathname : `#${PRODUCTS[i].id}`);
  }, []);

  return (
    <div className="backdrop flex min-h-dvh flex-col">
      <SharedDefs />
      <Header />

      <main className="relative flex flex-1 flex-col justify-center pb-6" aria-hidden={open != null}>
        <div className="rise mx-auto mb-6 flex w-full max-w-6xl items-end justify-center gap-6 px-4 sm:justify-between sm:px-8 md:mb-10">
          <p className="font-heading text-[13px] tracking-[0.28em] text-ink-soft">
            DROP 01 <span className="text-mad-red">/</span> FALL 2026
          </p>
          <p className="hidden font-heading text-[13px] tracking-[0.28em] text-ink-soft md:block">
            HOVER TO TURN · CLICK TO OPEN
          </p>
        </div>

        <DesktopRack active={active} onHover={setActive} onOpen={show} />
        <MobileRack active={active} onActive={setActive} onOpen={show} />

        <Caption product={PRODUCTS[active]} index={active} onOpen={() => show(active)} />
      </main>

      <Ticker />
      <Footer />

      {open != null && <Detail index={open} onClose={() => show(null)} onGo={show} />}
    </div>
  );
}

// ── Header + theme ─────────────────────────────────────────────────────────

function Header() {
  return (
    <header className="relative z-10 mx-auto flex w-full max-w-6xl items-center justify-between px-4 pt-5 sm:px-8 sm:pt-7">
      <a
        href={SITE_URL}
        className="hidden w-36 font-heading text-[15px] tracking-[0.2em] text-ink-soft transition-colors hover:text-ink sm:block"
      >
        THE APP
      </a>
      <a href="/" className="flex items-center gap-2.5" aria-label="Mile A Day Shop">
        <img src="/mad-icon.png" alt="" className="h-8 w-8 rounded-full shadow-md sm:h-9 sm:w-9" />
        <span className="font-heading text-[21px] leading-none tracking-[0.16em] sm:text-[26px] sm:tracking-[0.18em]">
          MILE A DAY <span className="text-mad-red">SHOP</span>
        </span>
      </a>
      <div className="flex items-center justify-end gap-3 sm:w-36 sm:gap-4">
        <ThemeToggle />
        <a
          href={APP_STORE_URL}
          className="font-heading text-[15px] tracking-[0.2em] text-ink-soft transition-colors hover:text-ink"
        >
          APP ↗
        </a>
      </div>
    </header>
  );
}

const THEME_NEXT: Record<ThemeChoice, ThemeChoice> = { system: "light", light: "dark", dark: "system" };

function ThemeToggle() {
  const [choice, setChoice] = useState<ThemeChoice>("system");
  useEffect(() => {
    try {
      const t = localStorage.getItem(THEME_KEY);
      if (t === "light" || t === "dark") setChoice(t);
    } catch {}
  }, []);

  const pick = (next: ThemeChoice) => {
    setChoice(next);
    const root = document.documentElement;
    if (next === "system") delete root.dataset.theme;
    else root.dataset.theme = next;
    try {
      if (next === "system") localStorage.removeItem(THEME_KEY);
      else localStorage.setItem(THEME_KEY, next);
    } catch {}
  };

  const label = choice === "system" ? "Theme: matches your device" : `Theme: ${choice}`;
  return (
    <button
      type="button"
      onClick={() => pick(THEME_NEXT[choice])}
      aria-label={`${label}. Switch theme`}
      title={label}
      className="flex h-9 w-9 items-center justify-center rounded-full border border-line text-ink-soft transition-colors hover:text-ink"
    >
      <svg viewBox="0 0 24 24" className="h-[18px] w-[18px]" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
        {choice === "light" && (
          <>
            <circle cx="12" cy="12" r="4.2" />
            {[0, 45, 90, 135, 180, 225, 270, 315].map((a) => (
              <path key={a} d="M12 2.8v2.2" transform={`rotate(${a} 12 12)`} />
            ))}
          </>
        )}
        {choice === "dark" && <path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5Z" />}
        {choice === "system" && (
          <>
            <circle cx="12" cy="12" r="8" />
            <path d="M12 4a8 8 0 0 1 0 16Z" fill="currentColor" />
          </>
        )}
      </svg>
    </button>
  );
}

// ── Desktop: every piece hangs side-on; hover turns one to face you. ───────

function DesktopRack({
  active,
  onHover,
  onOpen,
}: {
  active: number;
  onHover: (i: number) => void;
  onOpen: (i: number) => void;
}) {
  const [hover, setHover] = useState<number | null>(null);
  const [flipped, setFlipped] = useState(false);
  const height = useDesktopGarmentHeight();
  const box = useRef<HTMLDivElement>(null);
  const [boxW, setBoxW] = useState(1100);
  const swingRefs = useRef<(HTMLDivElement | null)[]>([]);

  useLayoutEffect(() => {
    const el = box.current;
    if (!el) return;
    const ro = new ResizeObserver(() => setBoxW(el.clientWidth));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  // Slots: a side-on piece takes its edge-on width, the turned one its full
  // width. Everything slides on transforms, so it stays smooth.
  const gap = height * 0.07;
  let cursor = 0;
  const layout = PRODUCTS.map((p, i) => {
    const w = garmentWidth(p, height);
    const slot = hover === i ? w + gap * 3 : w * SIDE_COS + gap;
    const x = cursor;
    cursor += slot;
    return { w, slot, x };
  });
  const offset = (boxW - cursor) / 2;
  const tallest = Math.max(...PRODUCTS.map((p) => hungSize(p, height).height));

  const enter = (i: number) => {
    if (hover === i) return;
    setHover(i);
    setFlipped(false);
    onHover(i);
    const el = swingRefs.current[i];
    if (el) {
      el.classList.remove("swing");
      void el.offsetWidth; // restart the animation
      el.classList.add("swing");
    }
  };

  return (
    <div className="relative mx-auto hidden w-full max-w-6xl px-8 md:block">
      <Rail />
      <div
        ref={box}
        className="relative"
        style={{ height: tallest + 60 }}
        onMouseLeave={() => {
          setHover(null);
          setFlipped(false);
        }}
      >
        {PRODUCTS.map((p, i) => {
          const { w, x, slot } = layout[i];
          const isHover = hover === i;
          return (
            <div
              key={p.id}
              className="rack-slot pointer-events-none absolute left-0 top-0"
              style={{
                transform: `translateX(${offset + x + slot / 2 - w / 2}px)`,
                transition: `transform 0.8s ${TURN_EASE}`,
                zIndex: isHover ? 30 : active === i ? 20 : 10 + i,
              }}
            >
              <div className="drop-in" style={{ animationDelay: `${120 + i * 80}ms` }}>
                <div
                  ref={(el) => {
                    swingRefs.current[i] = el;
                  }}
                  className="origin-top"
                  style={{ marginTop: -3 }}
                >
                  <Garment3D product={p} height={height} turn={isHover ? (flipped ? 180 : 0) : SIDE_TURN} />
                </div>
              </div>
            </div>
          );
        })}

        {/* Hit areas, one per slot, above the art: hover turns, click opens. */}
        {PRODUCTS.map((p, i) => {
          const { x, slot } = layout[i];
          return (
            <button
              key={p.id}
              type="button"
              onMouseEnter={() => enter(i)}
              onFocus={() => enter(i)}
              onClick={() => onOpen(i)}
              aria-label={`${p.name}, ${p.colorName}. ${statusLabel(p)}. Open details`}
              className="absolute left-0 top-0 z-40 cursor-pointer rounded-xl outline-none focus-visible:ring-2 focus-visible:ring-mad-red/60"
              style={{
                width: slot,
                height: tallest,
                transform: `translateX(${offset + x}px)`,
                transition: `transform 0.8s ${TURN_EASE}, width 0.8s ${TURN_EASE}`,
              }}
            />
          );
        })}

        {hover != null && (
          <div
            className="absolute left-0 z-50"
            style={{
              top: hungSize(PRODUCTS[hover], height).height + 12,
              transform: `translateX(${offset + layout[hover].x + layout[hover].slot / 2}px) translateX(-50%)`,
              transition: `transform 0.8s ${TURN_EASE}`,
            }}
          >
            <FlipButton flipped={flipped} onClick={() => setFlipped((f) => !f)} />
          </div>
        )}
      </div>
    </div>
  );
}

function FlipButton({ flipped, onClick }: { flipped: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="fade inline-flex items-center gap-1.5 whitespace-nowrap rounded-full border border-line bg-card px-3.5 py-1.5 font-heading text-[13px] tracking-[0.2em] text-ink shadow-sm backdrop-blur transition-colors duration-200 hover:bg-ink hover:text-paper"
    >
      <svg viewBox="0 0 24 24" className="h-3.5 w-3.5" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        <path d="M3 12a9 9 0 0 1 15.5-6.2L21 8" />
        <path d="M21 3v5h-5" />
        <path d="M21 12a9 9 0 0 1-15.5 6.2L3 16" />
        <path d="M3 21v-5h5" />
      </svg>
      {flipped ? "SEE FRONT" : "SEE BACK"}
    </button>
  );
}

function useDesktopGarmentHeight() {
  const [h, setH] = useState(240);
  useEffect(() => {
    const fit = () => {
      const byWidth = (Math.min(window.innerWidth, 1152) - 64) / 3.6;
      const byHeight = window.innerHeight * 0.36;
      setH(Math.round(Math.max(160, Math.min(320, byWidth, byHeight))));
    };
    fit();
    window.addEventListener("resize", fit);
    return () => window.removeEventListener("resize", fit);
  }, []);
  return h;
}

function Rail() {
  return (
    <div className="pointer-events-none absolute inset-x-4 top-0 z-0 sm:inset-x-6" aria-hidden="true">
      <div className="rail h-[9px] rounded-full" />
      <div className="rail-cap absolute -left-1 -top-[5px] h-[19px] w-[19px] rounded-full" />
      <div className="rail-cap absolute -right-1 -top-[5px] h-[19px] w-[19px] rounded-full" />
    </div>
  );
}

// ── Mobile: swipe the rail; the centred piece turns to face you. ──────────

function MobileRack({
  active,
  onActive,
  onOpen,
}: {
  active: number;
  onActive: (i: number) => void;
  onOpen: (i: number) => void;
}) {
  const scroller = useRef<HTMLDivElement>(null);
  const items = useRef<(HTMLDivElement | null)[]>([]);
  const [itemW, setItemW] = useState(240);
  const [flipped, setFlipped] = useState(false);

  useEffect(() => {
    const fit = () => setItemW(Math.round(Math.min(window.innerWidth * 0.62, 320)));
    fit();
    window.addEventListener("resize", fit);
    return () => window.removeEventListener("resize", fit);
  }, []);

  // Sized so the widest piece (the hoodie) fits its slot when facing you.
  const garmentH = Math.round(itemW / Math.max(...PRODUCTS.map((p) => garmentWidth(p, 1))));
  const tallest = Math.max(...PRODUCTS.map((p) => hungSize(p, garmentH).height));

  const paint = useCallback(() => {
    const el = scroller.current;
    if (!el) return;
    const pos = el.scrollLeft / itemW;
    items.current.forEach((node, i) => {
      if (!node) return;
      const d = Math.max(-3, Math.min(3, i - pos));
      const a = Math.abs(d);
      const near = Math.min(a, 1);
      // Neighbours slide in tight, the way side-on pieces pack on a rail.
      const shift = -Math.sign(d) * (0.3 * near + 0.66 * Math.max(0, a - 1)) * itemW;
      node.style.transform = `translateX(${shift}px) perspective(1600px) rotateY(${SIDE_TURN * near}deg) scale(${1 - 0.1 * near})`;
      node.style.opacity = String(1 - 0.15 * near - 0.12 * Math.max(0, a - 1));
      node.style.zIndex = String(30 - Math.round(a * 4));
    });
    onActive(Math.max(0, Math.min(PRODUCTS.length - 1, Math.round(pos))));
  }, [itemW, onActive]);

  useEffect(() => {
    const el = scroller.current;
    if (!el) return;
    let raf = 0;
    const onScroll = () => {
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(paint);
    };
    paint();
    el.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      el.removeEventListener("scroll", onScroll);
      cancelAnimationFrame(raf);
    };
  }, [paint]);

  useEffect(() => setFlipped(false), [active]);

  // Keep the rail on the active piece (e.g. after browsing in the detail view).
  useEffect(() => {
    const el = scroller.current;
    if (!el) return;
    const target = active * itemW;
    if (Math.abs(el.scrollLeft - target) > itemW / 2) el.scrollTo({ left: target, behavior: "smooth" });
  }, [active, itemW]);

  return (
    <div className="relative md:hidden">
      <Rail />
      <div
        ref={scroller}
        className="no-scrollbar relative flex snap-x snap-mandatory overflow-x-auto overflow-y-hidden"
        style={{ paddingInline: `calc(50vw - ${itemW / 2}px)`, height: tallest + 8 }}
      >
        {PRODUCTS.map((p, i) => (
          <div key={p.id} className="flex shrink-0 snap-center justify-center" style={{ width: itemW }}>
            <div
              ref={(el) => {
                items.current[i] = el;
              }}
              className="garment-3d"
              style={{ marginTop: -3 }}
            >
              <button
                type="button"
                onClick={() => {
                  if (i === active) onOpen(i);
                  else scroller.current?.scrollTo({ left: i * itemW, behavior: "smooth" });
                }}
                aria-label={`${p.name}, ${p.colorName}. ${statusLabel(p)}`}
                className="garment-3d block outline-none"
              >
                <Garment3D product={p} height={garmentH} turn={i === active && flipped ? 180 : 0} />
              </button>
            </div>
          </div>
        ))}
      </div>
      <div className="mt-3 flex items-center justify-center gap-4">
        <div className="flex gap-1.5" aria-hidden="true">
          {PRODUCTS.map((p, i) => (
            <span
              key={p.id}
              className="h-1.5 rounded-full transition-all duration-300"
              style={{ width: i === active ? 18 : 6, background: i === active ? "var(--mad-red)" : "var(--line)" }}
            />
          ))}
        </div>
        <FlipButton flipped={flipped} onClick={() => setFlipped((f) => !f)} />
      </div>
    </div>
  );
}

// ── The line under the rack: whatever you're looking at. ────────────────────

function Caption({ product, index, onOpen }: { product: Product; index: number; onOpen: () => void }) {
  return (
    <div className="mx-auto mt-5 flex w-full max-w-6xl flex-col items-center px-4 text-center sm:px-8 md:mt-2">
      <div key={product.id} className="rise flex flex-col items-center">
        <p className="font-heading text-[13px] tracking-[0.28em] text-ink-soft">
          {pad(index + 1)} / {pad(PRODUCTS.length)} · {product.colorName.toUpperCase()}
        </p>
        <h1 className="mt-1 font-heading text-[38px] leading-[0.95] tracking-[0.02em] sm:text-[52px]">{product.name}</h1>
        <p className="mt-2 flex items-center gap-2 text-[14px] text-ink-soft">
          <StatusDot product={product} />
          {statusLabel(product)}
          {product.price != null && (
            <>
              <span className="opacity-40">·</span>
              <span className="font-semibold text-ink">{formatPrice(product.price)}</span>
            </>
          )}
        </p>
      </div>
      <button
        type="button"
        onClick={onOpen}
        className="group mt-5 inline-flex items-center gap-2 rounded-full border border-ink/70 px-6 py-2.5 font-heading text-[15px] tracking-[0.2em] transition-colors duration-300 hover:bg-ink hover:text-paper"
      >
        SEE THE PIECE
        <span className="transition-transform duration-300 group-hover:translate-x-0.5">→</span>
      </button>
    </div>
  );
}

function StatusDot({ product }: { product: Product }) {
  const live = isBuyable(product);
  const color = live ? "#1f9d55" : product.status === "later" ? "var(--ink-soft)" : "var(--mad-red)";
  return (
    <span className="relative inline-flex h-2 w-2">
      {product.status === "available" && (
        <span className="absolute inline-flex h-full w-full animate-ping rounded-full opacity-60" style={{ background: color }} />
      )}
      <span className="relative inline-flex h-2 w-2 rounded-full" style={{ background: color }} />
    </span>
  );
}

// ── Detail: the rack blurs back, the piece turns to you; drag to spin. ─────

function Detail({ index, onClose, onGo }: { index: number; onClose: () => void; onGo: (i: number) => void }) {
  const product = PRODUCTS[index];
  const [turn, setTurn] = useState(SIDE_TURN);
  const [dragging, setDragging] = useState(false);
  const [size, setSize] = useState<string | null>(null);
  const drag = useRef<{ x: number; start: number; moved: boolean } | null>(null);
  const height = useDetailHeight(product);

  const go = useCallback((delta: number) => onGo((index + delta + PRODUCTS.length) % PRODUCTS.length), [index, onGo]);

  // Every piece arrives side-on and turns to face you.
  useEffect(() => {
    setSize(null);
    setTurn(SIDE_TURN);
    let id = requestAnimationFrame(() => {
      id = requestAnimationFrame(() => setTurn(0));
    });
    return () => cancelAnimationFrame(id);
  }, [index]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
      if (e.key === "ArrowRight") go(1);
      if (e.key === "ArrowLeft") go(-1);
    };
    window.addEventListener("keydown", onKey);
    const overflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = overflow;
    };
  }, [go, onClose]);

  const showingBack = Math.abs(Math.round(turn / 180)) % 2 === 1;
  const showSide = (back: boolean) =>
    setTurn((t) => {
      const n = Math.round(t / 180);
      return (Math.abs(n) % 2 === 1) === back ? n * 180 : (n + 1) * 180;
    });
  const settle = () => {
    drag.current = null;
    setDragging(false);
    setTurn((t) => Math.round(t / 180) * 180);
  };

  const url = size ? checkoutUrl(product, size) : null;
  const buyable = isBuyable(product);

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={product.name}
      className="fade fixed inset-0 z-50 overflow-y-auto overflow-x-hidden backdrop-blur-xl"
      style={{ background: "var(--scrim)" }}
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="pointer-events-none sticky top-0 z-10 flex justify-between px-4 pt-4 sm:px-8 sm:pt-6">
        <p className="pointer-events-auto rounded-full border border-line bg-card px-3.5 py-2 font-heading text-[13px] tracking-[0.28em] text-ink-soft shadow-sm backdrop-blur">
          {pad(index + 1)} / {pad(PRODUCTS.length)}
        </p>
        <button
          type="button"
          onClick={onClose}
          className="pointer-events-auto rounded-full bg-ink px-4 py-2 font-heading text-[14px] tracking-[0.2em] text-paper shadow-lg transition-transform duration-300 hover:scale-105"
        >
          CLOSE ✕
        </button>
      </div>

      <div
        className="mx-auto grid min-h-[calc(100dvh-64px)] max-w-6xl items-center gap-6 px-4 pb-10 sm:px-8 md:grid-cols-[minmax(0,1.15fr)_minmax(0,1fr)] md:gap-12"
        onClick={(e) => {
          if (e.target === e.currentTarget) onClose();
        }}
      >
        {/* The piece */}
        <div className="sheet-up relative flex flex-col items-center">
          <div
            className="relative flex w-full touch-pan-y select-none justify-center"
            style={{ cursor: dragging ? "grabbing" : "grab" }}
            onPointerDown={(e) => {
              drag.current = { x: e.clientX, start: turn, moved: false };
              e.currentTarget.setPointerCapture(e.pointerId);
            }}
            onPointerMove={(e) => {
              const d = drag.current;
              if (!d) return;
              const dx = e.clientX - d.x;
              if (!d.moved && Math.abs(dx) < 4) return;
              d.moved = true;
              setDragging(true);
              setTurn(d.start + dx * 0.55);
            }}
            onPointerUp={settle}
            onPointerCancel={settle}
          >
            <div className="rail absolute left-1/2 top-[2px] h-[9px] w-[min(72%,380px)] -translate-x-1/2 rounded-full" aria-hidden="true" />
            <div key={index} className="swing origin-top">
              <Garment3D
                product={product}
                height={height}
                turn={turn}
                transition={dragging ? "none" : `transform 0.9s ${TURN_EASE}, --side 0.9s ${TURN_EASE}`}
              />
            </div>
          </div>

          <div className="mt-5 inline-flex rounded-full border border-line bg-card p-1 backdrop-blur">
            {([false, true] as const).map((back) => (
              <button
                key={String(back)}
                type="button"
                onClick={() => showSide(back)}
                className={`rounded-full px-5 py-1.5 font-heading text-[14px] tracking-[0.2em] transition-colors duration-300 ${
                  showingBack === back ? "bg-ink text-paper" : "text-ink-soft hover:text-ink"
                }`}
              >
                {back ? "BACK" : "FRONT"}
              </button>
            ))}
          </div>
          <p className="mt-2 text-[12px] text-ink-soft">Drag to spin it</p>

          <div className="mt-4 flex items-center gap-3">
            <ArrowButton label="Previous piece" onClick={() => go(-1)}>
              ←
            </ArrowButton>
            <ArrowButton label="Next piece" onClick={() => go(1)}>
              →
            </ArrowButton>
          </div>
        </div>

        {/* The facts */}
        <div
          key={product.id}
          className="sheet-up rounded-3xl border border-line bg-card p-6 shadow-[0_30px_80px_-30px_rgba(0,0,0,0.35)] backdrop-blur-xl sm:p-8"
          style={{ animationDelay: "80ms" }}
        >
          <p className="flex items-center gap-2 text-[13px] text-ink-soft">
            <StatusDot product={product} />
            {statusLabel(product)}
          </p>
          <h2 className="mt-2 font-heading text-[42px] leading-[0.92] sm:text-[54px]">{product.name}</h2>
          <p className="mt-1 text-[15px] text-ink-soft">{product.kind}</p>

          {product.price != null && (
            <p className="mt-4 font-heading text-[34px] leading-none tracking-[0.02em]">{formatPrice(product.price)}</p>
          )}

          <p className="mt-4 text-[15px] leading-relaxed opacity-80">{product.description}</p>

          <div className="mt-5 flex items-center gap-2.5">
            <span className="h-5 w-5 rounded-full border border-line shadow-inner" style={{ background: product.swatch }} aria-hidden="true" />
            <span className="text-[14px] font-medium">{product.colorName}</span>
          </div>

          <fieldset className="mt-5" disabled={product.status !== "available"}>
            <legend className="mb-2 font-heading text-[13px] tracking-[0.24em] text-ink-soft">SIZE</legend>
            <div className="grid grid-cols-5 gap-2">
              {product.sizes.map((s) => (
                <button
                  key={s}
                  type="button"
                  onClick={() => setSize(s)}
                  aria-pressed={size === s}
                  className={`rounded-xl border py-2.5 text-[14px] font-semibold transition-colors duration-200 disabled:cursor-not-allowed disabled:opacity-40 ${
                    size === s ? "border-ink bg-ink text-paper" : "border-line hover:border-ink/60"
                  }`}
                >
                  {s}
                </button>
              ))}
            </div>
          </fieldset>

          <div className="mt-5">
            {url ? (
              <a
                href={url}
                className="block w-full rounded-full bg-mad-red py-4 text-center font-heading text-[19px] tracking-[0.18em] text-white shadow-[0_14px_30px_-12px_rgba(199,37,84,0.8)] transition-transform duration-200 hover:scale-[1.015] active:scale-[0.99]"
              >
                BUY · {size} · {formatPrice(product.price)}
              </a>
            ) : (
              <button
                type="button"
                disabled
                className="block w-full cursor-not-allowed rounded-full bg-ink py-4 text-center font-heading text-[19px] tracking-[0.18em] text-paper opacity-90"
              >
                {buyable ? "PICK A SIZE" : statusLabel(product).toUpperCase()}
              </button>
            )}
            {!buyable && (
              <p className="mt-3 text-center text-[13px] text-ink-soft">
                Want to know the moment it drops?{" "}
                <a href={APP_STORE_URL} className="font-semibold text-ink underline decoration-mad-red decoration-2 underline-offset-4">
                  Get the app
                </a>
              </p>
            )}
          </div>

          <ul className="mt-6 space-y-2 border-t border-line pt-5">
            {product.details.map((d) => (
              <li key={d} className="flex gap-2.5 text-[14px] opacity-80">
                <span className="mt-[7px] h-1.5 w-1.5 shrink-0 rounded-full bg-mad-red" />
                {d}
              </li>
            ))}
          </ul>
        </div>
      </div>
    </div>
  );
}

function useDetailHeight(product: Product) {
  const [h, setH] = useState(380);
  useEffect(() => {
    const fit = () => {
      const w = window.innerWidth;
      const maxW = w < 768 ? w - 48 : Math.min(w * 0.46, 600);
      const byW = maxW / (garmentWidth(product, 100) / 100);
      setH(Math.round(Math.min(byW, window.innerHeight * (w < 768 ? 0.4 : 0.56), 500)));
    };
    fit();
    window.addEventListener("resize", fit);
    return () => window.removeEventListener("resize", fit);
  }, [product]);
  return h;
}

function ArrowButton({ label, onClick, children }: { label: string; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={label}
      className="flex h-11 w-11 items-center justify-center rounded-full border border-line bg-card text-[18px] backdrop-blur transition-colors duration-200 hover:bg-ink hover:text-paper"
    >
      {children}
    </button>
  );
}

// ── Ticker + footer ────────────────────────────────────────────────────────

const TICKER = [
  "GO THE EXTRA MILE",
  "ONE MILE. EVERY DAY.",
  "DROP 01: THE EXTRA MILE HOODIE",
  "TEES, LONG SLEEVES + TANKS ON THE WAY",
  "FLAMEY MERCH COMING LATER",
  "DON'T BREAK THE STREAK",
];

function Ticker() {
  const row = (
    <div className="flex shrink-0 items-center">
      {TICKER.map((t) => (
        <span key={t} className="flex items-center">
          <span className="px-5 font-heading text-[17px] tracking-[0.2em] sm:text-[19px]">{t}</span>
          <svg viewBox="0 0 200 240" className="h-[18px] w-[15px]" aria-hidden="true">
            <FlameyShape />
          </svg>
        </span>
      ))}
    </div>
  );
  return (
    <div className="relative overflow-hidden bg-mad-red py-2.5 text-white" aria-label={TICKER.join(" · ")}>
      <div className="marquee flex w-max" aria-hidden="true">
        {row}
        {row}
      </div>
    </div>
  );
}

function Footer() {
  return (
    <footer style={{ background: "var(--footer)", color: "var(--footer-ink)" }}>
      <div className="mx-auto flex max-w-6xl flex-col items-center justify-between gap-2 px-4 py-4 text-[12px] sm:flex-row sm:px-8">
        <p>© {new Date().getFullYear()} Mile A Day</p>
        <nav className="flex flex-wrap items-center justify-center gap-x-5 gap-y-1 [&_a]:transition-colors [&_a:hover]:text-white">
          <a href={SITE_URL}>mileaday.run</a>
          <a href={`mailto:${SUPPORT_EMAIL}?subject=${encodeURIComponent("Mile A Day Shop")}`}>Contact</a>
          <a href={`${SITE_URL}/privacy`}>Privacy</a>
          <a href="https://instagram.com/mileadayapp">Instagram</a>
          <a href="https://tiktok.com/@mileadayapp">TikTok</a>
        </nav>
      </div>
    </footer>
  );
}
