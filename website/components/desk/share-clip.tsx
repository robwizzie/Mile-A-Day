"use client";

import { useEffect, useRef, useState } from "react";
import { drawLeds } from "@/lib/desk-engine";

type Format = "gif" | "video";
type Shape = "wide" | "vertical";

const SECONDS = [4, 6, 10];
const GIF_FPS = 12;
const VIDEO_FPS = 24;

/** Size of the clip and where the LED panel sits in it. */
function layout(shape: Shape, format: Format) {
  if (shape === "vertical") {
    const w = format === "gif" ? 480 : 720, h = Math.round(w * 16 / 9);
    const pw = Math.round(w * 0.92);
    return { w, h, px: Math.round((w - pw) / 2), py: Math.round(h * 0.36), pw };
  }
  const w = format === "gif" ? 640 : 1280;
  const pw = Math.round(w * 0.95);
  const ph = pw / 2;
  const foot = Math.round(w * 0.07);
  return { w, h: Math.round(ph + (w - pw) + foot), px: Math.round((w - pw) / 2), py: Math.round((w - pw) / 2), pw };
}

/** One frame of the clip: the panel on dark, the Mile A Day name. */
function paint(ctx: CanvasRenderingContext2D, rgb: Uint8Array, shape: Shape, format: Format) {
  const L = layout(shape, format);
  const g = ctx.createLinearGradient(0, 0, 0, L.h);
  g.addColorStop(0, "#151517");
  g.addColorStop(1, "#08080a");
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, L.w, L.h);
  drawLeds(ctx, rgb, L.px, L.py, L.pw, L.pw / 2, format === "video");
  ctx.fillStyle = "rgba(255,255,255,0.55)";
  ctx.textBaseline = "middle";
  if (shape === "vertical") {
    ctx.textAlign = "center";
    ctx.font = `800 ${Math.round(L.w * 0.075)}px system-ui, sans-serif`;
    ctx.fillStyle = "#f5f5f5";
    ctx.fillText("MILE A DAY", L.w / 2, L.h * 0.2);
    ctx.font = `600 ${Math.round(L.w * 0.04)}px system-ui, sans-serif`;
    ctx.fillStyle = "#c72554";
    ctx.fillText("on my desk", L.w / 2, L.h * 0.255);
    ctx.fillStyle = "rgba(255,255,255,0.5)";
    ctx.fillText("mileaday.run", L.w / 2, L.h * 0.86);
  } else {
    const y = L.py + L.pw / 2 + (L.h - (L.py + L.pw / 2)) / 2;
    ctx.font = `800 ${Math.round(L.w * 0.028)}px system-ui, sans-serif`;
    ctx.textAlign = "left";
    ctx.fillText("MILE A DAY", L.px, y);
    ctx.textAlign = "right";
    ctx.font = `600 ${Math.round(L.w * 0.024)}px system-ui, sans-serif`;
    ctx.fillText("mileaday.run", L.px + L.pw, y);
  }
}

function videoType(): string | null {
  if (typeof MediaRecorder === "undefined") return null;
  for (const t of ["video/mp4;codecs=avc1", "video/mp4", "video/webm;codecs=vp9", "video/webm"]) {
    if (MediaRecorder.isTypeSupported(t)) return t;
  }
  return null;
}

/**
 * Share as GIF / video: records what the preview above is showing (the box's
 * real screen) for a few seconds, then hands it to the phone's share sheet
 * (or downloads it). Nothing leaves the phone unless you share it.
 */
