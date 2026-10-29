// Post-processing for the encoder's MP4, done on the box tree:
//
// 1. A sync-sample table (`stss`). The encoder writes none, and an MP4
//    without one says EVERY frame is a keyframe — so a player that seeks
//    (scrubbing, a thumbnail grab) lands on a P-frame it can't decode.
//    Keyframes are found by looking for IDR NAL units in each sample.
// 2. Faststart: `moov` moved ahead of `mdat` (ffmpeg's `-movflags
//    faststart`), so a player sees the index before the media. The chunk
//    offsets in stco/co64 shift by the moov's size.

type Box = { type: string; data?: Uint8Array; kids?: Box[] };

const CONTAINERS = new Set(["moov", "trak", "mdia", "minf", "stbl"]);

function parse(bytes: Uint8Array, from: number, to: number): Box[] | null {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const boxes: Box[] = [];
  for (let at = from; at < to; ) {
    if (at + 8 > to) return null;
    const size = view.getUint32(at);
    if (size < 8 || at + size > to) return null; // 64-bit sizes: never ours
    const type = String.fromCharCode(...bytes.subarray(at + 4, at + 8));
    if (CONTAINERS.has(type)) {
      const kids = parse(bytes, at + 8, at + size);
      if (!kids) return null;
      boxes.push({ type, kids });
    } else {
      boxes.push({ type, data: bytes.subarray(at + 8, at + size) });
    }
    at += size;
  }
  return boxes;
}

const sizeOf = (b: Box): number =>
  8 + (b.kids ? b.kids.reduce((n, k) => n + sizeOf(k), 0) : b.data!.length);

function write(b: Box, out: Uint8Array, at: number): number {
  const size = sizeOf(b);
  new DataView(out.buffer, out.byteOffset).setUint32(at, size);
  for (let i = 0; i < 4; i++) out[at + 4 + i] = b.type.charCodeAt(i);
  let p = at + 8;
  if (b.kids) for (const k of b.kids) p = write(k, out, p);
  else {
    out.set(b.data!, p);
    p += b.data!.length;
  }
  return p;
}

const find = (boxes: Box[], type: string): Box | undefined =>
  boxes.find((b) => b.type === type);

function* allOf(boxes: Box[], type: string): Generator<Box> {
  for (const b of boxes) {
    if (b.type === type) yield b;
    if (b.kids) yield* allOf(b.kids, type);
  }
}

const u32 = (d: Uint8Array, at: number) =>
  new DataView(d.buffer, d.byteOffset, d.byteLength).getUint32(at);

/** Each sample's [offset, size] in the file, from stsz + stsc + stco. */
function sampleRanges(stbl: Box): [number, number][] | null {
  const stsz = find(stbl.kids!, "stsz")?.data;
  const stsc = find(stbl.kids!, "stsc")?.data;
  const stco = find(stbl.kids!, "stco")?.data;
  if (!stsz || !stsc || !stco) return null;
  const fixed = u32(stsz, 4);
  const count = u32(stsz, 8);
  const sizes = Array.from(
    { length: count },
    (_, i) => fixed || u32(stsz, 12 + i * 4),
  );
  const runs = Array.from({ length: u32(stsc, 4) }, (_, i) => ({
    first: u32(stsc, 8 + i * 12),
    per: u32(stsc, 12 + i * 12),
  }));
  const chunks = Array.from({ length: u32(stco, 4) }, (_, i) =>
    u32(stco, 8 + i * 4),
  );
  const out: [number, number][] = [];
  let s = 0;
  chunks.forEach((offset, c) => {
    const run = [...runs].reverse().find((r) => r.first <= c + 1);
    let at = offset;
    for (let i = 0; i < (run?.per ?? 0) && s < count; i++, s++) {
      out.push([at, sizes[s]]);
      at += sizes[s];
    }
  });
  return out.length === count ? out : null;
}

/** Does this AVCC sample (4-byte length-prefixed NALs) hold an IDR slice? */
function isIdr(sample: Uint8Array): boolean {
  for (let at = 0; at + 5 <= sample.length; ) {
    const len = u32(sample, at);
    if ((sample[at + 4] & 0x1f) === 5) return true;
    at += 4 + len;
  }
  return false;
}

export function finishMp4(mp4: Uint8Array): Uint8Array {
  const top = parse(mp4, 0, mp4.length);
  if (!top) return mp4;
  const moov = find(top, "moov");
  const mdat = find(top, "mdat");
  if (!moov || !mdat) return mp4;

  // 1. stss, from the samples as they sit in this file (before any move).
  for (const stbl of allOf([moov], "stbl")) {
    if (find(stbl.kids!, "stss")) continue;
    const ranges = sampleRanges(stbl);
    if (!ranges) continue;
    const sync = ranges
      .map(([at, size], i) => (isIdr(mp4.subarray(at, at + size)) ? i + 1 : 0))
      .filter((n) => n > 0);
    if (sync.length === 0 || sync.length === ranges.length) continue;
    const data = new Uint8Array(8 + sync.length * 4);
    const view = new DataView(data.buffer);
    view.setUint32(4, sync.length);
    sync.forEach((n, i) => view.setUint32(8 + i * 4, n));
    const at = stbl.kids!.findIndex((k) => k.type === "stsz");
    stbl.kids!.splice(at + 1, 0, { type: "stss", data });
  }

  // 2. moov ahead of mdat; offsets into mdat move by what now precedes it.
  const before = (list: Box[]) =>
    list.slice(0, list.indexOf(mdat)).reduce((n, b) => n + sizeOf(b), 0);
  const oldStart = before(top);
  const order = top.filter((b) => b !== moov);
  order.splice(order.indexOf(mdat), 0, moov);
  const shift = before(order) - oldStart;
  if (shift !== 0) {
    for (const stco of allOf([moov], "stco")) {
      const d = stco.data!.slice();
      const view = new DataView(d.buffer);
      for (let i = 0, n = view.getUint32(4); i < n; i++)
        view.setUint32(8 + i * 4, view.getUint32(8 + i * 4) + shift);
      stco.data = d;
    }
    for (const co64 of allOf([moov], "co64")) {
      const d = co64.data!.slice();
      const view = new DataView(d.buffer);
      for (let i = 0, n = view.getUint32(4); i < n; i++)
        view.setBigUint64(
          8 + i * 8,
          view.getBigUint64(8 + i * 8) + BigInt(shift),
        );
      co64.data = d;
    }
  }

  const out = new Uint8Array(order.reduce((n, b) => n + sizeOf(b), 0));
  let at = 0;
  for (const b of order) at = write(b, out, at);
  return out;
}
