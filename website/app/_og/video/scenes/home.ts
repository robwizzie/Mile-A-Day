import { BRAND } from "../../shared";
import { ogAsset, type Ctx, type Scene } from "../render";
import {
  around,
  beat,
  brandGradient,
  clamp01,
  confetti,
  ease,
  flame,
  font,
  foreground,
  ground,
  lerp,
  lockup,
  roundRect,
  storePill,
} from "../kit";

// The home page's video: the hero's headline lands beside the real dashboard,
// and ONE card tells the story — today's mile fills its ring, a check, a small
// burst, and the card becomes the streak (512: the screenshot's 511, plus
// today). Everything has landed by ~3.5 s and holds still to be read.

const DONE_AT = 3.0;

export async function homeScene(): Promise<Scene> {
  const [icon, dashboard] = await Promise.all([
    ogAsset("icon.png"),
    ogAsset("dashboard.jpg"),
  ]);

  return (g, t) => {
    ground(g, t);
    foreground(g, t);

    // The phone rises in and stays put.
    const rise = ease.outCubic(beat(t, 0.15, 0.9));
    const px = 836;
    const py = 66;
    const pw = 320;
    const ph = 590;
    around(
      g,
      px + pw / 2,
      py + ph / 2,
      {
        rotate: (6 * Math.PI) / 180,
        alpha: clamp01(rise * 1.6),
        dy: (1 - rise) * 200,
      },
      () => {
        g.save();
        g.shadowColor = "rgba(199,37,84,0.3)";
        g.shadowBlur = 90;
        roundRect(g, px - 10, py - 10, pw + 20, ph + 20, 54);
        g.fillStyle = "#1c1c1e";
        g.fill();
        g.restore();
        g.lineWidth = 2;
        g.strokeStyle = "rgba(255,255,255,0.12)";
        roundRect(g, px - 10, py - 10, pw + 20, ph + 20, 54);
        g.stroke();
        g.save();
        roundRect(g, px, py, pw, ph, 44);
        g.clip();
        g.drawImage(
          dashboard,
          0,
          0,
          dashboard.width,
          (dashboard.width * ph) / pw,
          px,
          py,
          pw,
          ph,
        );
        g.restore();
      },
    );

    mileCard(g, t);

    // The copy column.
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

/** Today's mile on a card over the phone's corner, turning into the streak. */
function mileCard(g: Ctx, t: number) {
  const x = 664;
  const y = 404;
  const w = 344;
  const h = 132;
  const cardIn = ease.outBack(beat(t, 0.7, 0.6));
  const fill = ease.inOutCubic(beat(t, 1.1, DONE_AT - 1.1));
  const done = beat(t, DONE_AT, 0.4); // the card's settle and border
  // The text swap: the distance goes out, then the streak comes in.
  const out = beat(t, DONE_AT, 0.15);
  const into = ease.outCubic(beat(t, DONE_AT + 0.12, 0.35));
  const settle = done > 0 && done < 1 ? Math.sin(done * Math.PI) * 0.025 : 0;

  // The burst comes from behind the card, not over its words.
  confetti(g, t, x + 66, y + h / 2, DONE_AT, { seed: 11 });
  around(
    g,
    x + w / 2,
    y + h / 2,
    {
      scale: lerp(0.85, 1, cardIn) + settle,
      alpha: clamp01(cardIn * 2),
      dy: (1 - cardIn) * 20,
    },
    () => {
      g.save();
      g.shadowColor = "rgba(0,0,0,0.55)";
      g.shadowBlur = 40;
      g.shadowOffsetY = 16;
      roundRect(g, x, y, w, h, 28);
      g.fillStyle = "rgba(26,26,28,0.95)";
      g.fill();
      g.restore();
      g.lineWidth = 2;
      g.strokeStyle = `rgba(199,37,84,${lerp(0.12, 0.6, done)})`;
      roundRect(g, x, y, w, h, 28);
      g.stroke();

      // The ring, then the check inside it.
      const rx = x + 66;
      const ry = y + h / 2;
      g.lineWidth = 11;
      g.strokeStyle = "rgba(199,37,84,0.2)";
      g.beginPath();
      g.arc(rx, ry, 38, 0, Math.PI * 2);
      g.stroke();
      if (fill > 0) {
        g.lineCap = "round";
        g.strokeStyle = brandGradient(g, rx - 40, rx + 40);
        g.beginPath();
        // A full 2π sweep with round caps draws nothing in Skia.
        g.arc(
          rx,
          ry,
          38,
          -Math.PI / 2,
          -Math.PI / 2 + Math.PI * 2 * Math.min(fill, 0.9999),
        );
        g.stroke();
        g.lineCap = "butt";
      }
      check(g, rx, ry, ease.outCubic(beat(t, DONE_AT, 0.35)));

      // Text: the distance counting up, crossfading to the streak.
      const tx = x + 132;
      g.save();
      g.globalAlpha *= 1 - out;
      g.fillStyle = BRAND.muted;
      g.font = font.body(19, 700);
      g.fillText("TODAY", tx, y + 52);
      g.font = font.head(56);
      g.fillStyle = BRAND.ink;
      g.fillText(`${fill.toFixed(2)} MI`, tx, y + 104);
      g.restore();
      if (into > 0) {
        g.save();
        g.globalAlpha *= into;
        const dy = (1 - into) * 10;
        g.fillStyle = BRAND.muted;
        g.font = font.body(19, 700);
        g.fillText("MILE DONE", tx, y + 52 + dy);
        flame(g, tx - 2, y + 66 + dy, 34, t);
        g.font = font.head(56);
        g.fillStyle = brandGradient(g, tx, tx + 200);
        g.fillText("512 DAYS", tx + 38, y + 104 + dy);
        g.restore();
      }
    },
  );
}

/** A check drawing itself inside the ring (k: 0→1). */
function check(g: Ctx, cx: number, cy: number, k: number) {
  if (k <= 0) return;
  const pts: [number, number][] = [
    [cx - 15, cy + 1],
    [cx - 4, cy + 12],
    [cx + 17, cy - 11],
  ];
  g.lineWidth = 8;
  g.lineCap = "round";
  g.lineJoin = "round";
  g.strokeStyle = BRAND.ink;
  g.beginPath();
  g.moveTo(...pts[0]);
  if (k < 0.4) {
    const q = k / 0.4;
    g.lineTo(lerp(pts[0][0], pts[1][0], q), lerp(pts[0][1], pts[1][1], q));
  } else {
    const q = (k - 0.4) / 0.6;
    g.lineTo(...pts[1]);
    g.lineTo(lerp(pts[1][0], pts[2][0], q), lerp(pts[1][1], pts[2][1], q));
  }
  g.stroke();
  g.lineCap = "butt";
}
