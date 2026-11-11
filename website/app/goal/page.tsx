import type { Metadata } from "next";
import { Navbar } from "@/components/navbar";
import { Footer } from "@/components/footer";
import { APP_STORE_URL } from "@/lib/site";
import { ogVideos } from "../_og/video/meta";
import { GoalRewards } from "./GoalRewards";
import { loadGoal, statusLine, type PublicGoal } from "./goalData";

const title = "Community Goal";
const description = "See how far the Mile A Day community has walked together, and join in.";

export const metadata: Metadata = {
  title,
  description,
  alternates: { canonical: "/goal" },
  openGraph: {
    title: `${title} | Mile A Day`,
    description,
    url: "/goal",
    type: "website",
    siteName: "Mile A Day",
    videos: ogVideos("/goal/og.mp4"),
  },
};

/** Usernames are letters, numbers and underscores; anything else is ignored. */
function referrerFrom(value: string | string[] | undefined): string | null {
  return typeof value === "string" && /^[A-Za-z0-9_]{3,20}$/.test(value) ? value : null;
}

/** Will we get there, and what would change it. Empty until there's a rate to read. */
function paceLine(goal: PublicGoal): string | null {
  const projected = goal.pace?.projected_miles;
  if (goal.state !== "active" || goal.percent >= 100 || projected == null) return null;
  if (projected >= goal.target_miles) {
    const finish = goal.pace?.projected_finish;
    if (!finish) return "On pace to finish. Every new walker gets us there sooner.";
    const day = new Date(`${finish}T00:00:00Z`).toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: "UTC" });
    return `On pace to finish by ${day}. Every new walker gets us there sooner.`;
  }
  const needed = goal.pace?.walkers_needed;
  const short = `At this pace we'd reach ${projected.toLocaleString("en-US")} mi.`;
  if (!needed) return short;
  return `${short} ${needed.toLocaleString("en-US")} more ${needed === 1 ? "walker gets" : "walkers get"} us there.`;
}

/** Under this, a live count reads as an empty room, so it waits. */
const WALKING_TODAY_MIN = 3;

function walkingToday(goal: PublicGoal): string | null {
  const n = goal.walkers_today;
  if (goal.state !== "active" || n == null || n < WALKING_TODAY_MIN) return null;
  return `${n.toLocaleString("en-US")} walked today`;
}

export default async function GoalPage({
  searchParams,
}: {
  searchParams: Promise<{ ref?: string | string[] }>;
}) {
  const [goal, params] = await Promise.all([loadGoal(), searchParams]);
  const referrer = referrerFrom(params.ref);

  return (
    <div className="min-h-screen bg-[#0e0809] text-white">
      <Navbar />
      <main className="mx-auto flex max-w-2xl flex-col gap-6 px-5 pb-20 pt-32">
        <p className="text-[13px] font-semibold uppercase tracking-[0.18em] text-[#ff5a6e]">
          Community goal
        </p>

        {goal ? (
          <>
            <div className="flex flex-col gap-2">
              <p className="text-sm font-semibold text-[#ff4d7d]">{statusLine(goal)}</p>
              <h1 className="font-heading text-[clamp(40px,7vw,64px)] leading-[0.95]">{goal.title}</h1>
              <p className="text-lg text-[#a0a0a0]">{goal.description}</p>
            </div>

            <section className="flex flex-col gap-3 rounded-3xl bg-white/[0.045] p-6 sm:p-7">
              <p className="font-heading text-[48px] leading-none">
                {Math.floor(goal.total_miles).toLocaleString("en-US")} mi
              </p>
              <p className="text-sm text-[#a0a0a0]">
                of {goal.target_miles.toLocaleString("en-US")} mi, walked by{" "}
                {goal.walkers.toLocaleString("en-US")} {goal.walkers === 1 ? "walker" : "walkers"}
              </p>
              <div
                className="relative h-3.5 overflow-hidden rounded-full bg-white/10"
                role="img"
                aria-label={`${goal.percent}% of the way`}
              >
                <div className="h-full rounded-full bg-[#ec3047]" style={{ width: `${goal.percent}%` }} />
              </div>
              {walkingToday(goal) && (
                <p className="flex items-center gap-2 text-sm font-semibold text-white/75">
                  <span className="relative flex h-2.5 w-2.5">
                    <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-green-400 opacity-60 motion-reduce:animate-none" />
                    <span className="relative inline-flex h-2.5 w-2.5 rounded-full bg-green-500" />
                  </span>
                  {walkingToday(goal)}
                </p>
              )}
              {paceLine(goal) && <p className="text-base font-bold text-[#ffb547]">{paceLine(goal)}</p>}
              <ul className="mt-2 flex flex-col gap-2">
                {goal.checkpoints.map((c) => (
                  <li key={c.percent} className="flex items-center justify-between text-sm">
                    <span className={c.reached ? "font-semibold text-white" : "text-[#a0a0a0]"}>
                      {c.reached ? "✓ " : ""}
                      {c.name}
                    </span>
                    <span className="text-[#a0a0a0]">{c.percent}%</span>
                  </li>
                ))}
              </ul>
            </section>

            <section className="flex flex-col gap-4 rounded-3xl bg-white/[0.045] p-6 sm:p-7">
              <div>
                <h2 className="font-heading text-[26px]">Rewards you can unlock.</h2>
                <p className="text-sm text-[#a0a0a0]">Limited to this goal. Earn them even if we miss the target.</p>
              </div>
              <GoalRewards rewards={goal.rewards ?? []} />
            </section>
          </>
        ) : (
          <div className="flex flex-col gap-2">
            <h1 className="font-heading text-[clamp(40px,7vw,64px)] leading-[0.95]">The next goal is on its way.</h1>
            <p className="text-lg text-[#a0a0a0]">
              Community goals bring everyone&rsquo;s miles together. Download the app so you&rsquo;re ready.
            </p>
          </div>
        )}

        <div className="flex flex-col gap-2">
          <a
            href={APP_STORE_URL} data-track="app_store:goal"
            className="lift rounded-full bg-[#ec3047] px-6 py-4 text-center text-lg font-bold text-white hover:bg-[#d6243a]"
          >
            Join on the App Store
          </a>
          {referrer && (
            <p className="text-center text-sm text-[#a0a0a0]">
              When you sign up, choose &ldquo;Friend or family&rdquo; and pick @{referrer}.
            </p>
          )}
        </div>
      </main>
      <Footer />
    </div>
  );
}
