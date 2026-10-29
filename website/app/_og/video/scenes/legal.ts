import { BRAND } from "../../shared";
import { ogAsset, type Ctx, type Scene } from "../render";
import {
  around,
  beat,
  brandGradient,
  clamp01,
  ease,
  font,
  foreground,
  ground,
  lerp,
  lockup,
  radialGlow,
  roundRect,
  seeded,
  sparkles,
  storePill,
  wrap,
} from "../kit";

// /privacy and /terms: a page writing itself line by line, then stamped —
// a shield for the privacy policy, a seal for the terms.

export type LegalVideo = {
  /** The title, split for two lines; the second is drawn in brand red. */
  title: [string, string];
  description: string;
  badge: "shield" | "seal";
};

const STAMP_AT = 2.3;

export async function legalScene(v: LegalVideo): Promise<Scene> {
  const icon = await ogAsset("icon.png");
  const rand = seeded(v.badge === "shield" ? 5 : 9);
  // The page's "text": paragraphs of bars with ragged ends.
  const bars: { y: number; w: number; head: boolean }[] = [];
  let y = 0;
  for (let para = 0; para < 4; para++) {
    bars.push({ y, w: 0.42 + rand() * 0.2, head: true });
    y += 26;
    const n = 2 + Math.floor(rand() * 2);
    for (let i = 0; i < n; i++) {
      bars.push({
        y,
        w: i === n - 1 ? 0.45 + rand() * 0.3 : 0.88 + rand() * 0.12,
        head: false,
      });
      y += 18;
    }
    y += 14;
  }

  return (g, t) => {
    ground(g, t);
    foreground(g, t);

    lockup(g, icon, t);
    v.title.forEach((line, i) => {
      const p = ease.outQuint(beat(t, 0.3 + i * 0.15, 0.7));
      const ly = 290 + i * 118;
      around(g, 72, ly, { alpha: p, dy: (1 - p) * 50 }, () => {
        g.font = font.head(132);
        const shine = beat(t, 2.6, 1.1);
        g.fillStyle =
          i === 1
            ? brandGradient(
                g,
                72,
                560,
                shine > 0 && shine < 1 ? ease.inOutSine(shine) : null,
              )
            : BRAND.ink;
        g.fillText(line, 72, ly);
      });
    });
    const sub = ease.outCubic(beat(t, 0.9, 0.6));
    around(g, 72, 462, { alpha: sub, dy: (1 - sub) * 14 }, () => {
      g.font = font.body(27);
      g.fillStyle = BRAND.muted;
      wrap(g, v.description, 640, 2).forEach((l, i) =>
        g.fillText(l, 72, 462 + i * 36),
      );
    });
    storePill(g, t, 72, 536, undefined, 1.3);

    page(g, t, bars, v.badge);

    sparkles(g, t, [
      { x: 1150, y: 90, s: 9, d: 0.2 },
      { x: 700, y: 560, s: 7, d: 2.1 },
      { x: 640, y: 100, s: 6, d: 3.3 },
    ]);
  };
}

