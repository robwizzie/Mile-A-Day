import { readFileSync } from "node:fs";
import { join } from "node:path";
import { unstable_cache } from "next/cache";
import { hashString } from "./kit";
import { renderVideo, type Scene } from "./render";

// Serving an og.mp4: render once, keep the bytes, answer byte ranges.
//
// - The bytes live in Next's data cache (shared by every instance, kept
//   across requests) and a small in-memory map, keyed by WHAT IS DRAWN —
//   the caller passes the facts the scene shows, so a new streak or avatar
//   is a new video at once, and every unknown username shares one.
// - Range requests are answered here, from those bytes. iOS (AVFoundation,
//   which renders iMessage's link previews) only plays video from a server
//   that honours Range; whether the CDN would split a cached 200 into 206s
//   is not something to bet a preview on, so the CDN doesn't cache these
//   (the data cache is the cache) and every range reaches this code.
// - A render that fails answers 503 uncached: the platform falls back to
//   the og:image card, and the next request tries again.

/**
 * Changes with every deploy, so new scene code never serves old videos: the
 * Vercel deployment, else this build's id (`next start`), else the dev
 * server's start (the data cache outlives both locally).
 */
const BUILD =
  process.env.VERCEL_DEPLOYMENT_ID ?? process.env.VERCEL_GIT_COMMIT_SHA ?? localBuild();

function localBuild(): string {
  if (process.env.NODE_ENV === "development") return `dev-${Date.now()}`;
  try {
    return readFileSync(join(process.cwd(), ".next/BUILD_ID"), "utf8").trim();
  } catch {
    return `start-${Date.now()}`;
  }
}

const MEMORY_MAX = 24;
const memory = new Map<string, { until: number; bytes: Uint8Array }>();
const inflight = new Map<string, Promise<Uint8Array>>();

async function videoBytes(
  key: string,
  ttl: number,
  scene: () => Promise<Scene>,
): Promise<Uint8Array> {
  const hit = memory.get(key);
  if (hit && hit.until > Date.now()) return hit.bytes;
  // One render per key per instance, however many requests arrive for it.
  let job = inflight.get(key);
  if (!job) {
    job = (async () => {
      const b64 = await unstable_cache(
        async () =>
          Buffer.from(await renderVideo(await scene())).toString("base64"),
        ["og-video", BUILD, key],
        { revalidate: ttl },
      )();
      const bytes = new Uint8Array(Buffer.from(b64, "base64"));
      if (memory.size >= MEMORY_MAX) memory.delete(memory.keys().next().value!);
      memory.set(key, { until: Date.now() + Math.min(ttl, 600) * 1000, bytes });
      return bytes;
    })().finally(() => inflight.delete(key));
    inflight.set(key, job);
  }
  return job;
}

/** A stable short key for the facts a scene draws. */
export function factsKey(kind: string, facts: unknown): string {
  return `${kind}/${hashString(JSON.stringify(facts)).toString(36)}`;
}

/**
 * The response for one og.mp4 request (GET or HEAD). `ttl` (seconds) is how
 * long a render stands before it's redrawn in the background.
 */
export async function ogVideoResponse(
  req: Request,
  {
    key,
    ttl,
    scene,
  }: { key: string; ttl: number; scene: () => Promise<Scene> },
): Promise<Response> {
  let bytes: Uint8Array;
  try {
    bytes = await videoBytes(key, ttl, scene);
  } catch (err) {
    console.error(`og.mp4 ${key}:`, err);
    return new Response("video unavailable", {
      status: 503,
      headers: { "Cache-Control": "no-store", "Retry-After": "60" },
    });
  }

  const total = bytes.length;
  const headers: Record<string, string> = {
    "Content-Type": "video/mp4",
    "Accept-Ranges": "bytes",
    "Cache-Control": `public, max-age=${Math.min(ttl, 3600)}`,
    // The CDN would cache whole-file 200s and replay them for range
    // requests; keep it out (see above).
    "CDN-Cache-Control": "no-store",
    ETag: `"${key.replace(/[^\w/-]/g, "")}-${total}"`,
  };
  const head = req.method === "HEAD";

  const range = req.headers.get("range");
  const match = range?.match(/^bytes=(\d*)-(\d*)$/);
  if (range && match && (match[1] || match[2])) {
    let start: number;
    let end: number;
    if (match[1]) {
      start = Number(match[1]);
      end = match[2] ? Math.min(Number(match[2]), total - 1) : total - 1;
    } else {
      // "bytes=-N": the last N bytes.
      start = Math.max(0, total - Number(match[2]));
      end = total - 1;
    }
    if (start >= total || start > end) {
      return new Response(null, {
        status: 416,
        headers: { ...headers, "Content-Range": `bytes */${total}` },
      });
    }
    const body = bytes.subarray(start, end + 1);
    return new Response(head ? null : body, {
      status: 206,
      headers: {
        ...headers,
        "Content-Range": `bytes ${start}-${end}/${total}`,
        "Content-Length": String(body.length),
      },
    });
  }
  return new Response(head ? null : bytes, {
    headers: { ...headers, "Content-Length": String(total) },
  });
}