export function ShareClip({ frameRef, busyLabel }: { frameRef: React.MutableRefObject<Uint8Array | null>; busyLabel?: string }) {
  const [format, setFormat] = useState<Format>("gif");
  const [shape, setShape] = useState<Shape>("vertical");
  const [secs, setSecs] = useState(6);
  const [phase, setPhase] = useState<"idle" | "recording" | "encoding" | "done">("idle");
  const [progress, setProgress] = useState(0);
  const [out, setOut] = useState<{ url: string; blob: Blob; name: string; kind: Format } | null>(null);
  const [error, setError] = useState("");
  const canVideo = useRef<string | null>(null);

  useEffect(() => { canVideo.current = videoType(); }, []);
  useEffect(() => () => { if (out) URL.revokeObjectURL(out.url); }, [out]);

  async function record() {
    setError("");
    if (out) URL.revokeObjectURL(out.url);
    setOut(null);
    if (!frameRef.current) { setError("The preview isn't running yet"); return; }
    const L = layout(shape, format);
    const c = document.createElement("canvas");
    c.width = L.w;
    c.height = L.h;
    const ctx = c.getContext("2d")!;
    setPhase("recording");
    setProgress(0);
    try {
      if (format === "video") {
        const type = canVideo.current;
        if (!type) throw new Error("This browser can't record video here. Try GIF.");
        const stream = (c as HTMLCanvasElement & { captureStream(fps?: number): MediaStream }).captureStream(VIDEO_FPS);
        const rec = new MediaRecorder(stream, { mimeType: type, videoBitsPerSecond: 6_000_000 });
        const parts: Blob[] = [];
        rec.ondataavailable = (e) => e.data.size && parts.push(e.data);
        const done = new Promise<void>((r) => { rec.onstop = () => r(); });
        paint(ctx, frameRef.current!, shape, format);
        rec.start(250);
        const t0 = performance.now();
        await new Promise<void>((resolve) => {
          const tick = () => {
            const el = (performance.now() - t0) / 1000;
            if (frameRef.current) paint(ctx, frameRef.current, shape, format);
            setProgress(Math.min(1, el / secs));
            if (el >= secs) return resolve();
            setTimeout(tick, 1000 / VIDEO_FPS);
          };
          tick();
        });
        rec.stop();
        await done;
        const blob = new Blob(parts, { type: type.split(";")[0] });
        const ext = type.includes("mp4") ? "mp4" : "webm";
        setOut({ url: URL.createObjectURL(blob), blob, name: `mile-a-day-desk.${ext}`, kind: "video" });
      } else {
        const frames: Uint8Array[] = [];
        const n = secs * GIF_FPS;
        await new Promise<void>((resolve) => {
          const id = setInterval(() => {
            if (frameRef.current) frames.push(frameRef.current.slice());
            setProgress(frames.length / n);
            if (frames.length >= n) { clearInterval(id); resolve(); }
          }, 1000 / GIF_FPS);
        });
        setPhase("encoding");
        const { GIFEncoder, quantize, applyPalette } = await import("gifenc");
        const gif = GIFEncoder();
        for (let i = 0; i < frames.length; i++) {
          paint(ctx, frames[i], shape, format);
          const { data } = ctx.getImageData(0, 0, L.w, L.h);
          const palette = quantize(data, 128);
          gif.writeFrame(applyPalette(data, palette), L.w, L.h, { palette, delay: Math.round(1000 / GIF_FPS), repeat: 0 });
          setProgress((i + 1) / frames.length);
          if (i % 4 === 3) await new Promise((r) => setTimeout(r, 0));     // keep the page responsive
        }
        gif.finish();
        const blob = new Blob([gif.bytes()], { type: "image/gif" });
        setOut({ url: URL.createObjectURL(blob), blob, name: "mile-a-day-desk.gif", kind: "gif" });
      }
      setPhase("done");
    } catch (e) {
      setError((e as Error).message);
      setPhase("idle");
    }
  }

  async function share() {
    if (!out) return;
    const file = new File([out.blob], out.name, { type: out.blob.type });
    const nav = navigator as Navigator & { canShare?(d: ShareData): boolean };
    if (nav.canShare?.({ files: [file] })) {
      try {
        await nav.share({ files: [file], title: "Mile A Day" });
        return;
      } catch {
        /* cancelled: fall through to nothing */
        return;
      }
    }
    const a = document.createElement("a");
    a.href = out.url;
    a.download = out.name;
    a.click();
  }

  const working = phase === "recording" || phase === "encoding";
  const chip = (on: boolean) => ({ background: on ? "rgba(217,64,89,0.25)" : "rgba(255,255,255,0.05)",
                                   boxShadow: on ? "inset 0 0 0 1.5px #d94059" : undefined });

  return (
    <div className="flex flex-col gap-2">
      <div className="grid grid-cols-2 gap-2">
        <div className="grid grid-cols-2 gap-1 rounded-xl bg-white/[0.04] p-1">
          {(["gif", "video"] as Format[]).map((f) => (
            <button key={f} disabled={working} onClick={() => setFormat(f)} className="rounded-lg py-1.5 text-xs font-bold" style={chip(format === f)}>
              {f === "gif" ? "GIF" : "Video"}
            </button>
          ))}
        </div>
        <div className="grid grid-cols-2 gap-1 rounded-xl bg-white/[0.04] p-1">
          {(["vertical", "wide"] as Shape[]).map((s) => (
            <button key={s} disabled={working} onClick={() => setShape(s)} className="rounded-lg py-1.5 text-xs font-bold" style={chip(shape === s)}>
              {s === "vertical" ? "9:16" : "Wide"}
            </button>
          ))}
        </div>
      </div>
      <div className="flex items-center gap-2">
        {SECONDS.map((s) => (
          <button key={s} disabled={working} onClick={() => setSecs(s)} className="rounded-lg px-3 py-1.5 text-xs font-bold" style={chip(secs === s)}>
            {s}s
          </button>
        ))}
        <button disabled={working} onClick={record}
                className="ml-auto rounded-xl px-4 py-2 text-sm font-extrabold disabled:opacity-60" style={{ background: "#d94059" }}>
          {phase === "recording" ? `● Recording ${Math.round(progress * secs)}s`
            : phase === "encoding" ? `Making GIF ${Math.round(progress * 100)}%` : "● Record"}
        </button>
      </div>
      {working && (
        <div className="h-1 overflow-hidden rounded-full bg-white/10">
          <div className="h-full bg-[#d94059] transition-[width]" style={{ width: `${progress * 100}%` }} />
        </div>
      )}
      {error && <p className="text-xs text-[#ff6b8b]">{error}</p>}
      {out && (
        <div className="flex flex-col items-center gap-2 rounded-xl bg-white/[0.04] p-2">
          {out.kind === "gif"
            // eslint-disable-next-line @next/next/no-img-element
            ? <img src={out.url} alt="Your clip" className="max-h-72 rounded-lg" />
            : <video src={out.url} className="max-h-72 rounded-lg" autoPlay loop muted playsInline />}
          <button onClick={share} className="w-full rounded-xl py-2.5 text-sm font-extrabold" style={{ background: "#d94059" }}>
            Share or save
          </button>
          <p className="text-[11px] text-white/40">{(out.blob.size / 1024 / 1024).toFixed(1)} MB · {out.name}</p>
        </div>
      )}
      <p className="text-[11px] text-white/40">
        {busyLabel ?? "Records what the preview shows, like a test animation or a doodle. Only you decide where it goes."}
      </p>
    </div>
  );
}
