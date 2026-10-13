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
    <section ref={ref} className="section-lazy relative px-6 py-20">
      <div className="mx-auto grid max-w-6xl items-center gap-10 md:grid-cols-[1fr_1.2fr]">
        <div>
          <span className="reveal mb-3 inline-block text-sm font-semibold uppercase tracking-widest text-[#c72554]">
            New · Mile A Day Desk
          </span>
          <h2 className="reveal font-heading text-[clamp(40px,6vw,72px)] leading-[0.95] text-[#f5f5f5]">
            YOUR STREAK,<br />ON YOUR <span className="text-[#c72554]">DESK</span>
          </h2>
          <p className="reveal mt-4 max-w-md text-[#a0a0a0]">
            A little LED box running on live Mile A Day data. This one is real and running right now. Tap it.
          </p>
          <a href="/desk"
             className="reveal mt-6 inline-flex items-center gap-2 rounded-2xl bg-[#c72554] px-6 py-3.5 font-bold text-white transition-transform hover:-translate-y-0.5">
            See it live and get one →
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
