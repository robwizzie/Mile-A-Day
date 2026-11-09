// The public community goal, shared by /goal and its og.mp4 so both show the
// same numbers. Only totals: GET /public/community-goal carries no person.

const API_URL = process.env.NEXT_PUBLIC_API_URL || "https://mad.mindgoblin.tech";

export type PublicGoal = {
  title: string;
  description: string;
  target_miles: number;
  starts_on: string;
  days_left: number;
  state: string;
  total_miles: number;
  walkers: number;
  /** Optional: null outside an active goal, and absent from older APIs. */
  walkers_today?: number | null;
  percent: number;
  checkpoints: Array<{ percent: number; name: string; reached: boolean }>;
  pace?: {
    projected_miles: number | null;
    projected_finish: string | null;
    walkers_needed: number | null;
  } | null;
  /** Optional: the site can deploy before the API that adds it. */
  rewards?: Array<{ days: number; name: string; item_id: string | null; rarity?: string }>;
};

/** Totals change every 10 minutes, so a minute of caching loses nothing. */
export async function loadGoal(): Promise<PublicGoal | null> {
  try {
    const res = await fetch(`${API_URL}/public/community-goal`, { next: { revalidate: 60 } });
    if (!res.ok) return null;
    return (await res.json()).goal ?? null;
  } catch {
    return null;
  }
}

export function statusLine(goal: PublicGoal): string {
  const start = new Date(`${goal.starts_on}T12:00:00Z`).toLocaleDateString("en-US", {
    month: "long",
    day: "numeric",
    timeZone: "UTC",
  });
  if (goal.state === "upcoming") return `Starts ${start}`;
  if (goal.state === "active") return goal.days_left === 1 ? "Last day" : `${goal.days_left} days left`;
  if (goal.state === "counting") return "Final count in progress";
  return goal.percent >= 100 ? "We made it" : `We walked ${goal.percent}% of the way`;
}
