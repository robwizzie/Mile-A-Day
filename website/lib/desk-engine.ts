/**
 * The desk counter's own code, running in the browser: MicroPython
 * WebAssembly + the box's mad/* package (public/desk/py), drawing into a
 * 64x32 frame handed back as RGB bytes. Used by the phone remote's preview,
 * the website's live twin (/desk), the TV page and GIF sharing — so every
 * one of them shows exactly what a real box shows.
 */

export type DeskEngine = {
  start(feed: string, style: number, mascot: number): void;
  feed(feed: string, now: number): void;
  choose(style: number, mascot: number, now: number): void;
  sleep(awake: number, start: number, end: number, now: number): void;
  test(scene: string, now: number): void;
  doodle(code: string, now: number): void;
  set_date(d: string): void;
  poke(now: number): void;
  dizzy(now: number): void;
  frame(now: number): Uint8Array;
};

/** Style numbers (the box's STYLES). */
export const STYLE = {
  CLASSIC: 0, SPOTLIGHT: 1, ARCADE: 2, BIG: 3, CAMPFIRE: 4, RACE: 5, CLOCK: 6,
  VERSUS: 7, GROWTH: 8, ODOMETER: 9, SHOWCASE: 10,
} as const;
export const MASCOT = { RUNNER: 0, FLAMEY: 1 } as const;

const MODULES = ["__init__", "gfx", "art", "app", "cards", "heat", "fx", "modes", "extra", "decor",
                 "season", "closet", "testscenes", "boards"];

let enginePromise: Promise<DeskEngine> | null = null;

/** Load MicroPython + the desk's code once per page. */
export function loadDeskEngine(): Promise<DeskEngine> {
  if (enginePromise) return enginePromise;
  enginePromise = (async () => {
    // Plain dynamic import of a static file (kept out of the bundle).
    const importer = new Function("u", "return import(u)") as (u: string) => Promise<any>;
    const { loadMicroPython } = await importer("/desk/mp/micropython.mjs");
    const mp = await loadMicroPython({ heapsize: 6 * 1024 * 1024 });
    const files = ["displayio.py", "bitmaptools.py", "deskpreview.py", ...MODULES.map((m) => `mad/${m}.py`)];
    mp.FS.mkdir("/mad");
    await Promise.all(files.map(async (f) => {
      const res = await fetch(`/desk/py/${f}`);
      if (!res.ok) throw new Error(`desk file ${f}: ${res.status}`);
      mp.FS.writeFile(`/${f}`, new Uint8Array(await res.arrayBuffer()));
    }));
    mp.runPython("import sys\nif '/' not in sys.path: sys.path.append('/')");
    return mp.pyimport("deskpreview") as DeskEngine;
  })();
  enginePromise.catch(() => { enginePromise = null; });
  return enginePromise;
}

/** The panel is dim on purpose (one USB supply); brighten it for a screen
 *  the way the LEDs read in a room. */
export const LED_GAIN = 1.8;

/** Today's date on the viewer's clock, for the seasonal looks. */
export function localDate(): string {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

/** Copy one frame into a 64x32 ImageData (brightened). */
export function frameToImage(rgb: Uint8Array, img: ImageData) {
  const d = img.data;
  for (let i = 0, j = 0; i < 2048; i++, j += 3) {
    d[i * 4] = Math.min(255, rgb[j] * LED_GAIN);
    d[i * 4 + 1] = Math.min(255, rgb[j + 1] * LED_GAIN);
    d[i * 4 + 2] = Math.min(255, rgb[j + 2] * LED_GAIN);
    d[i * 4 + 3] = 255;
  }
}

/**
 * Draw the frame as an LED matrix: round dots on a black board, unlit LEDs
 * faintly visible, a soft glow around lit ones. `w` x `h` is the area at
 * (x, y) on `ctx`, 2:1.
 */
export function drawLeds(ctx: CanvasRenderingContext2D, rgb: Uint8Array, x: number, y: number, w: number, h: number,
                         glow = true) {
  const p = w / 64;
  const r = p * 0.36;
  ctx.fillStyle = "#050505";
  ctx.fillRect(x, y, w, h);
  ctx.fillStyle = "#1d1d1d";                       // the dark LEDs (visible, like the real panel)
  ctx.beginPath();
  for (let yy = 0; yy < 32; yy++) {
    for (let xx = 0; xx < 64; xx++) {
      const i = (yy * 64 + xx) * 3;
      if (rgb[i] | rgb[i + 1] | rgb[i + 2]) continue;
      const cx = x + (xx + 0.5) * p, cy = y + (yy + 0.5) * p;
      ctx.moveTo(cx + r, cy);
      ctx.arc(cx, cy, r, 0, Math.PI * 2);
    }
  }
  ctx.fill();
  if (glow) {
    ctx.save();
    ctx.globalCompositeOperation = "lighter";
    for (let yy = 0; yy < 32; yy++) {
      for (let xx = 0; xx < 64; xx++) {
        const i = (yy * 64 + xx) * 3;
        if (!(rgb[i] | rgb[i + 1] | rgb[i + 2])) continue;
        const R = Math.min(255, rgb[i] * LED_GAIN), G = Math.min(255, rgb[i + 1] * LED_GAIN),
              B = Math.min(255, rgb[i + 2] * LED_GAIN);
        ctx.fillStyle = `rgba(${R},${G},${B},0.16)`;
        ctx.fillRect(x + (xx - 0.35) * p, y + (yy - 0.35) * p, p * 1.7, p * 1.7);
      }
    }
    ctx.restore();
  }
  for (let yy = 0; yy < 32; yy++) {
    for (let xx = 0; xx < 64; xx++) {
      const i = (yy * 64 + xx) * 3;
      if (!(rgb[i] | rgb[i + 1] | rgb[i + 2])) continue;
      const R = Math.min(255, rgb[i] * LED_GAIN), G = Math.min(255, rgb[i + 1] * LED_GAIN),
            B = Math.min(255, rgb[i + 2] * LED_GAIN);
      ctx.fillStyle = `rgb(${R},${G},${B})`;
      ctx.beginPath();
      ctx.arc(x + (xx + 0.5) * p, y + (yy + 0.5) * p, r, 0, Math.PI * 2);
      ctx.fill();
    }
  }
}
