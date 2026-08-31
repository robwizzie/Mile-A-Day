"use client";

import { useEffect, useState } from "react";
import {
  BarList,
  Card,
  fmt,
  getData,
  HEAT_HUE,
  Loading,
  MAD_RED,
  MAD_SUCCESS,
  MAD_WARNING,
  pct,
  Section,
  SegmentedControl,
  STACK_SECTIONS,
  StatCard,
  WALK_BLUE,
  workoutColor,
} from "./lib";
import { HeatGrid, TimeSeriesBars } from "./charts";
import { useDrilldown, useOpenUser } from "./Drilldown";

type Overview = {
  total_users: number;
  total_miles: number;
  miles_today: number;
  active_users_7d: number;
  total_hypes: number;
  hypes_today: number;
  total_nudges: number;
  nudges_today: number;
};

type Engagement = {
  dau: number;
  wau: number;
  mau: number;
  new_today: number;
  new_7d: number;
  new_30d: number;
};

type Leaderboards = {
  top_streaks: {
    user_id: string;
    username: string | null;
    current_streak: number;
  }[];
  top_milers: {
    user_id: string;
    username: string | null;
    total_miles: number;
  }[];
};

type Pulse = {
  posts_today: number;
  photos_today: number;
  comments_today: number;
  competitions_live: number;
  buddy_sessions_today: number;
  tokens_spent_today: number;
  challenges_completed_today: number;
  badges_today: number;
  friends_today: number;
  tracking_now: number;
};

type Rhythms = {
  clock: { dow: number; hour: number; count: number }[];
  by_hour: { hour: number; count: number }[];
  by_weekday: { dow: number; count: number; miles: number }[];
  streak_buckets: { label: string; users: number }[];
  window_days: number;
};

type Trends = { days: string[]; metrics: Trend[] };

type Trend = {
  key: string;
  label: string;
  current: number;
  previous: number;
  change_pct: number | null;
  spark: number[];
  distinct: boolean;
};

type AtRisk = {
  user_id: string;
  username: string | null;
  current_streak: number;
  miles_today: number;
  goal_miles: number;
  hours_left: number;
  local_date: string;
};

type Activation = {
  total_users: number;
  steps: {
    key: string;
    label: string;
    hint: string;
    users: number;
    pct: number;
  }[];
};

type WorkoutType = { type: string; count: number; miles: number };
const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
// Only every third hour is labelled — 24 legible labels do not fit, and a
// crowded axis is worse than a sparse one.
const HOUR_LABELS = Array.from({ length: 24 }, (_, h) =>
  h === 0 ? "12a" : h < 12 ? `${h}a` : h === 12 ? "12p" : `${h - 12}p`,
);

const nameOf = (u: { username: string | null; user_id: string }) =>
  u.username ? `@${u.username}` : u.user_id.slice(0, 8);

