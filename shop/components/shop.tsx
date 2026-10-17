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
import { SharedDefs } from "./designs";
import { Garment3D, SIDE_TURN, TURN_EASE, garmentWidth, hungSize } from "./garment";

const SIDE_COS = Math.abs(Math.cos((SIDE_TURN * Math.PI) / 180));
const HERO = PRODUCTS[0];
const GUTTER = "max(24px, calc((100vw - 1024px) / 2 + 24px))";

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
    <div className="flex min-h-dvh flex-col">
      <SharedDefs />
      <Ribbon onOpen={() => show(0)} />
      <Nav />

      <main aria-hidden={open != null}>
        <section className="spotlight relative pb-16 pt-12 sm:pt-16">
          <div className="rise mx-auto max-w-3xl px-6 text-center">
            <p className="text-[17px] font-semibold text-accent">Drop 01</p>
            <h1 className="display mt-1 text-[44px] leading-[1.05] sm:text-[64px]">Go the extra mile.</h1>
            <p className="mx-auto mt-3 max-w-xl text-[19px] leading-snug text-ink-soft sm:text-[21px]">
              Official Mile A Day apparel. Made for the people who show up every single day.
            </p>
          </div>

          <div className="mt-10 sm:mt-12">
            <DesktopRack active={active} onHover={setActive} onOpen={show} />
            <MobileRack active={active} onActive={setActive} onOpen={show} />
          </div>

          <Caption product={PRODUCTS[active]} onOpen={() => show(active)} />
        </section>

        <Collection onOpen={show} />
        <Promises />
      </main>

      <Footer />

      {open != null && <Detail index={open} onClose={() => show(null)} onGo={show} />}
    </div>
  );
}

// ── Ribbon + nav ───────────────────────────────────────────────────────────

function Ribbon({ onOpen }: { onOpen: () => void }) {
  return (
    <div className="bg-bg-2 px-4 py-2.5 text-center text-[13px] text-ink-soft">
      {isBuyable(HERO) ? "Drop 01 is here." : "Drop 01 is almost here."} The {HERO.name}.{" "}
      <button type="button" onClick={onOpen} className="text-accent hover:underline">
        Take a look ›
      </button>
    </div>
  );
}

function Nav() {
  return (
    <header className="glass sticky top-0 z-40 border-b border-line">
      <div className="mx-auto flex h-12 max-w-[1024px] items-center justify-between px-5">
        <a href="/" className="flex items-center gap-2" aria-label="Mile A Day Shop">
          <img src="/mad-icon.png" alt="" className="h-6 w-6 rounded-full" />
          <span className="text-[15px] font-semibold tracking-[-0.01em]">Mile A Day</span>
          <span className="text-[15px] text-ink-soft">Shop</span>
        </a>
        <nav className="flex items-center gap-1 text-[13px] sm:gap-5">
          <a href="#collection" className="hidden text-ink-soft transition-colors hover:text-ink sm:block">
            Collection
          </a>
          <a href={SITE_URL} className="hidden text-ink-soft transition-colors hover:text-ink sm:block">
            The App
          </a>
          <ThemeToggle />
          <a
            href={APP_STORE_URL}
            className="ml-1 rounded-full bg-ink px-3 py-1 text-[12px] font-medium text-bg transition-opacity hover:opacity-80"
          >
            Get the app
          </a>
        </nav>
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

  const label = choice === "system" ? "Appearance: matches your device" : `Appearance: ${choice}`;
  return (
    <button
      type="button"
      onClick={() => pick(THEME_NEXT[choice])}
      aria-label={`${label}. Change appearance`}
      title={label}
      className="flex h-8 w-8 items-center justify-center rounded-full text-ink-soft transition-colors hover:text-ink"
    >
      <svg viewBox="0 0 24 24" className="h-[17px] w-[17px]" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round">
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

// ── Desktop rack: everything hangs side-on; hover turns one to face you. ───

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
  const [boxW, setBoxW] = useState(980);
  const swingRefs = useRef<(HTMLDivElement | null)[]>([]);

  useLayoutEffect(() => {
    const el = box.current;
    if (!el) return;
    const ro = new ResizeObserver(() => setBoxW(el.clientWidth));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  // A side-on piece takes its edge-on width, the turned one its full width.
  // Everything slides on transforms, so it stays smooth.
  const gap = height * 0.08;
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
    <div className="relative mx-auto hidden w-full max-w-[1024px] px-6 md:block">
      <Rail />
      <div
        ref={box}
        className="relative"
        style={{ height: tallest + 56 }}
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
              <div className="drop-in" style={{ animationDelay: `${200 + i * 70}ms` }}>
                <div
                  ref={(el) => {
                    swingRefs.current[i] = el;
                  }}
                  className="origin-top"
                  style={{ marginTop: -2 }}
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
              className="absolute left-0 top-0 z-40 cursor-pointer rounded-2xl outline-none focus-visible:ring-2 focus-visible:ring-accent/60"
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
              top: hungSize(PRODUCTS[hover], height).height + 10,
              transform: `translateX(${offset + layout[hover].x + layout[hover].slot / 2}px) translateX(-50%)`,
              transition: `transform 0.8s ${TURN_EASE}`,
            }}
          >
            <SideSwitch back={flipped} onChange={setFlipped} small />
          </div>
        )}
      </div>
    </div>
  );
}