function page(
  g: Ctx,
  t: number,
  bars: { y: number; w: number; head: boolean }[],
  badge: LegalVideo["badge"],
) {
  const x = 760;
  const y = 92;
  const w = 330;
  const h = 420;
  const p = ease.outBack(beat(t, 0.2, 0.85));
  const bob = Math.sin(t * 1.3) * 4;
  around(
    g,
    x + w / 2,
    y + h / 2,
    {
      rotate: lerp(0.22, 0.06, p),
      scale: lerp(0.75, 1, p),
      alpha: clamp01(p * 2),
      dy: bob,
    },
    () => {
      g.save();
      g.shadowColor = "rgba(0,0,0,0.6)";
      g.shadowBlur = 60;
      g.shadowOffsetY = 20;
      roundRect(g, x, y, w, h, 26);
      g.fillStyle = "#18181b";
      g.fill();
      g.restore();
      g.lineWidth = 2;
      g.strokeStyle = "rgba(255,255,255,0.1)";
      roundRect(g, x, y, w, h, 26);
      g.stroke();

      // The bars write in one after another, like a page being typed.
      const left = x + 34;
      const span = w - 68;
      bars.forEach((b, i) => {
        const q = ease.outCubic(beat(t, 0.55 + i * 0.075, 0.35));
        if (q <= 0) return;
        roundRect(
          g,
          left,
          y + 40 + b.y,
          Math.max(6, span * b.w * q),
          b.head ? 12 : 8,
          5,
        );
        g.fillStyle = b.head
          ? "rgba(199,37,84,0.75)"
          : "rgba(255,255,255,0.16)";
        g.fill();
      });
    },
  );

  // The stamp: drops in big, lands with a ripple.
  const sx = x + w - 8;
  const sy = y + h - 30;
  const r = 70;
  const s = beat(t, STAMP_AT, 0.45);
  if (s <= 0) return;
  const land = beat(t, STAMP_AT + 0.3, 0.8);
  if (land > 0 && land < 1) {
    g.lineWidth = 4 * (1 - land);
    g.strokeStyle = `rgba(255,77,125,${0.8 * (1 - land)})`;
    g.beginPath();
    g.arc(sx, sy + bob, r + 10 + land * 70, 0, Math.PI * 2);
    g.stroke();
  }
  around(
    g,
    sx,
    sy,
    {
      scale: lerp(1.9, 1, ease.outBack(s)),
      alpha: clamp01(s * 3),
      rotate: lerp(-0.5, -0.12, ease.outCubic(s)),
      dy: bob,
    },
    () => {
      radialGlow(g, sx, sy, r * 2.1, 0.45);
      g.beginPath();
      g.arc(sx, sy, r, 0, Math.PI * 2);
      g.fillStyle = brandGradient(g, sx - r, sx + r);
      g.fill();
      g.lineWidth = 3;
      g.strokeStyle = "rgba(255,255,255,0.35)";
      g.beginPath();
      g.arc(sx, sy, r - 9, 0, Math.PI * 2);
      g.stroke();
      if (badge === "shield") shield(g, sx, sy, 34);
      else seal(g, sx, sy, 30, t);
      check(
        g,
        sx,
        sy + (badge === "shield" ? 2 : 0),
        15,
        beat(t, STAMP_AT + 0.25, 0.4),
      );
    },
  );
}

function shield(g: Ctx, cx: number, cy: number, s: number) {
  g.beginPath();
  g.moveTo(cx, cy - s);
  g.quadraticCurveTo(
    cx + s * 0.55,
    cy - s * 0.72,
    cx + s * 0.85,
    cy - s * 0.72,
  );
  g.quadraticCurveTo(cx + s * 0.9, cy + s * 0.35, cx, cy + s);
  g.quadraticCurveTo(cx - s * 0.9, cy + s * 0.35, cx - s * 0.85, cy - s * 0.72);
  g.quadraticCurveTo(cx - s * 0.55, cy - s * 0.72, cx, cy - s);
  g.closePath();
  g.fillStyle = "rgba(255,255,255,0.18)";
  g.fill();
  g.lineWidth = 4;
  g.strokeStyle = "#fff";
  g.stroke();
}

/** A scalloped seal, slowly turning. */
function seal(g: Ctx, cx: number, cy: number, s: number, t: number) {
  g.beginPath();
  const n = 14;
  for (let i = 0; i <= n * 2; i++) {
    const a = (i / (n * 2)) * Math.PI * 2 + t * 0.4;
    const rr = i % 2 ? s : s * 0.84;
    const px = cx + Math.cos(a) * rr;
    const py = cy + Math.sin(a) * rr;
    if (i) g.lineTo(px, py);
    else g.moveTo(px, py);
  }
  g.closePath();
  g.fillStyle = "rgba(255,255,255,0.18)";
  g.fill();
  g.lineWidth = 4;
  g.strokeStyle = "#fff";
  g.stroke();
}

/** A check drawing itself (k: 0→1). */
function check(g: Ctx, cx: number, cy: number, s: number, k: number) {
  if (k <= 0) return;
  const pts: [number, number][] = [
    [cx - s, cy],
    [cx - s * 0.3, cy + s * 0.7],
    [cx + s, cy - s * 0.7],
  ];
  g.lineWidth = 6;
  g.lineCap = "round";
  g.lineJoin = "round";
  g.strokeStyle = "#fff";
  g.beginPath();
  g.moveTo(...pts[0]);
  if (k < 0.4) {
    const q = ease.outCubic(k / 0.4);
    g.lineTo(lerp(pts[0][0], pts[1][0], q), lerp(pts[0][1], pts[1][1], q));
  } else {
    const q = ease.outCubic((k - 0.4) / 0.6);
    g.lineTo(...pts[1]);
    g.lineTo(lerp(pts[1][0], pts[2][0], q), lerp(pts[1][1], pts[2][1], q));
  }
  g.stroke();
  g.lineCap = "butt";
}

export const PRIVACY: LegalVideo = {
  title: ["PRIVACY", "POLICY."],
  description: "How Mile A Day collects, uses, and protects your data.",
  badge: "shield",
};

export const TERMS: LegalVideo = {
  title: ["TERMS", "OF USE."],
  description: "The terms and conditions for using the Mile A Day app.",
  badge: "seal",
};
