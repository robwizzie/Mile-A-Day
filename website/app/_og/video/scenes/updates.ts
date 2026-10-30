import { loadImage, type Image } from "@napi-rs/canvas";
import { CURRENT_RELEASE, type ReleaseFeature } from "@/lib/releases";
import { BRAND } from "../../shared";
import { ogAsset, type Scene } from "../render";
import {
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
  storePill,
  wrap,
} from "../kit";

// /updates' video: the current release from lib/releases.ts — its version and
// headline, and its first features (the same icon and colour as the page)
// dealt in as cards, with the rest counted below. A release added there moves
// this video too.

const SHOWN = 4;
const CARD_H = 88;
const GAP = 16;
const COL_X = 676;
const COL_W = 452;

export async function updatesScene(): Promise<Scene> {
  const release = CURRENT_RELEASE;
  const [icon, glyphs] = await Promise.all([
    ogAsset("icon.png"),
    Promise.all(release.features.map(featureGlyph)),
  ]);
  const features = release.features
    .map((f, i) => ({ ...f, glyph: glyphs[i] }))
    .slice(0, SHOWN);
  const more = release.features.length - features.length;
  const step = CARD_H + GAP;
  const stackH = features.length * step - GAP + (more > 0 ? 58 : 0);
  const top0 = Math.round((630 - stackH) / 2);

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
      { scale: lerp(0.85, 1, tagIn), alpha: clamp01(tagIn * 2) },
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
      around(g, 72, y, { alpha: p, dy: (1 - p) * 40 }, () => {
        g.font = font.head(px);
        const last = i === lines.length - 1;
        g.fillStyle = last ? brandGradient(g, 72, 600) : BRAND.ink;
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

    // The features, dealt in one by one; then a single highlight passes
    // down the stack, and everything holds.
    features.forEach((f, k) => {
      const y = top0 + k * step;
      const deal = ease.outCubic(beat(t, 0.6 + k * 0.18, 0.55));
      const lit = beat(t, 2.3 + k * 0.3, 0.6);
      const glow = lit > 0 && lit < 1 ? Math.sin(lit * Math.PI) : 0;
      around(
        g,
        COL_X + COL_W / 2,
        y + CARD_H / 2,
        { alpha: deal, dx: (1 - deal) * 60 },
        () => featureCard(g, f, COL_X, y, glow),
      );
    });
    if (more > 0) {
      const m = ease.outCubic(beat(t, 1.6, 0.5));
      const y = top0 + features.length * step + 26;
      around(g, COL_X, y, { alpha: m, dy: (1 - m) * 10 }, () => {
        g.font = font.body(24, 700);
        g.fillStyle = BRAND.muted;
        g.fillText(`+ ${more} more in this update`, COL_X + 8, y);
      });
    }
  };
}

function featureCard(
  g: Parameters<Scene>[0],
  f: ReleaseFeature & { glyph: Image | null },
  x: number,
  y: number,
  /** 0→1→0 as the highlight passes this card: its border takes its colour. */
  glow: number,
) {
  const pad = (CARD_H - 56) / 2;
  roundRect(g, x, y, COL_W, CARD_H, 22);
  g.fillStyle = "rgba(255,255,255,0.05)";
  g.fill();
  g.fillStyle = hexA(f.color, 0.06 * glow);
  g.fill();
  g.lineWidth = 1.5;
  g.strokeStyle = glow > 0 ? hexA(f.color, 0.09 + 0.5 * glow) : "rgba(255,255,255,0.09)";
  g.stroke();
  roundRect(g, x + pad, y + pad, 56, 56, 16);
  g.fillStyle = hexA(f.color, 0.18);
  g.fill();
  if (f.glyph) g.drawImage(f.glyph, x + pad + 12, y + pad + 12, 32, 32);
  g.font = font.body(25, 700);
  g.fillStyle = BRAND.ink;
  g.textBaseline = "middle";
  g.fillText(ellipsize(g, f.title, COL_W - 110), x + pad + 74, y + CARD_H / 2 + 1);
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
