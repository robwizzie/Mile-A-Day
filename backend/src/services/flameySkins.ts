/**
 * Flamey skins — every wardrobe item as a JSON file in `backend/flamey-skins/`
 * (format: docs/flamey-skins.md). Loaded ONCE at module load (server boot);
 * a new skin is a new file + a deploy.
 *
 * Validation here is deliberately light: a bad file is logged and skipped,
 * never fatal (production must boot). The strict gate is
 * `scripts/flamey-skins-check.mjs`, which runs in CI.
 *
 * Skins whose id is not in flameyCatalog.ts ROWS become catalog items (see
 * buildCatalog there); ROWS stays authoritative for the items it lists.
 */
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { gzipSync } from "node:zlib";
import { isFlameySlot, type FlameySlot, type FlameyUnlock } from "./flameySlots.js";

export interface FlameySkin {
  format: number;
  id: string;
  order: number;
  slot: FlameySlot;
  /** Parsed form of the file's `unlock`. */
  unlock: FlameyUnlock;
  /** Automatic mood dressing — drawn by the app, never in the Closet. */
  moodProp: boolean;
  /** The file's JSON exactly as written (what GET /flamey/skins serves). */
  raw: Record<string, unknown>;
}

const ID_RE = /^[a-z0-9_]+$/;

/**
 * The folder, for both `tsx src/server.ts` (src/services → ../../) and
 * `node dist/server.js` (dist/services → ../../), with the cwd as a fallback
 * (Docker WORKDIR /app). `FLAMEY_SKINS_DIR` overrides.
 */
function resolveSkinsDir(): string | null {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const candidates = [
    process.env.FLAMEY_SKINS_DIR,
    path.resolve(here, "../../flamey-skins"),
    path.resolve(process.cwd(), "flamey-skins"),
  ].filter((p): p is string => !!p);
  return candidates.find((p) => fs.existsSync(p) && fs.statSync(p).isDirectory()) ?? null;
}

/** File `unlock` → catalog unlock; null when malformed. */
export function parseSkinUnlock(u: unknown): FlameyUnlock | null {
  if (u === "always") return { kind: "always" };
  if (u === "plus") return { kind: "plus" };
  if (u && typeof u === "object" && !Array.isArray(u)) {
    const o = u as Record<string, unknown>;
    const keys = Object.keys(o);
    if (keys.length === 1 && typeof o.badge === "string" && ID_RE.test(o.badge)) {
      return { kind: "badge", id: o.badge };
    }
    if (
      keys.length === 1 &&
      Number.isInteger(o.month) &&
      (o.month as number) >= 1 &&
      (o.month as number) <= 12
    ) {
      return { kind: "month", month: o.month as number };
    }
  }
  return null;
}

function parseSkin(file: string, text: string): FlameySkin | string {
  let j: unknown;
  try {
    j = JSON.parse(text);
  } catch (e: any) {
    return `invalid JSON (${e?.message ?? e})`;
  }
  if (!j || typeof j !== "object" || Array.isArray(j)) return "not an object";
  const o = j as Record<string, unknown>;
  const id = path.basename(file, ".json");
  if (o.id !== id || !ID_RE.test(id)) return `id ${JSON.stringify(o.id)} != filename`;
  if (!Number.isInteger(o.format) || (o.format as number) < 1) return "format must be a positive integer";
  if (typeof o.order !== "number" || !Number.isFinite(o.order)) return "order must be a number";
  if (!isFlameySlot(o.slot)) return `unknown slot ${JSON.stringify(o.slot)}`;
  const unlock = parseSkinUnlock(o.unlock);
  if (!unlock) return `bad unlock ${JSON.stringify(o.unlock)}`;
  if (!o.art || typeof o.art !== "object" || Array.isArray(o.art)) return "art must be an object";
  return {
    format: o.format as number,
    id,
    order: o.order,
    slot: o.slot,
    unlock,
    moodProp: o.mood_prop === true,
    raw: o,
  };
}

function loadSkins(): { skins: FlameySkin[]; version: string } {
  const dir = resolveSkinsDir();
  const hash = createHash("sha256");
  if (!dir) {
    console.error("[flamey-skins] flamey-skins folder not found; serving no skins");
    return { skins: [], version: hash.digest("hex").slice(0, 16) };
  }
  const skins: FlameySkin[] = [];
  let files: string[] = [];
  try {
    files = fs.readdirSync(dir).filter((f) => f.endsWith(".json")).sort();
  } catch (e: any) {
    console.error(`[flamey-skins] cannot read ${dir}: ${e?.message ?? e}`);
  }
  for (const file of files) {
    let text: string;
    try {
      text = fs.readFileSync(path.join(dir, file), "utf8");
    } catch (e: any) {
      console.error(`[flamey-skins] skipped ${file}: unreadable (${e?.message ?? e})`);
      continue;
    }
    const parsed = parseSkin(file, text);
    if (typeof parsed === "string") {
      console.error(`[flamey-skins] skipped ${file}: ${parsed}`);
      continue;
    }
    // Only accepted files feed the version, so a skipped file doesn't churn it.
    hash.update(file).update("\0").update(text).update("\0");
    skins.push(parsed);
  }
  skins.sort((a, b) => a.order - b.order || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  console.log(`[flamey-skins] loaded ${skins.length}/${files.length} skins from ${dir}`);
  return { skins, version: hash.digest("hex").slice(0, 16) };
}

const loaded = loadSkins();

/** Every valid skin, ordered by `order` then id. */
export const FLAMEY_SKINS: ReadonlyArray<FlameySkin> = loaded.skins;

/** Stable hash of the loaded files' names + contents. */
export const FLAMEY_SKINS_VERSION: string = loaded.version;

/** Highest renderer format any loaded skin needs (1 today). */
export const FLAMEY_SKIN_FORMAT_MAX: number = Math.max(1, ...loaded.skins.map((s) => s.format));

export interface FlameySkinsPayload {
  etag: string;
  /** UTF-8 JSON body. */
  body: Buffer;
  /** gzip of `body`, built once. */
  gzipped: Buffer;
}

const payloadCache = new Map<number, FlameySkinsPayload>();

/**
 * The GET /flamey/skins response for a client renderer `format`: only skins
 * with format <= it. Built once per effective format and memoized (the files
 * never change while the process runs).
 */
export function flameySkinsPayload(format: number): FlameySkinsPayload {
  const effective = Math.max(0, Math.min(format, FLAMEY_SKIN_FORMAT_MAX));
  const cached = payloadCache.get(effective);
  if (cached) return cached;
  const body = Buffer.from(
    JSON.stringify({
      version: FLAMEY_SKINS_VERSION,
      format_max: FLAMEY_SKIN_FORMAT_MAX,
      skins: FLAMEY_SKINS.filter((s) => s.format <= effective).map((s) => s.raw),
    }),
    "utf8",
  );
  const payload: FlameySkinsPayload = {
    etag: `"${FLAMEY_SKINS_VERSION}-f${effective}"`,
    body,
    gzipped: gzipSync(body, { level: 9 }),
  };
  payloadCache.set(effective, payload);
  return payload;
}
