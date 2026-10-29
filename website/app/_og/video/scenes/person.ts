import type { Image } from "@napi-rs/canvas";
import { BRAND } from "../../shared";
import type { Ctx, Scene } from "../render";
import {
  W,
  around,
  avatar,
  beat,
  brandGradient,
  clamp01,
  confetti,
  count,
  ease,
  ellipsize,
  embers,
  fitSize,
  font,
  ground,
  hashString,
  lerp,
  lockup,
  foreground,
  radialGlow,
  roundRect,
  seeded,
  sparkles,
  storePill,
  streakChip,
} from "../kit";

// The video for a link about ONE person — a profile or a post (the PersonCard
// of the PNG cards, in motion): their avatar pops in as the app's ring draws
// round it, the streak counts up and lands with confetti, the stats tick up.
// Same rule as the cards: only what `/public/users/:username` already
// publishes. A post shows its AUTHOR — the post itself (photo, route, caption)
// never appears; its side card is decoration, a locked "friends only" tile.

export type PersonVideo = {
  icon: Image;
  avatar: Image | null;
  initials: string;
  name: string;
  handle: string | null;
  streak: number | null;
  /** Shared stats, counted up; null when the account withholds them. */
  stats: {
    miles: number;
    milesText: (n: number) => string;
    friends: number;
  } | null;
  /** The profile's banner: its two gradient stops and the photo over them. */
  banner: { stops: [string, string]; image: Image | null } | null;
  headline: string;
  footnote: string;
  /** Draw the locked post tile on the right (post links). */
  post?: boolean;
  /** Seeds the decoration so each person's video is their own. */
  seed: string;
};

const LAND = 2.7; // when the streak counter lands

export function personScene(v: PersonVideo): Scene {
  const seed = hashString(v.seed);
  const sideCard = !!v.post;
  const r = sideCard ? 92 : 104;
  const acx = 72 + r + 6;
  const acy = sideCard ? 300 : 306;
  const textX = acx + r + 52;
  const textW = (sideCard ? 790 : W - 72) - textX;

  return (g, t) => {
    ground(g, t);
    if (v.banner) banner(g, t, v.banner);
    foreground(g, t);

    lockup(g, v.icon, t);
    if (sideCard) postTile(g, t, seed);

    avatar(
      g,
      v.avatar,
      v.initials,
      acx,
      acy,
      r,
      beat(t, 0.2, 0.7),
      ease.inOutCubic(beat(t, 0.5, 1.4)),
      t,
    );

    // Name, then handle, sliding up.
    const nameIn = ease.outQuint(beat(t, 0.55, 0.7));
    const namePx = fitSize(
      g,
      v.name,
      font.head,
      sideCard ? 96 : 112,
      textW,
      60,
    );
    g.font = font.head(namePx);
    const name = ellipsize(g, v.name, textW);
    const hasChip = v.streak !== null;
    const blockTop = acy - (hasChip ? 104 : 70) - (v.stats ? 10 : 0);
    const nameY = blockTop + namePx * 0.82;
    around(g, textX, nameY, { alpha: nameIn, dy: (1 - nameIn) * 40 }, () => {
      if (v.banner) textShadow(g);
      g.font = font.head(namePx);
      g.fillStyle = BRAND.ink;
      g.fillText(name, textX, nameY);
    });
    let y = nameY;
    if (v.handle) {
      const hIn = ease.outCubic(beat(t, 0.75, 0.6));
      y += 44;
      const hy = y;
      around(g, textX, hy, { alpha: hIn, dy: (1 - hIn) * 20 }, () => {
        if (v.banner) textShadow(g);
        g.font = font.body(32);
        g.fillStyle = BRAND.muted;
        g.fillText(ellipsize(g, v.handle!, textW), textX, hy);
      });
    }
    if (v.streak !== null) {
      y += 26;
      const chipY = y;
      const w = streakChip(g, t, textX, chipY, v.streak, {
        appear: 0.95,
        start: 1.15,
        dur: LAND - 1.15,
        px: 30,
      });
      if (t > LAND)
        embers(g, t, textX + 30, chipY + 22, {
          n: 9,
          seed,
          alpha: clamp01((t - LAND) * 2),
        });
      confetti(g, t, textX + w / 2, chipY + 26, LAND, { seed, n: 50 });
      y += 52;
    }
    if (v.stats) {
      const s = v.stats;
      const p = ease.outQuint(beat(t, 1.4, 1.5));
      const sIn = ease.outCubic(beat(t, 1.3, 0.5));
      y += 46;
      const sy = y;
      around(g, textX, sy, { alpha: sIn, dy: (1 - sIn) * 16 }, () => {
        g.font = font.body(28);
        g.fillStyle = BRAND.muted;
        const friends = Math.round(s.friends * p);
        g.fillText(
          ellipsize(
            g,
            `${s.milesText(s.miles * p)} · ${count(friends)} ${s.friends === 1 ? "friend" : "friends"}`,
            textW,
          ),
          textX,
          sy,
        );
      });
    }

    // Bottom row: the line about them, and the invite.
    const fIn = ease.outCubic(beat(t, 1.5, 0.6));
    around(g, 72, 560, { alpha: fIn, dy: (1 - fIn) * 18 }, () => {
      g.font = font.body(33, 700);
      g.fillStyle = BRAND.ink;
      g.fillText(ellipsize(g, v.headline, 690), 72, 548);
      g.font = font.body(24);
      g.fillStyle = BRAND.muted;
      g.fillText(ellipsize(g, v.footnote, 690), 72, 584);
    });
    g.font = font.body(25, 700);
    const pillW = 24 + 24 + 12 + g.measureText("Get Mile A Day").width + 24;
    storePill(g, t, W - 72 - pillW, 532, "Get Mile A Day", 1.8);

    sparkles(g, t, [
      { x: W - 120, y: 60, s: 9, d: 0.4 },
      { x: W - 330, y: 120, s: 6, d: 2.2 },
      { x: acx + r * 0.9, y: acy - r * 0.95, s: 10, d: 1.2 },
    ]);
  };
}

