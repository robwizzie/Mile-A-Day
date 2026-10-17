"use client";

import { useEffect, useState } from "react";

type Engine = typeof import("./engine");

let engine: Promise<Engine | null> | null = null;

/** three.js and the garment engine, loaded once on demand. null = no WebGL
 *  (the CSS garments stand in). */
export function loadEngine() {
  if (!engine) {
    engine = import("./engine")
      .then((m) => (m.webglAvailable() ? m : null))
      .catch(() => null);
  }
  return engine;
}

/** undefined while loading, null when 3D isn't available. */
export function useEngine() {
  const [m, setM] = useState<Engine | null | undefined>(undefined);
  useEffect(() => {
    let live = true;
    void loadEngine().then((e) => live && setM(e));
    return () => {
      live = false;
    };
  }, []);
  return m;
}

function isDark() {
  const t = document.documentElement.dataset.theme;
  if (t === "dark") return true;
  if (t === "light") return false;
  return window.matchMedia("(prefers-color-scheme: dark)").matches;
}

/** The theme actually showing (system or the visitor's pick). */
export function useDarkTheme() {
  const [dark, setDark] = useState(false);
  useEffect(() => {
    const update = () => setDark(isDark());
    update();
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    mq.addEventListener("change", update);
    const mo = new MutationObserver(update);
    mo.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });
    return () => {
      mq.removeEventListener("change", update);
      mo.disconnect();
    };
  }, []);
  return dark;
}