/** Apple-style segmented control: Front | Back. */
function SideSwitch({ back, onChange, small }: { back: boolean; onChange: (back: boolean) => void; small?: boolean }) {
  return (
    <div
      className={`fade relative inline-grid grid-cols-2 rounded-full bg-bg-2 p-[3px] ${small ? "text-[12px]" : "text-[14px]"}`}
      role="group"
      aria-label="Show side"
    >
      <span
        className="absolute inset-y-[3px] left-[3px] w-[calc(50%-3px)] rounded-full bg-surface shadow-[0_1px_4px_rgba(0,0,0,0.14)] transition-transform duration-300"
        style={{ transform: back ? "translateX(100%)" : "none", transitionTimingFunction: TURN_EASE }}
        aria-hidden="true"
      />
      {[false, true].map((b) => (
        <button
          key={String(b)}
          type="button"
          onClick={() => onChange(b)}
          aria-pressed={back === b}
          className={`relative z-10 rounded-full font-medium transition-colors ${small ? "px-3.5 py-1" : "px-6 py-1.5"} ${
            back === b ? "text-ink" : "text-ink-soft hover:text-ink"
          }`}
        >
          {b ? "Back" : "Front"}
        </button>
      ))}
    </div>
  );
}

function useDesktopGarmentHeight() {
  const [h, setH] = useState(240);
  useEffect(() => {
    const fit = () => {
      const byWidth = (Math.min(window.innerWidth, 1024) - 48) / 3.6;
      const byHeight = window.innerHeight * 0.31;
      setH(Math.round(Math.max(170, Math.min(290, byWidth, byHeight))));
    };
    fit();
    window.addEventListener("resize", fit);
    return () => window.removeEventListener("resize", fit);
  }, []);
  return h;
}

function Rail() {
  return (
    <div className="pointer-events-none absolute inset-x-6 top-[2px] z-0 sm:inset-x-10" aria-hidden="true">
      <div className="rail h-[5px] rounded-full" />
    </div>
  );
}

// ── Mobile rack: swipe the rail; the centred piece turns to face you. ─────

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
              style={{ marginTop: -2 }}
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
      <div className="mt-4 flex justify-center">
        <SideSwitch back={flipped} onChange={setFlipped} small />
      </div>
    </div>
  );
}

// ── Caption under the rack ─────────────────────────────────────────────────

function Caption({ product, onOpen }: { product: Product; onOpen: () => void }) {
  const buyable = isBuyable(product);
  return (
    <div className="mx-auto mt-6 flex max-w-xl flex-col items-center px-6 text-center md:mt-0">
      <div key={product.id} className="rise flex flex-col items-center">
        <Eyebrow product={product} />
        <h2 className="display mt-1 text-[28px] leading-tight sm:text-[32px]">{product.name}</h2>
        <p className="mt-1 text-[17px] text-ink-soft">
          {product.colorName}
          {product.price != null && ` · ${formatPrice(product.price)}`}
        </p>
      </div>
      <div className="mt-5 flex items-center gap-5">
        <button
          type="button"
          onClick={onOpen}
          className="rounded-full bg-accent px-6 py-2.5 text-[15px] font-medium text-white transition-[transform,opacity] duration-200 hover:opacity-90 active:scale-[0.97]"
        >
          {buyable ? "Buy" : "Take a look"}
        </button>
        <a href={APP_STORE_URL} className="text-[15px] text-accent hover:underline">
          Get notified in the app ›
        </a>
      </div>
    </div>
  );
}

