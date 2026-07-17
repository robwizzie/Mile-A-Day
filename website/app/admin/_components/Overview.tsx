"use client";

import { useEffect, useState } from "react";
import { BarList, Card, fmt, getData, Loading, PALETTE, StatCard } from "./lib";
import { TimeSeriesBars } from "./charts";

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

type WorkoutType = { type: string; count: number; miles: number };
type DayMiles = { date: string; miles: number };
type DaySignup = { date: string; count: number };

const nameOf = (u: { username: string | null; user_id: string }) =>
  u.username ? `@${u.username}` : u.user_id.slice(0, 8);

export function OverviewTab() {
  const [overview, setOverview] = useState<Overview | null>(null);
  const [engagement, setEngagement] = useState<Engagement | null>(null);
  const [miles, setMiles] = useState<DayMiles[]>([]);
  const [signups, setSignups] = useState<DaySignup[]>([]);
  const [boards, setBoards] = useState<Leaderboards | null>(null);
  const [types, setTypes] = useState<WorkoutType[]>([]);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    Promise.all([
      getData<Overview>("overview"),
      getData<Engagement>("engagement"),
      getData<DayMiles[]>("miles-by-day"),
      getData<DaySignup[]>("signups-by-day"),
      getData<Leaderboards>("leaderboards"),
      getData<WorkoutType[]>("workout-types"),
    ])
      .then(([o, e, m, s, b, t]) => {
        setOverview(o);
        setEngagement(e);
        setMiles(m);
        setSignups(s);
        setBoards(b);
        setTypes(t);
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
    </div>
  );
}
