import { loadImage, type Image } from "@napi-rs/canvas";
import { CURRENT_RELEASE, type ReleaseFeature } from "@/lib/releases";
import { BRAND } from "../../shared";
import { ogAsset, type Scene } from "../render";
import {
  H,
  around,
  beat,
  brandGradient,
  clamp01,
  ease,
  ellipsize,
  fitSize,
  font,
  foreground,
  ground,
  lerp,
  lockup,
  roundRect,
  sparkles,
  storePill,
  wrap,
} from "../kit";

// /updates' video: the current release from lib/releases.ts — its version and
// headline, and every feature in it (the same icon and colour as the page)
// rolling up as a stack of cards. A release added there moves this video too.

const CARD_H = 84;
const GAP = 14;
const COL_X = 676;
const COL_W = 452;

export async function updatesScene(): Promise<Scene> {
  const release = CURRENT_RELEASE;
  const [icon, glyphs] = await Promise.all([
    ogAsset("icon.png"),
    Promise.all(release.features.map(featureGlyph)),
  ]);
  const features = release.features.map((f, i) => ({ ...f, glyph: glyphs[i] }));
  const step = CARD_H + GAP;

  return (g, t) => {
    ground(g, t);
    foreground(g, t);

    lockup(g, icon, t);

    // "WHAT'S NEW" tag, popping in.
    const tagIn = ease.outBack(beat(t, 0.2, 0.5));
    around(
      g,
      72,
      175,
      { scale: lerp(0.6, 1, tagIn), alpha: clamp01(tagIn * 2) },
      () => {
        g.font = font.body(22, 700);
        const label = `WHAT'S NEW · v${release.version}`;
        const w = g.measureText(label).width + 40;
        roundRect(g, 72, 156, w, 42, 21);
        g.fillStyle = "rgba(199,37,84,0.2)";
        g.fill();
        g.fillStyle = BRAND.pink;
        g.textBaseline = "middle";
        g.fillText(label, 92, 178);
        g.textBaseline = "alphabetic";
      },
    );

    // The release's headline, line by line.
    const headline = release.headline.toUpperCase();
    const px = fitSize(
      g,
      headline.split(" ").sort((a, b) => b.length - a.length)[0],
      font.head,
      104,
      540,
      64,
    );
    g.font = font.head(px);
    const lines = wrap(g, headline, 560, 3);
    const lh = px * 0.92;
    const top = 214 + px * 0.82 + (3 - lines.length) * lh * 0.35;
    lines.forEach((line, i) => {
      const p = ease.outQuint(beat(t, 0.35 + i * 0.14, 0.7));
      const y = top + i * lh;
      around(g, 72, y, { alpha: p, dy: (1 - p) * 50 }, () => {
        g.font = font.head(px);
        const last = i === lines.length - 1;
        const shine = beat(t, 2.2, 1.1);
        g.fillStyle = last
          ? brandGradient(
              g,
              72,
              600,
              shine > 0 && shine < 1 ? ease.inOutSine(shine) : null,
            )
          : BRAND.ink;
        g.fillText(line, 72, y);
      });
    });
    const subIn = ease.outCubic(beat(t, 0.9, 0.6));
    const subY = top + (lines.length - 1) * lh + 52;
    around(g, 72, subY, { alpha: subIn, dy: (1 - subIn) * 14 }, () => {
      g.font = font.body(27);
      g.fillStyle = BRAND.muted;
      g.fillText(
        `${release.features.length} new things · ${release.date}`,
        72,
        subY,
      );
    });
    storePill(g, t, 72, 532, undefined, 1.3);

    // The features, dealt in from the right, then rolling up forever.
    const scroll = Math.max(0, t - 1.9) * 46;
    g.save();
    g.beginPath();
    g.rect(COL_X - 30, 0, COL_W + 60, H);
    g.clip();
    const first = Math.floor(scroll / step);
    for (let k = first - 1; k < first + 8; k++) {
      const i = ((k % features.length) + features.length) % features.length;
      // Before the roll starts only the first pass is dealt; after, the list repeats.
      if (k < 0 || (t < 1.9 && k >= features.length)) continue;
      const y = 40 + k * step - scroll;
      if (y > H || y + CARD_H < 0) continue;
      const deal = ease.outBack(beat(t, 0.45 + Math.min(k, 6) * 0.11, 0.6));
      // Fade at the top and bottom edges.
      const edge = clamp01(Math.min((y + CARD_H) / 90, (H - y) / 110));
      around(
        g,
        COL_X + COL_W / 2,
        y + CARD_H / 2,
        { alpha: clamp01(deal * 2) * edge, dx: (1 - deal) * 320 },
        () => featureCard(g, features[i], COL_X, y),
      );
    }
    g.restore();

    sparkles(g, t, [
      { x: 620, y: 120, s: 9, d: 0.5 },
      { x: 1150, y: 600, s: 7, d: 2.4 },
      { x: 560, y: 470, s: 6, d: 3.6 },
    ]);
  };
}

function featureCard(
  g: Parameters<Scene>[0],
  f: ReleaseFeature & { glyph: Image | null },
  x: number,
  y: number,
) {
  roundRect(g, x, y, COL_W, CARD_H, 22);
  g.fillStyle = "rgba(255,255,255,0.05)";
  g.fill();
  g.lineWidth = 1.5;
  g.strokeStyle = "rgba(255,255,255,0.09)";
  g.stroke();
  roundRect(g, x + 14, y + 14, 56, 56, 16);
  g.fillStyle = hexA(f.color, 0.18);
  g.fill();
  if (f.glyph) g.drawImage(f.glyph, x + 26, y + 26, 32, 32);
  g.font = font.body(25, 700);
  g.fillStyle = BRAND.ink;
  g.textBaseline = "middle";
  g.fillText(ellipsize(g, f.title, COL_W - 110), x + 88, y + CARD_H / 2 + 1);
  g.textBaseline = "alphabetic";
}

/**
 * The feature's lucide icon, in its colour, as an image (SVG → Skia). Built
 * from the icon's own node list — a lucide component is a forwardRef whose
 * render hands its `iconNode` to the shared <Icon> — because Next won't let
 * a route pull in react-dom/server to render it.
 */
async function featureGlyph(f: ReleaseFeature): Promise<Image | null> {
  try {
    const el = (
      f.icon as unknown as {
        render: (p: object, r: null) => { props: { iconNode?: [string, Record<string, string>][] } };
      }
    ).render({}, null);
    const nodes = el.props.iconNode;
    if (!nodes?.length) return null;
    const attr = (v: string) => String(v).replace(/[&"<>]/g, (c) => `&#${c.charCodeAt(0)};`);
    const kids = nodes
      .map(([tag, attrs]) =>
        `<${tag} ${Object.entries(attrs)
          .filter(([k]) => k !== "key")
          .map(([k, v]) => `${k}="${attr(v)}"`)
          .join(" ")}/>`,
      )
      .join("");
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="${attr(f.color)}" stroke-width="2.25" stroke-linecap="round" stroke-linejoin="round">${kids}</svg>`;
    return await loadImage(Buffer.from(svg));
  } catch {
    return null;
  }
}

function hexA(hex: string, a: number): string {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
  return `rgba(${r},${g},${b},${a})`;
}