function Eyebrow({ product, className = "" }: { product: Product; className?: string }) {
  const label = isBuyable(product) ? "New" : statusLabel(product);
  return (
    <p className={`text-[14px] font-semibold ${product.status === "later" ? "text-ink-soft" : "text-accent"} ${className}`}>
      {label}
    </p>
  );
}

// ── Collection: Apple-store cards, front turns to back on hover. ──────────

function Collection({ onOpen }: { onOpen: (i: number) => void }) {
  return (
    <section id="collection" className="scroll-mt-16 bg-bg-2 py-16 sm:py-20">
      <div className="mx-auto max-w-[1024px] px-6">
        <h2 className="display text-[32px] leading-tight sm:text-[44px]">
          The collection. <span className="text-ink-soft">Every piece, front and back.</span>
        </h2>
      </div>
      {/* Cards start in line with the heading and scroll to the window edge. */}
      <div
        className="no-scrollbar mt-6 flex snap-x snap-mandatory gap-5 overflow-x-auto py-4"
        style={{ paddingInline: GUTTER, scrollPaddingInline: GUTTER }}
      >
        {PRODUCTS.map((p, i) => (
          <CollectionCard key={p.id} product={p} onOpen={() => onOpen(i)} />
        ))}
        <div className="w-1 shrink-0" aria-hidden="true" />
      </div>
    </section>
  );
}

function CollectionCard({ product, onOpen }: { product: Product; onOpen: () => void }) {
  const [back, setBack] = useState(false);
  return (
    <button
      type="button"
      onClick={onOpen}
      onMouseEnter={() => setBack(true)}
      onMouseLeave={() => setBack(false)}
      onFocus={() => setBack(true)}
      onBlur={() => setBack(false)}
      aria-label={`${product.name}, ${product.colorName}. ${statusLabel(product)}`}
      className="group relative flex h-[440px] w-[300px] shrink-0 snap-start flex-col overflow-hidden rounded-[22px] bg-surface p-7 text-left shadow-[0_2px_12px_rgba(0,0,0,0.06)] transition-[transform,box-shadow] duration-500 hover:scale-[1.012] hover:shadow-[0_12px_36px_rgba(0,0,0,0.12)]"
      style={{ transitionTimingFunction: TURN_EASE }}
    >
      <Eyebrow product={product} className="text-[12px]" />
      <h3 className="display mt-1 text-[22px] leading-[1.15]">{product.name}</h3>
      <p className="mt-1 text-[14px] text-ink-soft">
        {product.colorName}
        {product.price != null && ` · ${formatPrice(product.price)}`}
      </p>
      <div className="mt-auto flex justify-center">
        <Garment3D product={product} height={product.art.kind === "photo" ? 196 : 222} turn={back ? 180 : 0} />
      </div>
      <span className="absolute bottom-5 right-5 flex h-8 w-8 items-center justify-center rounded-full bg-bg-2 text-ink-soft opacity-0 transition-opacity duration-300 group-hover:opacity-100">
        <svg viewBox="0 0 24 24" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" aria-hidden="true">
          <path d="M12 5v14M5 12h14" />
        </svg>
      </span>
    </button>
  );
}

// ── Promise row ────────────────────────────────────────────────────────────

const PROMISES = [
  { title: "Printed to order.", body: "Each piece is made when you order it, so nothing sits in a warehouse." },
  { title: "Designed for the daily mile.", body: "Every print comes from the app: the streak, the route, Flamey." },
  { title: "Questions? We answer.", body: `Write to ${SUPPORT_EMAIL} about sizing, orders or anything else.` },
];

