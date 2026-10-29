import { readFile } from "node:fs/promises";
import { join } from "node:path";
import {
  GlobalFonts,
  createCanvas,
  loadImage,
  type Image,
  type SKRSContext2D,
} from "@napi-rs/canvas";
import type { H264MP4Encoder } from "h264-mp4-encoder";
import { remoteImageBytes } from "../shared";
import { VIDEO } from "./config";
import { finishMp4 } from "./mp4";

// The link-preview VIDEOS (og:video): each page's `og.mp4` route draws its
// scene frame by frame on a Skia canvas and encodes it to H.264 MP4 with a
// WebAssembly encoder — no ffmpeg binary, so it runs in a Vercel function.
// The PNG card from the page's opengraph-image stays as og:image: the poster,
// and the whole preview wherever a platform doesn't play og:video.

export { VIDEO };

export type Ctx = SKRSContext2D;
/** Draws one frame at `t` seconds into a fresh (save/restore'd) context. */
export type Scene = (g: Ctx, t: number) => void;

const OG_DIR = join(process.cwd(), "app/_og");

let fontsRegistered = false;

/** The same vendored type the PNG cards use (Skia reads woff directly). */
function registerFonts() {
  if (fontsRegistered) return;
  GlobalFonts.registerFromPath(
    join(OG_DIR, "fonts/BebasNeue-400.woff"),
    "Bebas Neue",
  );
  GlobalFonts.registerFromPath(
    join(OG_DIR, "fonts/DMSans-500.woff"),
    "DM Sans",
  );
  GlobalFonts.registerFromPath(
    join(OG_DIR, "fonts/DMSans-700.woff"),
    "DM Sans",
  );
  fontsRegistered = true;
}

/** A file from app/_og (the app icon, the dashboard shot) as a canvas image. */
export async function ogAsset(name: string): Promise<Image> {
  return loadImage(await readFile(join(OG_DIR, name)));
}

/** A remote picture (avatar, banner), or null: a bad image never fails the video. */
export async function remoteImage(url: string | null): Promise<Image | null> {
  const got = await remoteImageBytes(url);
  if (!got) return null;
  try {
    return await loadImage(got.bytes);
  } catch {
    return null;
  }
}

/**
 * A new encoder, with the Emscripten module's process-wide hooks taken back
 * off: its build installs `uncaughtException` / `unhandledRejection` handlers
 * that rethrow, which would turn ANY stray rejection elsewhere in the server
 * into a crashed process.
 */
async function createEncoder(): Promise<H264MP4Encoder> {
  // Listeners typed loosely: process.listeners() is overloaded per event.
  type Hook = (...args: unknown[]) => void;
  const proc = process as unknown as {
    listeners(e: string): Hook[];
    removeListener(e: string, l: Hook): void;
  };
  const events = ["uncaughtException", "unhandledRejection"];
  const before = events.map((e) => new Set(proc.listeners(e)));
  try {
    const mod = (await import("h264-mp4-encoder")) as unknown as {
      createH264MP4Encoder?: () => Promise<H264MP4Encoder>;
      default?: { createH264MP4Encoder: () => Promise<H264MP4Encoder> };
    };
    // CommonJS: the functions sit on the default export or the namespace,
    // depending on who did the interop.
    const create = mod.createH264MP4Encoder ?? mod.default!.createH264MP4Encoder;
    return await create();
  } finally {
    events.forEach((e, i) => {
      for (const l of proc.listeners(e)) {
        if (!before[i].has(l)) proc.removeListener(e, l);
      }
    });
  }
}

let renders = 0;

/** Render a scene to an MP4 (H.264 baseline, yuv420p, indexed, moov first). */
export async function renderVideo(scene: Scene): Promise<Uint8Array> {
  registerFonts();
  const { width, height, fps, seconds } = VIDEO;
  const canvas = createCanvas(width, height);
  const g = canvas.getContext("2d");
  const encoder = await createEncoder();
  // The encoders share one in-memory file system: concurrent renders on
  // one instance each need their own file.
  encoder.outputFilename = `og-${process.pid}-${renders++}.mp4`;
  encoder.width = width;
  encoder.height = height;
  encoder.frameRate = fps;
  // Motion graphics on a dark ground: 24 keeps the red glows from banding
  // and lands a 6 s clip around a megabyte (link previews download it whole).
  encoder.quantizationParameter = 24;
  encoder.speed = 10;
  encoder.groupOfPictures = fps * 3;
  encoder.initialize();
  try {
    const frames = fps * seconds;
    for (let i = 0; i < frames; i++) {
      g.save();
      scene(g, i / fps);
      g.restore();
      encoder.addFrameRgba(g.getImageData(0, 0, width, height).data);
      // A render is a few seconds of CPU: let other requests on this
      // instance breathe between frames.
      if (i % 15 === 14) await new Promise((r) => setImmediate(r));
    }
    encoder.finalize();
    const bytes = encoder.FS.readFile(encoder.outputFilename);
    encoder.FS.unlink(encoder.outputFilename);
    return finishMp4(bytes);
  } finally {
    encoder.delete();
  }
}
