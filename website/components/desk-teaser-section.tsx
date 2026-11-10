"use client";

import { useEffect, useRef, useState } from "react";
import { DeskBox } from "./desk/desk-box";
import { useDeskFeed } from "@/lib/use-desk-feed";
import { MASCOT, STYLE } from "@/lib/desk-engine";

/** Homepage: a small live desk box (loaded only once it scrolls into view)
 *  and a link to mileaday.run/desk. */
export function DeskTeaserSection() {
  const ref = useRef<HTMLDivElement>(null);
  const [seen, setSeen] = useState(false);
  const feed = useDeskFeed(seen);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver(([e]) => {
      if (e.isIntersecting) {
        setSeen(true);
        io.disconnect();
      }
    }, { rootMargin: "200px" });
    io.observe(el);
    return () => io.disconnect();
  }, []);

  return (
    <section ref={ref} className="relative border-t border-white/10 bg-[#0e0809] px-6 py-20 text-white">
      <div className="mx-auto grid max-w-6xl items-center gap-10 md:grid-cols-[1fr_1.2fr]">
        <div>
          <p className="mb-4 text-[13px] font-semibold uppercase tracking-[0.18em] text-white/60">
            Mile A Day Desk
          </p>
          <h2 className="font-heading text-[clamp(40px,6vw,72px)] leading-[0.95] text-white">
            Your streak,<br />on your desk.
          </h2>
          <p className="mt-4 max-w-md text-[17px] text-white/70">
            A little LED box running on live Mile A Day data. This one is real and running right now. Tap it.
          </p>
          <a href="/desk"
             className="mt-6 inline-flex items-center gap-2 rounded-full bg-white px-6 py-3.5 text-[15px] font-semibold text-[#16090c] hover:bg-white/90">
            See it live
          </a>
        </div>
        <div>
          {seen ? (
            <DeskBox feed={feed} style={STYLE.ARCADE} mascot={MASCOT.FLAMEY} />
          ) : (
            <div style={{ aspectRatio: "2.15 / 1" }} />
          )}
        </div>
      </div>
    </section>
  );
}
