"use client";

import { useEffect, useRef } from "react";
import { PRODUCTS } from "@/lib/catalog";
import { SIDE_TURN } from "@/components/garment";
import { loadEngine } from "@/components/three/react";

const ANGLES = [0, -35, SIDE_TURN, 180];
// ?p=0,3 limits the lab to those pieces (drawn larger); ?a=0,-90 sets angles.
function params() {
  const q = new URLSearchParams(window.location.search);
  const ids = q.get("p")?.split(",").map(Number) ?? PRODUCTS.map((_, i) => i);
  const angles = q.get("a")?.split(",").map(Number) ?? ANGLES;
  const W = window.innerWidth;
  const size = Math.min(320, (W / ids.length) * 0.75);
  const ROW = size * 1.45;
  return { products: ids.map((i) => PRODUCTS[i]), angles, W, size, ROW, H: ROW * angles.length + 40 };
}

export function Lab() {
  const canvas = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    let disposed = false;
    void loadEngine().then(async (engine) => {
      if (!engine || !canvas.current || disposed) return;
      const { products, angles, W, size, ROW, H } = params();
      canvas.current.style.width = `${W}px`;
      canvas.current.style.height = `${H}px`;
      const s = new engine.Stage(canvas.current, { railR: 3 });
      s.resize(W, H);
      s.setRail(0, 1, -9999);
      const pieces = angles.flatMap((turn, r) =>
        products.map((p, i) => {
          const piece = s.add(p, size, { x: (W / products.length) * (i + 0.5), turn });
          piece.yOffset = s.wy(30 + r * ROW) - s.railY;
          return piece;
        }),
      );
      await Promise.all(pieces.map((p) => p.loaded));
      for (const p of pieces) for (let i = 0; i < 90; i++) p.step(1 / 30, 1e9);
      s.renderNow();
      const name = new URLSearchParams(window.location.search).get("snap");
      if (name) {
        const data = canvas.current.toDataURL("image/png");
        await fetch("/lab/snap", { method: "POST", body: JSON.stringify({ name, data }) });
      }
      (window as unknown as { __labReady?: boolean }).__labReady = true;
    });
    return () => {
      disposed = true;
    };
  }, []);
  return (
    <main style={{ background: "#f5f5f7", minHeight: "100vh" }}>
      <canvas ref={canvas} style={{ display: "block" }} />
    </main>
  );
}
