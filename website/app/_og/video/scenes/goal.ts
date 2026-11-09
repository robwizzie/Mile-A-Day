import type { PublicGoal } from "../../../goal/goalData";
import { statusLine } from "../../../goal/goalData";
import { BRAND } from "../../shared";
import { ogAsset, type Scene } from "../render";
import {
  around,
  beat,
  brandGradient,
  clamp01,
  count,
  ease,
  fitSize,
  font,
  foreground,
  ground,
  lerp,
  lockup,
  roundRect,
  storePill,
} from "../kit";

// /goal's video: the one payoff is the community's total counting up while
// the journey bar fills to where we are. The Coast to Coast Collection sits
// beside it as the reason to join. Before the goal starts there's nothing to
// count, so the target lands instead; with no goal, a plain invitation.

const ART_X = 650;
const ART_W = 490;
const ART_H = Math.round((ART_W * 760) / 1280);
const ART_Y = 150;

export async function goalScene(goal: PublicGoal | null): Promise<Scene> {
  const [icon, art] = await Promise.all([ogAsset("icon.png"), ogAsset("goal-collection.jpg")]);
  const live = goal != null && goal.state !== "upcoming";
  const tag = goal ? statusLine(goal).toUpperCase() : "COMMUNITY GOALS";
  const headline = (goal?.title ?? "Walk together").toUpperCase();
  const target = goal?.target_miles ?? 0;
  const total = live ? Math.floor(goal!.total_miles) : 0;
  const fillTo = live ? clamp01(goal!.percent / 100) : 0;

  return (g, t) => {
    ground(g, t);
    foreground(g, t);
    lockup(g, icon, t);

    // Status tag.
    const tagIn = ease.outBack(beat(t, 0.2, 0.5));
    around(g, 72, 175, { scale: lerp(0.85, 1, tagIn), alpha: clamp01(tagIn * 2) }, () => {
      g.font = font.body(22, 700);
      const w = g.measureText(tag).width + 40;
      roundRect(g, 72, 156, w, 42, 21);
      g.fillStyle = "rgba(199,37,84,0.2)";
      g.fill();
      g.fillStyle = BRAND.pink;
      g.textBaseline = "middle";
      g.fillText(tag, 92, 178);
      g.textBaseline = "alphabetic";
    });

    // The goal's name.
    const hIn = ease.outQuint(beat(t, 0.35, 0.7));
    const px = fitSize(g, headline, font.head, 92, 540, 56);
    around(g, 72, 290, { alpha: hIn, dy: (1 - hIn) * 30 }, () => {
      g.font = font.head(px);
      g.fillStyle = brandGradient(g, 72, 600);
      g.fillText(headline, 72, 290);
    });

    // The payoff: the total climbs (or, before the start, the target lands).
    const climb = ease.outCubic(beat(t, 0.9, 2.4));
    const numIn = ease.outCubic(beat(t, 0.8, 0.4));
    around(g, 72, 380, { alpha: numIn }, () => {
      g.font = font.head(84);
      g.fillStyle = BRAND.ink;
      const n = goal ? (live ? count(total * climb) : count(target)) : "EVERY MILE";
      g.fillText(goal ? `${n} MI` : n, 72, 380);
    });
    around(g, 72, 420, { alpha: ease.outCubic(beat(t, 1.1, 0.5)) }, () => {
      g.font = font.body(25);
      g.fillStyle = BRAND.muted;
      const sub = !goal
        ? "counts toward one shared goal"
        : live
          ? `of ${count(target)} mi · ${count(goal.walkers)} ${goal.walkers === 1 ? "walker" : "walkers"}`
          : "together, in one month";
      g.fillText(sub, 72, 420);
    });

    if (live) {
      const barIn = ease.outCubic(beat(t, 0.9, 0.4));
      around(g, 72, 452, { alpha: barIn }, () => {
        roundRect(g, 72, 446, 520, 16, 8);
        g.fillStyle = "rgba(255,255,255,0.1)";
        g.fill();
        const w = 520 * fillTo * climb;
        if (w > 1) {
          roundRect(g, 72, 446, Math.max(16, w), 16, 8);
          g.fillStyle = brandGradient(g, 72, 592);
          g.fill();
        }
      });
    }

    storePill(g, t, 72, 512, undefined, 1.4);

    // The collection, the reason to take part.
    const artIn = ease.outCubic(beat(t, 0.5, 0.8));
    around(g, ART_X + ART_W / 2, ART_Y + ART_H / 2, { alpha: artIn, scale: lerp(0.94, 1, artIn) }, () => {
      g.save();
      roundRect(g, ART_X, ART_Y, ART_W, ART_H, 26);
      g.clip();
      g.drawImage(art, ART_X, ART_Y, ART_W, ART_H);
      g.restore();
      roundRect(g, ART_X, ART_Y, ART_W, ART_H, 26);
      g.lineWidth = 2;
      g.strokeStyle = "rgba(255,255,255,0.12)";
      g.stroke();
    });
    const capIn = ease.outCubic(beat(t, 1.3, 0.6));
    around(g, ART_X, ART_Y + ART_H + 44, { alpha: capIn, dy: (1 - capIn) * 10 }, () => {
      g.font = font.body(24, 700);
      g.fillStyle = BRAND.ink;
      g.textAlign = "center";
      g.fillText("Walk to unlock the limited collection", ART_X + ART_W / 2, ART_Y + ART_H + 44);
      g.textAlign = "left";
    });
  };
}