/** The banner across the top, scrimmed into the ground — part of the stage. */
function banner(g: Ctx, t: number, b: NonNullable<PersonVideo["banner"]>) {
  const bh = 330;
  g.save();
  const grad = g.createLinearGradient(0, 0, W * 0.55, bh * 1.6);
  grad.addColorStop(0, `rgb(${b.stops[0]})`);
  grad.addColorStop(0.5, `rgba(${b.stops[1]},0.9)`);
  grad.addColorStop(1, `rgba(${b.stops[1]},0.32)`);
  g.fillStyle = "#000";
  g.fillRect(0, 0, W, bh);
  g.fillStyle = grad;
  g.fillRect(0, 0, W, bh);
  if (b.image) {
    // Still, and there from the first frame: a photo that moves or fades
    // changes every pixel of every frame, which is what makes a clip heavy.
    const s = Math.max(W / b.image.width, bh / b.image.height);
    const w = b.image.width * s;
    const h = b.image.height * s;
    g.beginPath();
    g.rect(0, 0, W, bh);
    g.clip();
    g.drawImage(b.image, (W - w) / 2, (bh - h) / 2, w, h);
  } else {
    // No photo: a soft sheen travels across the gradient, once a loop.
    const x = lerp(-300, W + 300, ease.inOutSine(t / 6));
    radialGlow(g, x, bh * 0.4, 320, 0.18, "255,255,255");
  }
  const scrim = g.createLinearGradient(0, 0, 0, bh);
  scrim.addColorStop(0, "rgba(0,0,0,0.42)");
  scrim.addColorStop(0.4, "rgba(0,0,0,0)");
  scrim.addColorStop(0.75, "rgba(10,10,10,0.75)");
  scrim.addColorStop(1, BRAND.ground);
  g.fillStyle = scrim;
  g.fillRect(0, 0, W, bh + 1);
  g.restore();
}

/**
 * The post, as a locked tile: an abstract "photo" with a decorative route
 * drawing itself and a runner dot along it — invented from the seed, never
 * the post's real route — under a "Friends only" lock.
 */
