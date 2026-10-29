import { BRAND } from "../../shared";
import { ogAsset, type Scene } from "../render";
import {
  around,
  beat,
  brandGradient,
  clamp01,
  confetti,
  ease,
  font,
  ground,
  lerp,
  lockup,
  foreground,
  roundRect,
  sparkles,
  storePill,
  streakChip,
} from "../kit";

// The home page's video: the hero's headline lands beside the real dashboard,
// and today's mile fills its ring — 0.00 to 1.00 mi, MILE DONE, confetti, and
// the streak ticks over a day (511 → 512: the screenshot's own streak).

const DONE_AT = 3.1;

export async function homeScene(): Promise<Scene> {
  const [icon, dashboard] = await Promise.all([
    ogAsset("icon.png"),
    ogAsset("dashboard.jpg"),
  ]);

  return (g, t) => {
    ground(g, t);
    foreground(g, t);

    // The phone, floating in from below and bobbing.
    const rise = ease.outBack(beat(t, 0.15, 0.9));
    const bob = 0;
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
        dy: (1 - rise) * 260 + bob,
      },
      () => {
        g.save();
        g.shadowColor = "rgba(199,37,84,0.35)";
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

    // Today's mile, on a glass card over the phone's corner.
    const cardIn = ease.outBack(beat(t, 0.75, 0.6));
    const cx = 676;
    const cy = 420;
    const cw = 330;
    const ch = 124;
    const fill = ease.inOutCubic(beat(t, 1.15, DONE_AT - 1.15));
    const done = t >= DONE_AT;
    const donePop = beat(t, DONE_AT, 0.5);
    around(
      g,
      cx + cw / 2,
      cy + ch / 2,
      {
        scale:
          lerp(0.6, 1, cardIn) +
          (donePop > 0 && donePop < 1 ? Math.sin(donePop * Math.PI) * 0.05 : 0),
        alpha: clamp01(cardIn * 2),
        dy: bob * 0.4,
      },
      () => {
        g.save();
        g.shadowColor = "rgba(0,0,0,0.55)";
        g.shadowBlur = 40;
        g.shadowOffsetY = 16;
        roundRect(g, cx, cy, cw, ch, 28);
        g.fillStyle = "rgba(28,28,30,0.92)";
        g.fill();
        g.restore();
        g.lineWidth = 2;
        g.strokeStyle = done ? "rgba(199,37,84,0.7)" : "rgba(255,255,255,0.1)";
        roundRect(g, cx, cy, cw, ch, 28);
        g.stroke();

        const rx = cx + 64;
        const ry = cy + ch / 2;
        g.lineWidth = 12;
        g.strokeStyle = "rgba(199,37,84,0.22)";
        g.beginPath();
        g.arc(rx, ry, 38, 0, Math.PI * 2);
        g.stroke();
        if (fill > 0) {
          g.lineCap = "round";
          g.strokeStyle = brandGradient(g, rx - 40, rx + 40);
          g.beginPath();
          g.arc(rx, ry, 38, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.min(fill, 0.9999));
          g.stroke();
          g.lineCap = "butt";
        }
        if (done) {
          // The check draws itself inside the full ring.
          const k = ease.outCubic(beat(t, DONE_AT, 0.35));
          g.lineWidth = 8;
          g.lineCap = "round";
          g.lineJoin = "round";
          g.strokeStyle = BRAND.ink;
          g.beginPath();
          const pts = [
            [rx - 15, ry + 1],
            [rx - 4, ry + 12],
            [rx + 17, ry - 11],
          ];
          g.moveTo(pts[0][0], pts[0][1]);
          if (k < 0.4) {
            const q = k / 0.4;
            g.lineTo(
              lerp(pts[0][0], pts[1][0], q),
              lerp(pts[0][1], pts[1][1], q),
            );
          } else {
            const q = (k - 0.4) / 0.6;
            g.lineTo(pts[1][0], pts[1][1]);
            g.lineTo(
              lerp(pts[1][0], pts[2][0], q),
              lerp(pts[1][1], pts[2][1], q),
            );
          }
          g.stroke();
          g.lineCap = "butt";
        }

        g.fillStyle = BRAND.muted;
        g.font = font.body(19, 700);
        g.fillText(done ? "TODAY'S MILE" : "TODAY", cx + 128, cy + 50);
        g.font = font.head(54);
        g.fillStyle = done ? brandGradient(g, cx + 128, cx + 300) : BRAND.ink;
        g.fillText(
          done ? "MILE DONE" : `${fill.toFixed(2)} MI`,
          cx + 128,
          cy + 100,
        );
      },
    );

    // The streak, one day short until the mile lands.
    const ticked = t >= DONE_AT + 0.05;
    streakChip(g, t, 702, 344 + bob * 0.4, ticked ? 512 : 511, {
      appear: 1.0,
      start: ticked ? DONE_AT + 0.05 : 99,
      from: 511,
      dur: 0.25,
      px: 26,
    });
    confetti(g, t, cx + 64, cy + ch / 2, DONE_AT, { seed: 11, n: 54 });

    // The copy column.
    lockup(g, icon, t);
    const l1 = ease.outQuint(beat(t, 0.25, 0.7));
    const l2 = ease.outQuint(beat(t, 0.5, 0.7));
    g.font = font.head(140);
    around(g, 72, 290, { alpha: l1, dy: (1 - l1) * 60 }, () => {
      g.fillStyle = BRAND.ink;
      g.fillText("ONE MILE.", 72, 290);
    });
    around(g, 72, 413, { alpha: l2, dy: (1 - l2) * 60 }, () => {
      g.font = font.head(140);
      const shine = beat(t, 2.0, 1.1);
      g.fillStyle = brandGradient(
        g,
        72,
        600,
        shine > 0 && shine < 1 ? ease.inOutSine(shine) : null,
      );
      g.fillText("EVERY DAY.", 72, 413);
    });
    const sub = ease.outCubic(beat(t, 0.95, 0.6));
    around(g, 72, 470, { alpha: sub, dy: (1 - sub) * 16 }, () => {
      g.font = font.body(30);
      g.fillStyle = BRAND.muted;
      g.fillText("Walk it or run it. Just get it done.", 72, 470);
    });
    storePill(g, t, 72, 512, undefined, 1.3);

    sparkles(g, t, [
      { x: 1150, y: 120, s: 10, d: 0.3 },
      { x: 790, y: 120, s: 7, d: 1.9 },
      { x: 1100, y: 560, s: 9, d: 3.1 },
      { x: 640, y: 70, s: 6, d: 4.2 },
    ]);

  };
}
