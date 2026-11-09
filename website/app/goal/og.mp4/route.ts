import { factsKey, ogVideoResponse } from "../../_og/video/serve";
import { goalScene } from "../../_og/video/scenes/goal";
import { loadGoal, statusLine } from "../goalData";

// /goal's og:video. Keyed by what it draws, with the total rounded to tens so
// a busy day doesn't mean a fresh render every ten minutes.
export const dynamic = "force-dynamic";
export const maxDuration = 60;

export async function GET(req: Request) {
  const goal = await loadGoal();
  const key = goal
    ? factsKey("goal", [
        goal.title,
        goal.state,
        statusLine(goal),
        goal.target_miles,
        Math.floor(goal.total_miles / 10),
        goal.walkers,
        goal.percent,
      ])
    : "goal/none";
  return ogVideoResponse(req, { key, ttl: 3600, scene: () => goalScene(goal) });
}

export { GET as HEAD };