function postTile(g: Ctx, t: number, seed: number) {
  const x = 838;
  const y = 116;
  const w = 290;
  const h = 360;
  const p = ease.outBack(beat(t, 0.35, 0.8));
  const bob = Math.sin(t * 1.4) * 5;
  around(
    g,
    x + w / 2,
    y + h / 2,
    {
      rotate: lerp(0.2, -0.05, p),
      scale: lerp(0.7, 1, p),
      alpha: clamp01(p * 2),
      dy: bob,
    },
    () => {
      g.save();
      g.shadowColor = "rgba(199,37,84,0.35)";
      g.shadowBlur = 70;
      roundRect(g, x, y, w, h, 30);
      g.fillStyle = "#17171a";
      g.fill();
      g.restore();
      g.save();
      roundRect(g, x + 12, y + 12, w - 24, h - 92, 22);
      g.clip();
      const bg = g.createLinearGradient(x, y, x + w, y + h);
      bg.addColorStop(0, "#3a1220");
      bg.addColorStop(1, "#140a10");
      g.fillStyle = bg;
      g.fillRect(x, y, w, h);
      radialGlow(g, x + w * 0.7, y + 70, 180, 0.35);

      // The route: a seeded loop through the tile.
      const rand = seeded(seed);
      const pts: [number, number][] = [];
      const n = 7;
      for (let i = 0; i <= n; i++) {
        const a = (i / n) * Math.PI * 2;
        const rr = 78 + rand() * 40;
        pts.push([
          x + w / 2 + Math.cos(a) * rr * 0.95,
          y + 145 + Math.sin(a) * rr * 0.85,
        ]);
      }
      pts[n] = pts[0];
      const draw = ease.inOutCubic(beat(t, 0.8, 2.2));
      const path = smooth(pts, 24);
      const upto = Math.max(2, Math.floor(path.length * draw));
      g.lineWidth = 7;
      g.lineCap = "round";
      g.lineJoin = "round";
      g.strokeStyle = brandGradient(g, x, x + w);
      g.beginPath();
      path
        .slice(0, upto)
        .forEach(([px, py], i) => (i ? g.lineTo(px, py) : g.moveTo(px, py)));
      g.stroke();
      // Once drawn, the runner keeps lapping it.
      const lap =
        draw < 1
          ? upto - 1
          : Math.floor(((t - 3) / 2.4) * path.length) % path.length;
      const [dx, dy] = path[Math.min(path.length - 1, lap)];
      radialGlow(g, dx, dy, 26, 0.7, "255,77,125");
      g.fillStyle = "#fff";
      g.beginPath();
      g.arc(dx, dy, 7, 0, Math.PI * 2);
      g.fill();
      g.restore();

      // The lock line under the "photo".
      const lockIn = ease.outBack(beat(t, 1.3, 0.5));
      around(
        g,
        x + 40,
        y + h - 40,
        { scale: lockIn, alpha: clamp01(lockIn * 2) },
        () => {
          lock(g, x + 24, y + h - 58, 30);
          g.font = font.body(24, 700);
          g.fillStyle = BRAND.ink;
          g.fillText("Friends only", x + 66, y + h - 33);
        },
      );
    },
  );
}

/** Lifts type off a banner photo (the name and handle overlap it). */
function textShadow(g: Ctx) {
  g.shadowColor = "rgba(0,0,0,0.55)";
  g.shadowBlur = 14;
  g.shadowOffsetY = 2;
}

/** Catmull-Rom through the points (closed loop), `per` steps a segment. */
function smooth(pts: [number, number][], per: number): [number, number][] {
  const out: [number, number][] = [];
  const m = pts.length - 1;
  const at = (i: number) => pts[((i % m) + m) % m];
  for (let i = 0; i < m; i++) {
    const [p0, p1, p2, p3] = [at(i - 1), at(i), at(i + 1), at(i + 2)];
    for (let s = 0; s < per; s++) {
      const u = s / per;
      const u2 = u * u;
      const u3 = u2 * u;
      const f = (a: number, b: number, c: number, d: number) =>
        0.5 *
        (2 * b +
          (-a + c) * u +
          (2 * a - 5 * b + 4 * c - d) * u2 +
          (-a + 3 * b - 3 * c + d) * u3);
      out.push([f(p0[0], p1[0], p2[0], p3[0]), f(p0[1], p1[1], p2[1], p3[1])]);
    }
  }
  out.push(out[0]);
  return out;
}

function lock(g: Ctx, x: number, y: number, s: number) {
  g.strokeStyle = BRAND.pink;
  g.lineWidth = s * 0.12;
  g.beginPath();
  g.arc(x + s / 2, y + s * 0.42, s * 0.24, Math.PI, 0);
  g.lineTo(x + s * 0.74, y + s * 0.5);
  g.moveTo(x + s * 0.26, y + s * 0.42);
  g.lineTo(x + s * 0.26, y + s * 0.5);
  g.stroke();
  roundRect(g, x + s * 0.12, y + s * 0.48, s * 0.76, s * 0.5, s * 0.1);
  g.fillStyle = BRAND.pink;
  g.fill();
}