export function OverviewTab() {
  const open = useDrilldown();
  const openUser = useOpenUser();
  const [overview, setOverview] = useState<Overview | null>(null);
  const [engagement, setEngagement] = useState<Engagement | null>(null);
  const [boards, setBoards] = useState<Leaderboards | null>(null);
  const [types, setTypes] = useState<WorkoutType[]>([]);
  const [pulse, setPulse] = useState<Pulse | null>(null);
  const [rhythms, setRhythms] = useState<Rhythms | null>(null);
  const [trends, setTrends] = useState<Trends | null>(null);
  const [atRisk, setAtRisk] = useState<AtRisk[]>([]);
  const [activation, setActivation] = useState<Activation | null>(null);
  const [metric, setMetric] = useState("miles");
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    Promise.all([
      getData<Overview>("overview"),
      getData<Engagement>("engagement"),
      getData<Leaderboards>("leaderboards"),
      getData<WorkoutType[]>("workout-types"),
      getData<Pulse>("pulse"),
      getData<Rhythms>("activity-rhythms"),
      getData<Trends | Trend[]>("trends"),
      getData<AtRisk[]>("at-risk"),
      getData<Activation>("activation"),
    ])
      .then(([o, e, b, t, p, r, tr, ar, act]) => {
        setOverview(o);
        setEngagement(e);
        setBoards(b);
        setTypes(t);
        setPulse(p);
        setRhythms(r);
        // The website (Vercel) and the API (Coolify) deploy independently, so
        // a new page can meet an API that still returns the bare array this
        // endpoint used to. Normalise rather than throw: the axis falls back
        // to indices and every panel still renders.
        setTrends(Array.isArray(tr) ? { days: [], metrics: tr } : tr);
        setAtRisk(ar);
        setActivation(act);
      })
      .catch((e) => {
        if (e?.message !== "unauthorized") setErr("Failed to load overview.");
      });
  }, []);

  if (err) return <p className="text-sm text-[#d94059]">{err}</p>;
  if (!overview || !engagement) return <Loading />;

  const trend = (key: string) => trends?.metrics.find((t) => t.key === key);
  const milesTrend = trend("miles");
  const activeTrend = trend("active_users");
  const signupTrend = trend("new_users");
  const photoTrend = trend("photos");

  return (
    <div className={STACK_SECTIONS}>
      {/* Anything wrong RIGHT NOW sits above anything historical: a 200-day
          streak that ends tonight cannot wait for someone to scroll. */}
      {atRisk.length > 0 && (
        <button
          onClick={() => open({ kind: "at_risk" })}
          className="group flex w-full items-center gap-4 rounded-2xl border border-[#ff9900]/25 bg-[#ff9900]/[0.07] p-4 text-left transition hover:border-[#ff9900]/50 hover:bg-[#ff9900]/[0.12]"
        >
          <span className="text-2xl leading-none">🔥</span>
          <span className="min-w-0 flex-1">
            <span className="block text-sm font-bold text-white">
              {atRisk.length} streak{atRisk.length === 1 ? "" : "s"} at risk today
            </span>
            <span className="block truncate text-xs text-white/50">
              Longest is {atRisk[0].current_streak} days
              {atRisk[0].username ? ` (@${atRisk[0].username})` : ""} ·{" "}
              {atRisk[0].hours_left}h left in their own day
            </span>
          </span>
          <span className="shrink-0 text-white/25 transition group-hover:text-[#ff9900]">
            ›
          </span>
        </button>
      )}

      <Section
        title="Right now"
        hint="Today is the ET calendar day, the boundary every daily counter in the app uses. Percentages compare the last 30 days with the 30 before."
      >
        <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
          {/* Each card's number and its percentage are the SAME quantity over
              the SAME window. Pairing a "today" number with a 30-day delta —
              or, worse, hanging a signups delta off a total-users count —
              reads as precision and means nothing. Today is the strip below. */}
          <StatCard
            label="Active people · 30d"
            value={fmt(activeTrend?.current ?? engagement.mau)}
            sub={`${fmt(engagement.dau)} today · ${fmt(engagement.wau)} this week`}
            accent
            changePct={activeTrend?.change_pct}
            previous={activeTrend?.previous}
            current={activeTrend?.current}
            spark={activeTrend?.spark}
          />
          <StatCard
            label="Miles · 30d"
            value={fmt(Math.round(milesTrend?.current ?? 0))}
            sub={`${overview.miles_today.toFixed(1)} today · ${fmt(Math.round(overview.total_miles))} all time`}
            changePct={milesTrend?.change_pct}
            previous={milesTrend?.previous}
            current={milesTrend?.current}
            spark={milesTrend?.spark}
          />
          <StatCard
            label="New signups · 30d"
            value={fmt(signupTrend?.current ?? engagement.new_30d)}
            sub={`${fmt(overview.total_users)} users in total`}
            changePct={signupTrend?.change_pct}
            previous={signupTrend?.previous}
            current={signupTrend?.current}
            spark={signupTrend?.spark}
          />
          <StatCard
            label="Photos · 30d"
            value={fmt(photoTrend?.current ?? 0)}
            sub={`${fmt(pulse?.photos_today ?? 0)} today`}
            changePct={photoTrend?.change_pct}
            previous={photoTrend?.previous}
            current={photoTrend?.current}
            spark={photoTrend?.spark}
          />
        </div>

        {pulse && (
          <Card>
            <div className="grid grid-cols-3 gap-x-6 gap-y-5 sm:grid-cols-5">
              {(
                [
                  {
                    label: "Out running now",
                    value: pulse.tracking_now,
                    accent: true,
                    kind: "live_tracking",
                  },
                  { label: "Photos posted", value: pulse.photos_today },
                  { label: "Comments", value: pulse.comments_today },
                  { label: "Competitions live", value: pulse.competitions_live },
                  {
                    label: "Buddy walks started",
                    value: pulse.buddy_sessions_today,
                  },
                  {
                    label: "Streak tokens spent",
                    value: pulse.tokens_spent_today,
                  },
                  {
                    label: "Challenges completed",
                    value: pulse.challenges_completed_today,
                  },
                  { label: "Badges earned", value: pulse.badges_today },
                  { label: "New friendships", value: pulse.friends_today },
                  { label: "Hypes", value: overview.hypes_today },
                ] as {
                  label: string;
                  value: number;
                  accent?: boolean;
                  kind?: string;
                }[]
              ).map((it) => {
                const body = (
                  <>
                    <div
                      className={`mad-num text-[22px] leading-none font-extrabold ${
                        it.accent ? "text-[#ff8fa3]" : "text-white"
                      }`}
                    >
                      {fmt(it.value)}
                    </div>
                    <div className="mt-1 text-[11px] leading-tight text-white/40">
                      {it.label}
                    </div>
                  </>
                );
                // Only the counters with rows behind them are pressable —
                // making the whole strip look clickable when most of it is
                // not is worse than a strip that plainly is not.
                return it.kind ? (
                  <button
                    key={it.label}
                    onClick={() => open({ kind: it.kind! })}
                    className="-mx-2 rounded-lg px-2 py-1 text-left transition hover:bg-white/[0.05]"
                  >
                    {body}
                  </button>
                ) : (
                  <div key={it.label}>{body}</div>
                );
              })}
            </div>
          </Card>
        )}
      </Section>

      {activation && (
        <Section
          title="How far people get"
          hint="Milestones, not a funnel — somebody can post a photo without ever adding a friend, so these are independent counts rather than conversions. The first big drop is where the product loses people."
        >
          <Card>
            <ul className="space-y-3.5">
              {activation.steps.map((st) => {
                return (
                  <li key={st.key}>
                    <button
                      onClick={() =>
                        open({ kind: "activation_step", id: st.key })
                      }
                      className="-mx-2 block w-[calc(100%+1rem)] rounded-lg px-2 py-1 text-left transition hover:bg-white/[0.05]"
                    >
                      <div className="mb-1.5 flex items-baseline justify-between gap-3">
                        <span className="min-w-0 text-sm text-white/85">
                          {st.label}
                          <span className="ml-2 text-xs text-white/30">
                            {st.hint}
                          </span>
                        </span>
                        <span className="shrink-0 text-sm tabular-nums text-white/45">
                          <span className="font-semibold text-white/95">
                            {fmt(st.users)}
                          </span>{" "}
                          · {st.pct}%
                        </span>
                      </div>
                      <div className="h-2.5 overflow-hidden rounded-full bg-white/[0.06]">
                        <div
                          className="h-full rounded-full transition-[width] duration-300"
                          style={{ width: `${st.pct}%`, background: MAD_RED }}
                        />
                      </div>
                    </button>
                  </li>
                );
              })}
            </ul>
          </Card>
        </Section>
      )}


      {trends && trends.metrics.length > 0 && (
        <Section
          title="Trends"
          hint="Daily, over the last 30 days. The cards above show the same series as a shape; this is the detail behind whichever one you pick."
          actions={
            <SegmentedControl
              value={metric}
              onChange={setMetric}
              options={trends.metrics.map((m) => ({
                value: m.key,
                label: m.label,
              }))}
            />
          }
        >
          <Card>
            <TimeSeriesBars
              data={(
                trends.metrics.find((m) => m.key === metric) ??
                trends.metrics[0]
              ).spark.map((v, i) => ({
                date: trends.days[i] ?? String(i),
                value: v,
              }))}
              label={
                (
                  trends.metrics.find((m) => m.key === metric) ??
                  trends.metrics[0]
                ).label
              }
              formatValue={(v) =>
                metric === "miles" ? v.toFixed(1) : v.toFixed(0)
              }
              unit={metric === "miles" ? " mi" : ""}
            />
            {(trends.metrics.find((m) => m.key === metric)?.distinct ??
              false) && (
              <p className="mt-2 text-xs text-white/35">
                This counts distinct people per day, so the bars do not add up
                to the 30-day total — somebody active on ten days is one
                person, not ten.
              </p>
            )}
          </Card>
        </Section>
      )}

      <Section
        title="Who is out in front"
        hint="Tap a name to open that person."
      >
      <div className="grid gap-5 lg:grid-cols-3">
        <Card title="🔥 Longest active streaks">
          <BarList
            items={(boards?.top_streaks ?? []).map((u) => ({
              label: nameOf(u),
              value: u.current_streak,
              onClick: () => openUser(u.user_id),
            }))}
            color={MAD_WARNING}
            formatValue={(v) => `${v} days`}
          />
        </Card>
        <Card title="🏃 Most miles all-time">
          <BarList
            items={(boards?.top_milers ?? []).map((u) => ({
              label: nameOf(u),
              value: Math.round(u.total_miles),
              onClick: () => openUser(u.user_id),
            }))}
            color={MAD_SUCCESS}
            formatValue={(v) => `${fmt(v)} mi`}
          />
        </Card>
        <Card
          title="Workout mix"
          hint="Counting workouts only. Colours are the app's own: runs red, walks blue."
        >
          <BarList
            items={types.map((t) => ({
              label: t.type,
              value: t.count,
              sub: `${fmt(Math.round(t.miles))} mi`,
              // MADTheme.workoutColor — the same red/blue the feed, dashboard
              // and route heatmap use, so a walk never changes colour between
              // the app and here.
              color: workoutColor(t.type),
              onClick: () => open({ kind: "workout_type", id: t.type }),
            }))}
            formatValue={(v) => `${fmt(v)}`}
          />
        </Card>
      </div>
      </Section>

      {rhythms && (
        <Section
          title="Rhythms"
          hint="When the miles happen, and how deep the habit goes."
        >
        <div className="grid gap-5 lg:grid-cols-3">
          <Card
            className="lg:col-span-2"
            title="When people finish their mile"
            hint={`Last ${rhythms.window_days} days, in each runner's own local time — not ours.`}
          >
            <HeatGrid
              hue={HEAT_HUE}
              rows={WEEKDAYS.map((label, i) => ({ key: String(i), label }))}
              cols={Array.from({ length: 24 }, (_, h) => ({
                key: String(h),
                label: h % 3 === 0 ? HOUR_LABELS[h] : "",
              }))}
              colLabel={(_, i) => i % 3 === 0}
              value={(dow, hour) =>
                rhythms.clock.find(
                  (c) => c.dow === Number(dow) && c.hour === Number(hour),
                )?.count ?? 0
              }
              title={(day, hour, v) =>
                `${day} ${hour || ""}: ${v} workout${v === 1 ? "" : "s"}`
              }
              formatValue={(v) => `${fmt(v)}/hr`}
              legend="Workouts finished per weekday hour"
              cell={28}
            />
          </Card>

          <Card
            title="How deep the streaks go"
            hint="Every user by current streak. A fat left side and a thin tail is people starting streaks and losing them."
          >
            <BarList
              items={rhythms.streak_buckets.map((b) => ({
                label: b.label === "0" ? "No streak" : `${b.label} days`,
                value: b.users,
                sub: `${pct(b.users, rhythms.streak_buckets.reduce((a, x) => a + x.users, 0))}%`,
                onClick:
                  b.users > 0
                    ? () => open({ kind: "streak_bucket", id: b.label })
                    : undefined,
              }))}
              color={MAD_RED}
              formatValue={(v) => `${fmt(v)}`}
            />
          </Card>
        </div>
        </Section>
      )}
    </div>
  );
}
