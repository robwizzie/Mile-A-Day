"use client";

import { useEffect, useState } from "react";
import {
  BarList,
  Card,
  fmt,
  getData,
  HEAT_HUE,
  Loading,
  PALETTE,
  pct,
  StatCard,
} from "./lib";
import { HeatGrid, TimeSeriesBars } from "./charts";

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

type WorkoutType = { type: string; count: number; miles: number };
type DayMiles = { date: string; miles: number };
type DaySignup = { date: string; count: number };

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
// Only every third hour is labelled — 24 legible labels do not fit, and a
// crowded axis is worse than a sparse one.
const HOUR_LABELS = Array.from({ length: 24 }, (_, h) =>
  h === 0 ? "12a" : h < 12 ? `${h}a` : h === 12 ? "12p" : `${h - 12}p`,
);

const nameOf = (u: { username: string | null; user_id: string }) =>
  u.username ? `@${u.username}` : u.user_id.slice(0, 8);

export function OverviewTab() {
  const [overview, setOverview] = useState<Overview | null>(null);
  const [engagement, setEngagement] = useState<Engagement | null>(null);
  const [miles, setMiles] = useState<DayMiles[]>([]);
  const [signups, setSignups] = useState<DaySignup[]>([]);
  const [boards, setBoards] = useState<Leaderboards | null>(null);
  const [types, setTypes] = useState<WorkoutType[]>([]);
  const [pulse, setPulse] = useState<Pulse | null>(null);
  const [rhythms, setRhythms] = useState<Rhythms | null>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    Promise.all([
      getData<Overview>("overview"),
      getData<Engagement>("engagement"),
      getData<DayMiles[]>("miles-by-day"),
      getData<DaySignup[]>("signups-by-day"),
      getData<Leaderboards>("leaderboards"),
      getData<WorkoutType[]>("workout-types"),
      getData<Pulse>("pulse"),
      getData<Rhythms>("activity-rhythms"),
    ])
      .then(([o, e, m, s, b, t, p, r]) => {
        setOverview(o);
        setEngagement(e);
        setMiles(m);
        setSignups(s);
        setBoards(b);
        setTypes(t);
        setPulse(p);
        setRhythms(r);
      })
      .catch((e) => {
        if (e?.message !== "unauthorized") setErr("Failed to load overview.");
      });
  }, []);

  if (err) return <p className="text-sm text-[#c72554]">{err}</p>;
  if (!overview || !engagement) return <Loading />;

  return (
    <div className="space-y-6">
      {/* Headline counters */}
      <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
        <StatCard
          label="Total users"
          value={fmt(overview.total_users)}
          sub={`${engagement.new_today} new today`}
        />
        <StatCard
          label="Active today"
          value={fmt(engagement.dau)}
          sub={`${fmt(engagement.wau)} this week`}
          accent
        />
        <StatCard
          label="Total miles"
          value={fmt(Math.round(overview.total_miles))}
          sub={`${overview.miles_today.toFixed(1)} today`}
        />
        <StatCard
          label="Active (7d)"
          value={fmt(overview.active_users_7d)}
          sub={`${fmt(engagement.mau)} in 30d`}
        />
        <StatCard
          label="Hypes"
          value={fmt(overview.total_hypes)}
          sub={`${overview.hypes_today} today`}
        />
        <StatCard
          label="Nudges"
          value={fmt(overview.total_nudges)}
          sub={`${overview.nudges_today} today`}
        />
        <StatCard
          label="New (7d)"
          value={fmt(engagement.new_7d)}
          sub={`${fmt(engagement.new_30d)} in 30d`}
        />
        <StatCard
          label="Miles today"
          value={overview.miles_today.toFixed(1)}
          sub={`avg ${(overview.total_miles / Math.max(overview.total_users, 1)).toFixed(0)} / user`}
        />
      </div>

      {/* Today, across every feature — one line to answer "is the app alive". */}
      {pulse && (
        <Card
          title="Today"
          hint="Since midnight ET, the same boundary every daily counter in the app uses."
        >
          <div className="grid grid-cols-3 gap-x-6 gap-y-4 sm:grid-cols-5 lg:grid-cols-9">
            {[
              ["Out running now", pulse.tracking_now, true],
              ["Photos posted", pulse.photos_today],
              ["Comments", pulse.comments_today],
              ["Competitions live", pulse.competitions_live],
              ["Buddy walks started", pulse.buddy_sessions_today],
              ["Streak tokens spent", pulse.tokens_spent_today],
              ["Challenges completed", pulse.challenges_completed_today],
              ["Badges earned", pulse.badges_today],
              ["New friendships", pulse.friends_today],
            ].map(([label, value, accent]) => (
              <div key={label as string}>
                <div
                  className={`text-2xl font-semibold tabular-nums ${
                    accent ? "text-[#ffb3c6]" : "text-white"
                  }`}
                >
                  {fmt(value as number)}
                </div>
                <div className="text-xs text-white/40">{label as string}</div>
              </div>
            ))}
          </div>
        </Card>
      )}

      {/* Trends */}
      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <TimeSeriesBars
            data={miles.map((d) => ({ date: d.date, value: d.miles }))}
            label="Miles per day — last 30 days"
            unit=" mi"
          />
        </Card>
        <Card>
          <TimeSeriesBars
            data={signups.map((d) => ({ date: d.date, value: d.count }))}
            label="New signups per day — last 30 days"
            color="#38bdf8"
            hoverColor="#7dd3fc"
            formatValue={(v) => v.toFixed(0)}
          />
        </Card>
      </div>

      {/* Leaderboards + workout mix */}
      <div className="grid gap-6 lg:grid-cols-3">
        <Card title="🔥 Longest active streaks">
          <BarList
            items={(boards?.top_streaks ?? []).map((u) => ({
              label: nameOf(u),
              value: u.current_streak,
            }))}
            color="#fb923c"
            formatValue={(v) => `${v} days`}
          />
        </Card>
        <Card title="🏃 Most miles all-time">
          <BarList
            items={(boards?.top_milers ?? []).map((u) => ({
              label: nameOf(u),
              value: Math.round(u.total_miles),
            }))}
            color="#34d399"
            formatValue={(v) => `${fmt(v)} mi`}
          />
        </Card>
        <Card title="Workout mix" hint="Counting workouts only">
          <BarList
            items={types.map((t) => ({
              label: t.type,
              value: t.count,
              sub: `${fmt(Math.round(t.miles))} mi`,
            }))}
            color={PALETTE[2]}
            formatValue={(v) => `${fmt(v)}`}
          />
        </Card>
      </div>

      {/* When people run, and how deep their streaks go. */}
      {rhythms && (
        <div className="grid gap-6 lg:grid-cols-3">
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
              }))}
              color={PALETTE[6]}
              formatValue={(v) => `${fmt(v)}`}
            />
          </Card>
        </div>
      )}
    </div>
  );
}
