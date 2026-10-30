import type { Image } from "@napi-rs/canvas";
import { BRAND } from "../../shared";
import { ogAsset, type Ctx, type Scene } from "../render";
import {
  around,
  beat,
  brandGradient,
  clamp01,
  confetti,
  ease,
  font,
  foreground,
  ground,
  lerp,
  lockup,
  radialGlow,
  roundRect,
  storePill,
} from "../kit";

// The home page's video, told with the app's own screens: the hero's
// headline lands beside an iPhone showing the real dashboard (the hero's
// capture), Start Mile gets a tap, and the app's real "Still lit. Day 511"
// share card pops out of the phone with a small burst. Everything has landed
// by ~2.8 s and holds still to be read.

// The phone: the screen is the dashboard capture (776×1680) at this width,
// bleeding off the bottom edge like a product shot.
const SX = 832;
const SY = 54;
const SW = 322;
const SCALE = SW / 776;
const SH = 1680 * SCALE;

/** Start Mile in the capture (776-wide coordinates). */
const START = { x: 30, y: 991, w: 716, h: 104 };

const TAP_AT = 1.45;
const CARD_AT = 2.0;

export async function homeScene(): Promise<Scene> {
  const [icon, dashboard, card] = await Promise.all([
    ogAsset("icon.png"),
    ogAsset("dashboard-full.jpg"),
    ogAsset("still-lit.jpg"),
  ]);

  return (g, t) => {
    ground(g, t);
    foreground(g, t);

    phone(g, t, dashboard);
    stillLit(g, t, card);

    // The copy column — the hero's own words.
    lockup(g, icon, t);
    const l1 = ease.outQuint(beat(t, 0.25, 0.7));
    const l2 = ease.outQuint(beat(t, 0.45, 0.7));
    around(g, 72, 290, { alpha: l1, dy: (1 - l1) * 40 }, () => {
      g.font = font.head(140);
      g.fillStyle = BRAND.ink;
      g.fillText("ONE MILE.", 72, 290);
    });
    around(g, 72, 413, { alpha: l2, dy: (1 - l2) * 40 }, () => {
      g.font = font.head(140);
      g.fillStyle = brandGradient(g, 72, 600);
      g.fillText("EVERY DAY.", 72, 413);
    });
    const sub = ease.outCubic(beat(t, 0.9, 0.6));
    around(g, 72, 470, { alpha: sub, dy: (1 - sub) * 12 }, () => {
      g.font = font.body(30);
      g.fillStyle = BRAND.muted;
      g.fillText("Walk it or run it. Just get it done.", 72, 470);
    });
    storePill(g, t, 72, 512, undefined, 1.2);
  };
}

/** An iPhone (titanium edge, black bezel) rising in, then still. */
function phone(g: Ctx, t: number, screen: Image) {
  const rise = ease.outCubic(beat(t, 0.1, 0.9));
  around(
    g,
    SX + SW / 2,
    SY + 300,
    { alpha: clamp01(rise * 1.5), dy: (1 - rise) * 140 },
    () => {
      // Backlight: the brand glow the phone sits in.
      radialGlow(g, SX + SW / 2, SY + 260, 420, 0.3);

      const edge = 13;
      const bezel = 9;
      // Side buttons, behind the body.
      g.fillStyle = "#2c2c30";
      roundRect(g, SX - edge - 3, SY + 150, 6, 52, 3);
      g.fill();
      roundRect(g, SX - edge - 3, SY + 218, 6, 52, 3);
      g.fill();
      roundRect(g, SX + SW + edge - 3, SY + 180, 6, 84, 3);
      g.fill();

      // Body: a titanium edge with a soft shadow.
      g.save();
      g.shadowColor = "rgba(0,0,0,0.6)";
      g.shadowBlur = 50;
      g.shadowOffsetY = 20;
      roundRect(g, SX - edge, SY - edge, SW + edge * 2, SH + edge * 2, 60);
      const ti = g.createLinearGradient(SX - edge, 0, SX + SW + edge, 0);
      ti.addColorStop(0, "#4a4a50");
      ti.addColorStop(0.08, "#26262a");
      ti.addColorStop(0.92, "#26262a");
      ti.addColorStop(1, "#4a4a50");
      g.fillStyle = ti;
      g.fill();
      g.restore();
      roundRect(g, SX - bezel, SY - bezel, SW + bezel * 2, SH + bezel * 2, 54);
      g.fillStyle = "#030303";
      g.fill();

      // The screen.
      g.save();
      roundRect(g, SX, SY, SW, SH, 45);
      g.clip();
      g.drawImage(screen, SX, SY, SW, SH);
      tap(g, t);
      g.restore();

      g.lineWidth = 1.5;
      g.strokeStyle = "rgba(255,255,255,0.14)";
      roundRect(g, SX - edge, SY - edge, SW + edge * 2, SH + edge * 2, 60);
      g.stroke();
    },
  );
}

/** A tap on Start Mile: the button dips and a ripple spreads across it. */
function tap(g: Ctx, t: number) {
  const p = beat(t, TAP_AT, 0.55);
  if (p <= 0 || p >= 1) return;
  const x = SX + START.x * SCALE;
  const y = SY + START.y * SCALE;
  const w = START.w * SCALE;
  const h = START.h * SCALE;
  g.save();
  roundRect(g, x, y, w, h, h / 2);
  g.clip();
  g.fillStyle = `rgba(0,0,0,${0.22 * Math.sin(Math.min(1, p * 2.2) * Math.PI)})`;
  g.fillRect(x, y, w, h);
  const r = lerp(8, w * 0.75, ease.outCubic(p));
  g.fillStyle = `rgba(255,255,255,${0.32 * (1 - p)})`;
  g.beginPath();
  g.arc(x + w * 0.42, y + h / 2, r, 0, Math.PI * 2);
  g.fill();
  g.restore();
}

/**
 * The app's real share card ("Still lit." · Day 511) popping out of the
 * phone and landing tilted beside it, with a small burst from behind.
 */
function stillLit(g: Ctx, t: number, card: Image) {
  const h = 364;
  const w = (h * card.width) / card.height;
  const fx = 668; // where it lands (top-left)
  const fy = 206;
  const p = beat(t, CARD_AT, 0.75);
  if (p <= 0) return;
  const move = ease.outCubic(p);
  const pop = ease.outBack(p);
  // From the phone's screen to its spot.
  const cx = lerp(SX + SW / 2, fx + w / 2, move);
  const cy = lerp(SY + 290, fy + h / 2, move);

  // The burst comes from the card's top edge as it lands, above it.
  confetti(g, t, fx + w / 2, fy + 24, CARD_AT + 0.4, { seed: 11 });

  around(
    g,
    cx,
    cy,
    {
      scale: lerp(0.55, 1, pop),
      rotate: lerp(0.06, -0.105, move),
      alpha: clamp01(p * 3),
    },
    () => {
      const x = cx - w / 2;
      const y = cy - h / 2;
      g.save();
      g.shadowColor = "rgba(0,0,0,0.6)";
      g.shadowBlur = 50;
      g.shadowOffsetY = 22;
      roundRect(g, x, y, w, h, 20);
      g.fillStyle = "#120c0a";
      g.fill();
      g.restore();
      g.save();
      roundRect(g, x, y, w, h, 20);
      g.clip();
      g.drawImage(card, x, y, w, h);
      g.restore();
      g.lineWidth = 1.5;
      g.strokeStyle = "rgba(255,255,255,0.16)";
      roundRect(g, x, y, w, h, 20);
      g.stroke();
    },
  );
}
