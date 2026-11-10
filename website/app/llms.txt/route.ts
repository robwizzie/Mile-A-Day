import { FAQ } from "@/components/support-section";
import { CURRENT_RELEASE } from "@/lib/releases";
import { APP_STORE_URL, SITE_URL, SUPPORT_EMAIL } from "@/lib/site";

// /llms.txt (llmstxt.org): a plain-markdown summary of what Mile A Day is,
// for AI search and assistants. Built from the same sources as the home page
// (FAQ, current release, App Store link) so it can't drift from the site.
export const dynamic = "force-static";

export function GET() {
  const body = `# Mile A Day

> Mile A Day is a free iPhone and Apple Watch app for walking or running at least one mile every day. It tracks your daily streak, syncs walks and runs from Apple Health, and adds friends, competitions, medals and a mascot named Flamey to keep you going. Made by Rob Wiscount and David Simmerman.

- Price: free on iPhone and Apple Watch; Mile A Day+ is an optional upgrade
- Platforms: iOS and watchOS (Android waitlist open)
- Current version: ${CURRENT_RELEASE.version} (${CURRENT_RELEASE.date}): ${CURRENT_RELEASE.summary}
- Download: ${APP_STORE_URL}
- Support: ${SUPPORT_EMAIL}

## What it does

- Daily streak: walk or run one mile a day, any pace, and your streak grows. Streak Tokens (Streak Save, Double Down, Streak Assist) and Recovery Mode protect it when life happens.
- Counts what you already do: any walk or run saved to Apple Health counts, from Apple Watch, a treadmill or another running app. You can also track a mile in the app.
- Friends: a feed of friends' photos and stories that unlocks once you've done your mile, hypes, nudges, buddy walks, and Donate a Mile to save a friend's streak.
- Routes: route maps with a Flyover replay; the start and end of every route are trimmed for privacy, and Stealth Mode records no map at all.
- Competitions: five modes (Streaks, Apex, Targets, Clash, Race), solo or in teams, plus friend leaderboards for miles, pace and streak.
- Medals and milestones: day 100, 365, 500 and more, plus medals for speed and distance.
- Flamey: a flame mascot you name and dress with outfits unlocked by the medals you earn.

## Why one mile

Research from University College London found it takes an average of 66 days for a new behavior to become automatic. One mile is small enough to do every day and a streak makes it hard to skip.

## FAQ

${FAQ.map((item) => `### ${item.q}\n\n${item.a}`).join("\n\n")}

## Pages

- [Home](${SITE_URL}/): what the app does, live community numbers, how to start
- [What's new](${SITE_URL}/updates): every release, newest first
- [Community goal](${SITE_URL}/goal): how far the community has walked together
- [Privacy policy](${SITE_URL}/privacy)
- [Terms of service](${SITE_URL}/terms)
`;
  return new Response(body, {
    headers: { "Content-Type": "text/markdown; charset=utf-8" },
  });
}
