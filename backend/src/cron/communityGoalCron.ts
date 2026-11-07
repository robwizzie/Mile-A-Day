import cron from "node-cron";
import { PostgresService } from "../services/DbService.js";
import { runJob } from "./cronRunner.js";
import { sendPush } from "../services/pushNotificationService.js";
import { shouldSendNotification } from "../services/notificationSettingsService.js";
import { CLIENT_FEATURES, supportsClientFeatureSql, userSupports } from "../services/clientFeatures.js";
import { userOffsetMinutesOrNullSql } from "../services/dailyResetTime.js";
import {
  claimPush,
  goalsDueForRewards,
  goalsToRefresh,
  grantRewards,
  refreshTotals,
} from "../services/communityGoalService.js";

const db = PostgresService.getInstance();

/** Local hour the start and final-week pushes go out. */
const PUSH_HOUR = 10;

interface PushCopy {
  kind: "start" | "final_week";
  /** Days from `starts_on` or to `ends_on`, read by `dueGoalSql`. */
  day: string;
  title: (goal: string) => string;
  body: string;
}

const PUSHES: PushCopy[] = [
  {
    kind: "start",
    day: "g.starts_on",
    title: (goal) => `${goal} starts today`,
    body: "Every mile you walk this month moves all of us forward.",
  },
  {
    kind: "final_week",
    day: "g.ends_on - 6",
    title: (goal) => `${goal}: final week`,
    body: "One week left. Every walk counts, and every friend you invite helps us finish.",
  },
];

/** People whose local clock has reached the push hour on the goal's day. */
async function dueUsers(day: string): Promise<Array<{ user_id: string; goal_id: string; title: string }>> {
  return db.query(
    `WITH user_tz AS (
       SELECT u.user_id, ${userOffsetMinutesOrNullSql("u.user_id")} AS tz_offset FROM users u
     )
     SELECT t.user_id, g.goal_id, g.title
       FROM user_tz t
       JOIN community_goals g
         ON (NOW() + (t.tz_offset || ' minutes')::interval)::date = ${day}
      WHERE t.tz_offset IS NOT NULL
        AND EXTRACT(HOUR FROM (NOW() + (t.tz_offset || ' minutes')::interval)) = ${PUSH_HOUR}
        AND ${supportsClientFeatureSql("t.user_id", CLIENT_FEATURES.communityGoalV1)}
      LIMIT 5000`,
  );
}

async function pushIfAllowed(
  userId: string,
  goalId: string,
  kind: "start" | "final_week" | "result",
  title: string,
  body: string,
): Promise<void> {
  // A brand-new type: an older build would show it and open nothing.
  if (!(await userSupports(userId, CLIENT_FEATURES.communityGoalV1))) return;
  if (!(await shouldSendNotification(userId, null, "weekly_challenge"))) return;
  if (!(await claimPush(goalId, userId, kind))) return;
  const type = `community_goal_${kind}` as const;
  await sendPush(userId, { title, body, type, data: { type, goal_id: goalId } });
}

export async function sendCommunityGoalPushes(): Promise<void> {
  for (const push of PUSHES) {
    for (const user of await dueUsers(push.day)) {
      await pushIfAllowed(user.user_id, user.goal_id, push.kind, push.title(user.title), push.body);
    }
  }
}

export async function refreshCommunityGoalTotals(): Promise<void> {
  for (const goal of await goalsToRefresh()) await refreshTotals(goal);
}

/** Final total first, then rewards, then one result push to everyone who walked. */
export async function finishCommunityGoals(): Promise<void> {
  for (const goal of await goalsDueForRewards()) {
    await refreshTotals(goal);
    const { walkers, reached } = await grantRewards(goal);
    const title = reached ? `We made it: ${goal.title}` : `${goal.title} is over`;
    const tiers = [...goal.reward_tiers].sort((a, b) => b.days - a.days);
    for (const walker of walkers) {
      const best = tiers.find((t) => walker.days >= t.days);
      const body = best
        ? `You earned the ${best.name}. Thanks for walking with us.`
        : "Thanks for walking with us. See how far we got.";
      try {
        await pushIfAllowed(walker.user_id, goal.goal_id, "result", title, body);
      } catch (error: any) {
        console.error(`[community-goals] Result push failed for ${walker.user_id}:`, error?.message ?? error);
      }
    }
  }
}

export function startCommunityGoalCron(): void {
  cron.schedule("*/10 * * * *", () => {
    void runJob("community-goal-totals", refreshCommunityGoalTotals);
  });
  cron.schedule("5 * * * *", async () => {
    await runJob("community-goal-pushes", sendCommunityGoalPushes);
    await runJob("community-goal-finish", finishCommunityGoals);
  });
}
