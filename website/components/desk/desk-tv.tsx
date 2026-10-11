"use client";

import { useEffect, useState } from "react";
import { DeskBox } from "./desk-box";
import { useDeskFeed } from "@/lib/use-desk-feed";
import { MASCOT, STYLE } from "@/lib/desk-engine";

const NAMES: Record<string, number> = {
  showcase: STYLE.SHOWCASE, arcade: STYLE.ARCADE, odometer: STYLE.ODOMETER, classic: STYLE.CLASSIC,
  big: STYLE.BIG, campfire: STYLE.CAMPFIRE, spotlight: STYLE.SPOTLIGHT,
};

/**
 * TV mode (/desk/tv): the LEDs alone, as big as the screen allows, for a
 * booth or a counter. ?style=arcade|odometer|... (default showcase: every
 * style in turn) and ?mascot=runner|flamey. Click for full screen.
 */
export function DeskTv() {
  const feed = useDeskFeed();
  const [style, setStyle] = useState<number>(STYLE.SHOWCASE);
  const [mascot, setMascot] = useState<number>(MASCOT.FLAMEY);
  const [idle, setIdle] = useState(false);

  useEffect(() => {
    const q = new URLSearchParams(window.location.search);
    const s = NAMES[(q.get("style") || "").toLowerCase()];
    if (s !== undefined) setStyle(s);
    if ((q.get("mascot") || "").toLowerCase() === "runner") setMascot(MASCOT.RUNNER);
  }, []);

  useEffect(() => {                       // hide the cursor and hint when nobody's touching it
    let t: ReturnType<typeof setTimeout>;
    const wake = () => {
      setIdle(false);
      clearTimeout(t);
      t = setTimeout(() => setIdle(true), 3000);
    };
    wake();
    window.addEventListener("pointermove", wake);
    return () => { clearTimeout(t); window.removeEventListener("pointermove", wake); };
  }, []);

  const fullscreen = () => {
    if (!document.fullscreenElement) document.documentElement.requestFullscreen?.().catch(() => {});
  };

  return (
    <main onClick={fullscreen}
          className="flex min-h-screen flex-col items-center justify-center overflow-hidden bg-black"
          style={{ cursor: idle ? "none" : "pointer" }}>
      <div style={{ width: "min(94vw, 168vh)" }}>
        <DeskBox feed={feed} style={style} mascot={mascot} bare interactive={false} maxDpr={1.5} />
      </div>
      <div className="mt-[2vh] flex items-center gap-3 text-[clamp(12px,1.6vw,22px)] font-semibold tracking-wide text-white/45">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/images/mad-circle-icon.png" alt="" className="h-[1.6em] w-[1.6em] rounded-full" />
        Walk or run a mile a day · mileaday.run
      </div>
      <p className="fixed bottom-3 text-xs text-white/30 transition-opacity" style={{ opacity: idle ? 0 : 1 }}>
        Click for full screen
      </p>
    </main>
  );
}