function Promises() {
  return (
    <section className="mx-auto grid max-w-[1024px] gap-10 px-6 py-16 sm:grid-cols-3 sm:py-20">
      {PROMISES.map((p) => (
        <div key={p.title}>
          <h3 className="display text-[21px] leading-tight">{p.title}</h3>
          <p className="mt-2 text-[15px] leading-relaxed text-ink-soft">{p.body}</p>
        </div>
      ))}
    </section>
  );
}

// ── Detail: an Apple-style sheet. The piece turns in; drag to spin. ───────

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
      className="fade fixed inset-0 z-50 flex items-end justify-center overflow-hidden backdrop-blur-sm sm:items-center sm:p-6"
      style={{ background: "var(--scrim)" }}
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="sheet-in relative flex max-h-[94dvh] w-full max-w-[1040px] flex-col overflow-y-auto overscroll-contain rounded-t-[28px] bg-surface shadow-[0_30px_100px_rgba(0,0,0,0.35)] sm:rounded-[28px] md:grid md:grid-cols-[minmax(0,1.1fr)_minmax(0,1fr)] md:overflow-hidden">
        <button
          type="button"
          onClick={onClose}
          aria-label="Close"
          className="absolute right-4 top-4 z-20 flex h-9 w-9 items-center justify-center rounded-full bg-bg-2 text-ink-soft transition-colors hover:text-ink"
        >
          <svg viewBox="0 0 24 24" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" aria-hidden="true">
            <path d="M6 6l12 12M18 6L6 18" />
          </svg>
        </button>

        {/* The stage */}
        <div className="relative m-2 flex shrink-0 flex-col items-center rounded-[22px] bg-stage px-4 pb-5 pt-8 md:m-3 md:justify-center">
          <div className="spotlight pointer-events-none absolute inset-0 rounded-[22px]" aria-hidden="true" />
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
            <div className="rail absolute left-1/2 top-[2px] h-[5px] w-[min(70%,340px)] -translate-x-1/2 rounded-full" aria-hidden="true" />
            <div key={index} className="swing origin-top">
              <Garment3D
                product={product}
                height={height}
                turn={turn}
                transition={dragging ? "none" : `transform 0.9s ${TURN_EASE}, --side 0.9s ${TURN_EASE}`}
              />
            </div>
          </div>

          <div className="relative mt-5 flex w-full items-center justify-between">
            <RoundButton label="Previous piece" onClick={() => go(-1)}>
              <path d="M15 6l-6 6 6 6" />
            </RoundButton>
            <div className="flex flex-col items-center gap-1.5">
              <SideSwitch back={showingBack} onChange={showSide} />
              <p className="text-[12px] text-ink-soft">Drag to spin</p>
            </div>
            <RoundButton label="Next piece" onClick={() => go(1)}>
              <path d="M9 6l6 6-6 6" />
            </RoundButton>
          </div>
        </div>

        {/* The facts */}
        <div key={product.id} className="rise px-6 pb-8 pt-4 sm:px-8 md:overflow-y-auto md:py-12 md:pr-10">
          <Eyebrow product={product} />
          <h2 className="display mt-1 text-[32px] leading-[1.08] sm:text-[40px]">{product.name}</h2>
          <p className="mt-2 text-[17px] text-ink-soft">{product.kind}</p>
          {product.price != null && <p className="mt-4 text-[21px] font-medium">{formatPrice(product.price)}</p>}

          <p className="mt-4 text-[16px] leading-relaxed text-ink-soft">{product.description}</p>

          <div className="mt-7">
            <p className="text-[14px] font-semibold">
              Color <span className="font-normal text-ink-soft">· {product.colorName}</span>
            </p>
            <span
              className="mt-2.5 block h-8 w-8 rounded-full ring-2 ring-accent ring-offset-2 ring-offset-surface"
              style={{ background: product.swatch, boxShadow: "inset 0 0 0 1px rgba(0,0,0,0.12)" }}
              aria-hidden="true"
            />
          </div>

          <fieldset className="mt-7" disabled={product.status !== "available"}>
            <legend className="text-[14px] font-semibold">Size</legend>
            <div className="mt-2.5 grid grid-cols-5 gap-2">
              {product.sizes.map((s) => (
                <button
                  key={s}
                  type="button"
                  onClick={() => setSize(s)}
                  aria-pressed={size === s}
                  className={`h-12 rounded-xl border text-[15px] transition-[border-color,box-shadow] duration-200 disabled:cursor-not-allowed disabled:opacity-35 ${
                    size === s ? "border-accent shadow-[inset_0_0_0_1px_var(--accent)]" : "border-line hover:border-ink-soft"
                  }`}
                >
                  {s}
                </button>
              ))}
            </div>
          </fieldset>

          <div className="mt-7">
            {url ? (
              <a
                href={url}
                className="flex h-[52px] w-full items-center justify-center rounded-full bg-accent text-[17px] font-medium text-white transition-[transform,opacity] duration-200 hover:opacity-90 active:scale-[0.98]"
              >
                Buy · {formatPrice(product.price)}
              </a>
            ) : (
              <button
                type="button"
                disabled
                className="flex h-[52px] w-full cursor-not-allowed items-center justify-center rounded-full bg-bg-2 text-[17px] font-medium text-ink-soft"
              >
                {buyable ? "Select a size" : statusLabel(product)}
              </button>
            )}
            {!buyable && (
              <p className="mt-3 text-center text-[14px] text-ink-soft">
                Hear the moment it drops.{" "}
                <a href={APP_STORE_URL} className="text-accent hover:underline">
                  Get the app ›
                </a>
              </p>
            )}
          </div>

          <ul className="mt-8 space-y-2.5 border-t border-line pt-6">
            {product.details.map((d) => (
              <li key={d} className="flex gap-3 text-[15px] text-ink-soft">
                <svg viewBox="0 0 24 24" className="mt-[3px] h-4 w-4 shrink-0 text-accent" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                  <path d="M5 12.5l4.5 4.5L19 7.5" />
                </svg>
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
  const [h, setH] = useState(360);
  useEffect(() => {
    const fit = () => {
      const w = window.innerWidth;
      const maxW = w < 768 ? w - 64 : Math.min(w * 0.4, 500);
      const byW = maxW / (garmentWidth(product, 100) / 100);
      setH(Math.round(Math.min(byW, window.innerHeight * (w < 768 ? 0.36 : 0.5), 440)));
    };
    fit();
    window.addEventListener("resize", fit);
    return () => window.removeEventListener("resize", fit);
  }, [product]);
  return h;
}

function RoundButton({ label, onClick, children }: { label: string; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={label}
      className="flex h-9 w-9 items-center justify-center rounded-full bg-surface text-ink-soft shadow-[0_1px_4px_rgba(0,0,0,0.1)] transition-colors hover:text-ink"
    >
      <svg viewBox="0 0 24 24" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        {children}
      </svg>
    </button>
  );
}

// ── Footer ─────────────────────────────────────────────────────────────────

function Footer() {
  return (
    <footer className="mt-auto bg-bg-2 text-[12px] text-ink-soft">
      <div className="mx-auto max-w-[1024px] px-6 py-5">
        <p className="border-b border-line pb-4 leading-relaxed">
          Pieces are printed to order. Items marked coming soon or coming later aren&apos;t on sale yet. Questions?{" "}
          <a href={`mailto:${SUPPORT_EMAIL}?subject=${encodeURIComponent("Mile A Day Shop")}`} className="text-accent hover:underline">
            Contact us
          </a>
          .
        </p>
        <div className="flex flex-col gap-2 pt-4 sm:flex-row sm:items-center sm:justify-between">
          <p>Copyright © {new Date().getFullYear()} Mile A Day. All rights reserved.</p>
          <nav className="flex flex-wrap gap-x-4 gap-y-1 [&_a]:transition-colors [&_a:hover]:text-ink">
            <a href={SITE_URL}>mileaday.run</a>
            <a href={`${SITE_URL}/privacy`}>Privacy</a>
            <a href={`${SITE_URL}/terms`}>Terms</a>
            <a href="https://instagram.com/mileadayapp">Instagram</a>
            <a href="https://tiktok.com/@mileadayapp">TikTok</a>
          </nav>
        </div>
      </div>
    </footer>
  );
}
