// Our story, as data: the day the bet started, and the Instagram posts the
// story page embeds. Add a post by pasting its link (a /p/ or /reel/ URL from
// instagram.com/mileadayapp); the page shows them in this order.

/** The day of the bet (May 13, 2025): day 1 of the founders' streak. */
export const STORY_START = new Date(2025, 4, 13);

/** Whole days since the bet started (the founders' streak). */
export function founderStreakDays(now = new Date()): number {
  return Math.floor((now.getTime() - STORY_START.getTime()) / 86_400_000);
}

/** The month a streak reached `day` (e.g. "August 2025"). */
export function monthOfDay(day: number): string {
  const d = new Date(STORY_START.getTime() + (day - 1) * 86_400_000);
  return d.toLocaleDateString("en-US", { month: "long", year: "numeric" });
}

/** Instagram posts to show on /story, newest or best first. */
export const INSTAGRAM_POSTS: string[] = [
  "https://www.instagram.com/p/Dej6dY-AeX1/",
  "https://www.instagram.com/p/DfVsTIvN_OR/",
];

export const INSTAGRAM_URL = "https://www.instagram.com/mileadayapp";
export const TIKTOK_URL = "https://www.tiktok.com/@mileadayapp";
