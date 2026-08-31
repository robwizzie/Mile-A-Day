"use client";

import { useEffect, useState } from "react";
import {
  AdoptionBar,
  BarList,
  Card,
  Chip,
  fmt,
  getData,
  Loading,
  MAD_SUCCESS,
  MAD_WARNING,
  pct,
  relativeDay,
  Section,
  SERIES,
  SegmentedControl,
  STACK_SECTIONS,
  StatCard,
  WALK_BLUE,
} from "./lib";
import { StackedDayBars, TimeSeriesBars } from "./charts";
import { useDrilldown, useOpenUser } from "./Drilldown";

// ─── Types (mirror backend/src/services/adminAnalyticsService.ts) ────

type CompetitionStats = {
  summary: {
    total: number;
    live: number;
    upcoming: number;
    finished: number;
    created_7d: number;
    created_30d: number;
    team_competitions: number;
    players: number;
    total_users: number;
    invites_accepted: number;
    invites_pending: number;
    invites_declined: number;
    avg_roster: number;
  };
  by_type: {
    type: string;
    total: number;
    live: number;
    players: number;
    avg_roster: number;
  }[];
  by_week: { week: string; created: number; players: number }[];
  live: {
    id: string;
    competition_name: string | null;
    type: string;
    start_date: string | null;
    end_date: string | null;
    days_left: number | null;
    owner_username: string | null;
    players: number;
    pending: number;
    team_play: boolean;
  }[];
  top_organizers: {
    user_id: string;
    username: string | null;
    created: number;
  }[];
  top_winners: { user_id: string; username: string | null; wins: number }[];
};

type TokenStats = {
  enrollment: {
    total_users: number;
    enrolled: number;
    ever_double_down: number;
    ever_streak_save: number;
    ever_assist: number;
  };
  spend_by_kind: {
    kind: string;
    total: number;
    last_30d: number;
    last_7d: number;
    users: number;
  }[];
  spend_by_day: {
    date: string;
    streak_save: number;
    double_down: number;
    streak_assist: number;
  }[];
  held: {
    enrolled: number;
    double_down: number;
    streak_save: number;
    streak_assist: number;
    targets: {
      double_down: number;
      streak_save: number;
      streak_assist: number;
    };
  };
  assist_funnel: {
    offered: number;
    accepted: number;
    declined: number;
    expired: number;
    pending: number;
  };
  pauses: { total: number; active: number; expired: number; avg_days: number };
  breaks: {
    total: number;
    last_30d: number;
    saved_30d: number;
    avg_prior_streak: number;
  };
  top_donors: { user_id: string; username: string | null; assists: number }[];
};

type Adoption = {
  total_users: number;
  active_30d: number;
  features: {
    key: string;
    label: string;
    group: string;
    users_ever: number;
    users_30d: number;
    events_ever: number;
    events_30d: number;
  }[];
};

type Community = {
  friends: {
    pairs: number;
    pending: number;
    connected_users: number;
    total_users: number;
    avg_friends: number;
    solo_users: number;
  };
  buddy: {
    sessions: number;
    sessions_30d: number;
    live_now: number;
    completed: number;
    participants: number;
    avg_crew: number;
    by_mode: { mode: string; count: number }[];
    by_origin: { origin: string; count: number }[];
  };
  challenges: {
    served: number;
    completed: number;
    served_30d: number;
    completed_30d: number;
    by_challenge: {
      challenge_key: string;
      title: string | null;
      served: number;
      completed: number;
    }[];
  };
  badges: {
    earned: number;
    holders: number;
    top: { badge_id: string; name: string; rarity: string; earned: number }[];
  };
  live_now: { tracking: number; buddy_sessions: number };
  top_photographers: {
    user_id: string;
    username: string | null;
    photos: number;
    last_photo_at: string | null;
  }[];
};

const nameOf = (u: { username: string | null; user_id: string }) =>
  u.username ? `@${u.username}` : u.user_id.slice(0, 8);

const TYPE_LABELS: Record<string, string> = {
  streaks: "Streaks",
  apex: "Apex",
  clash: "Clash",
  targets: "Targets",
  race: "Race",
};

const MODE_LABELS: Record<string, string> = {
  together: "Just together",
  coop_goal: "Shared goal",
  race_goal: "Race to a distance",
  race_time: "Race against the clock",
};

const ORIGIN_LABELS: Record<string, string> = {
  invite: "Invited a friend",
  code: "Join code",
  join_active: "Joined a walk in progress",
  nearby: "Nearby",
};

const pretty = (map: Record<string, string>, key: string) =>
  map[key] ?? key.replace(/_/g, " ");

// ─── Competitions ───────────────────────────────────────────────────

function Competitions({ d }: { d: CompetitionStats }) {
  const open = useDrilldown();
  const openUser = useOpenUser();
  const s = d.summary;
  const maxWeek = Math.max(...d.by_week.map((w) => w.created), 1);

  return (
    <Section
      title="Competitions"
      hint="Who is competing, in what, and whether the feature is still being started."
    >

      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <StatCard
          label="Running now"
          value={fmt(s.live)}
          sub={`${fmt(s.upcoming)} waiting to start`}
          accent
        />
        <StatCard
          label="Ever created"
          value={fmt(s.total)}
          sub={`${fmt(s.created_30d)} in the last 30 days`}
        />
        <StatCard
          label="People who compete"
          value={fmt(s.players)}
          sub={`${pct(s.players, s.total_users)}% of all users`}
          onClick={() => open({ kind: "feature", id: "competition" })}
        />
        <StatCard
          label="Average roster"
          value={s.avg_roster.toFixed(1)}
          sub={`${fmt(s.team_competitions)} use teams`}
        />
      </div>

      <div className="grid gap-5 lg:grid-cols-2">
        <Card
          title="Created per week"
          hint="Last 12 weeks. A flat line here is the feature going quiet, whatever the all-time total says."
        >
          {s.total === 0 ? (
            <p className="text-sm text-white/40">
              Nobody has started a competition yet.
            </p>
          ) : (
            <TimeSeriesBars
              data={d.by_week.map((w) => ({ date: w.week, value: w.created }))}
              label="Competitions started"
              formatValue={(v) => v.toFixed(0)}
              period="week"
            />
          )}
        </Card>

        <div className="space-y-5">
          <Card title="Which format people pick">
            <BarList
              items={d.by_type.map((t) => ({
                label: pretty(TYPE_LABELS, t.type),
                value: t.total,
                onClick: () => open({ kind: "competition_invites", id: "accepted" }),
                sub:
                  t.live > 0
                    ? `${t.live} live · ${t.avg_roster.toFixed(1)} per game`
                    : `${t.avg_roster.toFixed(1)} per game`,
              }))}
              emptyLabel="No competitions yet."
              formatValue={(v) => `${fmt(v)} started`}
            />
          </Card>
          <Card
            title="Invites"
            hint="A declined or forever-pending invite is the format not landing, not the feature failing."
          >
            <div className="grid grid-cols-3 gap-3 text-center">
              {[
                ["Accepted", s.invites_accepted, "ok", "accepted"],
                ["Pending", s.invites_pending, "muted", "pending"],
                ["Declined", s.invites_declined, "bad", "declined"],
              ].map(([label, value, tone, status]) => (
                <button
                  key={label as string}
                  onClick={() =>
                    open({
                      kind: "competition_invites",
                      id: status as string,
                    })
                  }
                  className="rounded-2xl border border-white/[0.08] bg-white/[0.05] p-3 transition hover:border-white/20 hover:bg-white/[0.08]"
                >
                  <div className="mad-num text-2xl font-extrabold text-white">
                    {fmt(value as number)}
                  </div>
                  <div className="mt-1.5">
                    <Chip
                      text={label as string}
                      tone={tone as "ok" | "bad" | "muted"}
                    />
                  </div>
                </button>
              ))}
            </div>
            <p className="mt-3 text-xs text-white/40">
              {pct(
                s.invites_accepted,
                s.invites_accepted + s.invites_declined + s.invites_pending,
              )}
              % of invites turn into a player.
            </p>
          </Card>
        </div>
      </div>

      <Card
        title="On right now"
        hint="Running and about-to-start competitions. An open-ended one (first-to / duration) has no end date to count down."
      >
        {d.live.length === 0 ? (
          <p className="text-sm text-white/40">Nothing is running right now.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-white/10 text-left text-xs text-white/40">
                  <th className="p-2 font-medium">Competition</th>
                  <th className="p-2 font-medium">Format</th>
                  <th className="p-2 font-medium">Host</th>
                  <th className="p-2 font-medium">In</th>
                  <th className="p-2 font-medium">Ends</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-white/5">
                {d.live.map((c) => {
                  const started =
                    !c.start_date ||
                    c.start_date <= new Date().toISOString().slice(0, 10);
                  return (
                    <tr
                      key={c.id}
                      onClick={() => open({ kind: "competition", id: c.id })}
                      className="cursor-pointer transition hover:bg-white/[0.04]"
                    >
                      <td className="p-2">
                        <span className="text-white/90">
                          {c.competition_name || "Untitled"}
                        </span>
                        <span className="ml-2 inline-flex gap-1">
                          <Chip
                            text={started ? "live" : "lobby"}
                            tone={started ? "ok" : "muted"}
                          />
                          {c.team_play && <Chip text="teams" tone="info" />}
                        </span>
                      </td>
                      <td className="p-2 text-white/60">
                        {pretty(TYPE_LABELS, c.type)}
                      </td>
                      <td className="p-2 whitespace-nowrap text-white/50">
                        {c.owner_username ? `@${c.owner_username}` : "—"}
                      </td>
                      <td className="p-2 whitespace-nowrap text-white/70">
                        {c.players}
                        {c.pending > 0 && (
                          <span className="text-white/35">
                            {" "}
                            +{c.pending} invited
                          </span>
                        )}
                      </td>
                      <td className="p-2 whitespace-nowrap text-white/50">
                        {c.days_left == null
                          ? "open-ended"
                          : c.days_left === 0
                            ? "today"
                            : `${c.days_left}d`}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <div className="grid gap-5 lg:grid-cols-2">
        <Card title="Who starts them" hint="The people carrying the feature.">
          <BarList
            items={d.top_organizers.map((o) => ({
              label: nameOf(o),
              value: o.created,
              onClick: () => openUser(o.user_id),
            }))}
            color={MAD_WARNING}
            emptyLabel="No competitions created yet."
            formatValue={(v) => `${v} started`}
          />
        </Card>
        <Card title="Who wins them">
          <BarList
            items={d.top_winners.map((o) => ({
              label: nameOf(o),
              value: o.wins,
              onClick: () => openUser(o.user_id),
            }))}
            color={MAD_SUCCESS}
            emptyLabel="None have been resolved yet."
            formatValue={(v) => `${v} won`}
          />
        </Card>
      </div>
    </Section>
  );
}

// ─── Streak tokens ──────────────────────────────────────────────────

const TOKEN_SERIES = [
  { key: "streak_save" as const, label: "Streak Save", color: SERIES[0] },
  { key: "double_down" as const, label: "Double Down", color: SERIES[1] },
  { key: "streak_assist" as const, label: "Streak Assist", color: SERIES[2] },
];

function StreakTokens({ d }: { d: TokenStats }) {
  const open = useDrilldown();
  const openUser = useOpenUser();
  const spent = (kind: string) =>
    d.spend_by_kind.find((k) => k.kind === kind) ?? {
      total: 0,
      last_30d: 0,
      users: 0,
    };
  const save = spent("streak_save");
  const dd = spent("double_down_recover");
  const assist = spent("streak_assist");
  const totalSpent = save.total + dd.total + assist.total;
  const f = d.assist_funnel;
  const answered = f.accepted + f.declined + f.expired;

  return (
    <Section
      title="Streak tokens"
      hint="Double Down, Streak Save and Assist — spent, held, and whether they are catching the streaks that matter."
    >

      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <StatCard
          label="Tokens spent"
          value={fmt(totalSpent)}
          sub={`${fmt(save.last_30d + dd.last_30d + assist.last_30d)} in the last 30 days`}
          accent
          onClick={() => open({ kind: "feature", id: "streak_token" })}
        />
        <StatCard
          label="Enrolled"
          value={fmt(d.enrollment.enrolled)}
          sub={`${pct(d.enrollment.enrolled, d.enrollment.total_users)}% of users are on a build that has them`}
        />
        <StatCard
          label="Streaks saved (30d)"
          value={fmt(d.breaks.saved_30d)}
          sub={`${fmt(d.breaks.last_30d)} broke anyway`}
        />
        <StatCard
          label="Injury pauses"
          value={fmt(d.pauses.active)}
          sub={`open now · ${fmt(d.pauses.total)} ever`}
          onClick={() => open({ kind: "feature", id: "injury_pause" })}
        />
      </div>

      <Card>
        <StackedDayBars
          data={d.spend_by_day}
          series={TOKEN_SERIES}
          label="Days rescued by a token — last 30 days"
          hint="Dated by the day that was saved, not the day the token was spent."
        />
      </Card>

      <div className="grid gap-5 lg:grid-cols-3">
        <Card
          title="Spent, by kind"
          hint="How many people have ever used each, and how many times."
        >
          <ul className="space-y-3">
            {[
              ["Streak Save", save, TOKEN_SERIES[0].color, "streak_save"],
              ["Double Down", dd, TOKEN_SERIES[1].color, "double_down_recover"],
              ["Streak Assist", assist, TOKEN_SERIES[2].color, "streak_assist"],
            ].map(([label, v, color, kind]) => {
              const stat = v as {
                total: number;
                last_30d: number;
                users: number;
              };
              return (
                <li key={label as string}>
                  <button
                    onClick={() => open({ kind: "token", id: kind as string })}
                    className="-mx-2 flex w-[calc(100%+1rem)] items-baseline justify-between gap-2 rounded-lg px-2 py-1 text-sm transition hover:bg-white/[0.05]"
                  >
                    <span className="flex items-center gap-2 text-white/85">
                      <span
                        className="h-2.5 w-2.5 rounded-full"
                        style={{ background: color as string }}
                        aria-hidden
                      />
                      {label as string}
                    </span>
                    <span className="tabular-nums text-white/45">
                      <span className="font-semibold text-white/95">
                        {fmt(stat.total)}
                      </span>{" "}
                      · {fmt(stat.users)} people
                    </span>
                  </button>
                </li>
              );
            })}
          </ul>
          <p className="mt-4 text-xs text-white/40">
            An average broken streak was {d.breaks.avg_prior_streak.toFixed(0)}{" "}
            days long.
          </p>
        </Card>

        <Card
          title="Held right now"
          hint="Enrolled users whose meter is full — a token in hand, waiting to be needed."
        >
          <ul className="space-y-3">
            {[
              [
                "Double Down",
                d.held.double_down,
                d.held.targets.double_down,
                "days",
              ],
              [
                "Streak Save",
                d.held.streak_save,
                d.held.targets.streak_save,
                "run days",
              ],
              [
                "Streak Assist",
                d.held.streak_assist,
                d.held.targets.streak_assist,
                "days",
              ],
            ].map(([label, held, target, unit]) => (
              <li key={label as string}>
                <div className="mb-1 flex items-baseline justify-between gap-2 text-sm">
                  <span className="text-white/80">{label as string}</span>
                  <span className="tabular-nums text-white/50">
                    <span className="text-white/90">{fmt(held as number)}</span>{" "}
                    of {fmt(d.held.enrolled)}
                  </span>
                </div>
                <div className="h-2 overflow-hidden rounded-full bg-white/[0.06]">
                  <div
                    className="h-full rounded-full"
                    style={{
                      width: `${pct(held as number, d.held.enrolled)}%`,
                      background: SERIES[0],
                    }}
                  />
                </div>
                <p className="mt-1 text-[11px] text-white/30">
                  earns every {target as number} {unit as string}
                </p>
              </li>
            ))}
          </ul>
        </Card>

        <Card
          title="Assist exchanges"
          hint="An Assist needs both sides to say yes, so an offer that nobody answers is the interesting number."
        >
          <div className="space-y-2 text-sm">
            {[
              ["Offered", f.offered],
              ["Accepted", f.accepted],
              ["Declined", f.declined],
              ["Expired unanswered", f.expired],
              ["Still waiting", f.pending],
            ].map(([label, v]) => (
              <div
                key={label as string}
                className="flex items-baseline justify-between gap-2"
              >
                <span className="text-white/60">{label as string}</span>
                <span className="tabular-nums text-white/90">
                  {fmt(v as number)}
                </span>
              </div>
            ))}
          </div>
          <p className="mt-3 text-xs text-white/40">
            {answered > 0
              ? `${pct(f.accepted, answered)}% of answered offers became a rescue.`
              : "No offer has been answered yet."}
          </p>
          {d.top_donors.length > 0 && (
            <div className="mt-4 border-t border-white/10 pt-3">
              <p className="mb-2 text-xs text-white/40">
                Most miles given away
              </p>
              <BarList
                items={d.top_donors.map((x) => ({
                  label: nameOf(x),
                  value: x.assists,
                  onClick: () => openUser(x.user_id),
                }))}
                color={SERIES[2]}
                formatValue={(v) => `${v}`}
              />
            </div>
          )}
        </Card>
      </div>
    </Section>
  );
}

// ─── Adoption + community ───────────────────────────────────────────

function Adoption({ d }: { d: Adoption }) {
  const open = useDrilldown();
  const groups = [...new Set(d.features.map((f) => f.group))];
  return (
    <Section
      title="What people actually use"
      hint={`Bar = share of all ${fmt(d.total_users)} users who ever did it. The solid part = the share still doing it in the last 30 days. Tap a row for the people behind it.`}
    >
      <div className="grid gap-5 lg:grid-cols-3">
        {groups.map((g) => (
          <Card key={g} title={g}>
            <ul className="space-y-3">
              {d.features
                .filter((f) => f.group === g)
                .sort((a, b) => b.users_ever - a.users_ever)
                .map((f) => (
                  <AdoptionBar
                    key={f.key}
                    label={f.label}
                    everCount={f.users_ever}
                    recentCount={f.users_30d}
                    total={d.total_users}
                    events={f.events_ever}
                    onClick={
                      f.users_ever > 0
                        ? () => open({ kind: "feature", id: f.key })
                        : undefined
                    }
                  />
                ))}
            </ul>
          </Card>
        ))}
      </div>
      <p className="text-xs text-white/40">
        Out of {fmt(d.total_users)} users, {fmt(d.active_30d)} logged a mile in
        the last 30 days — that is the pool any of these can be adopted by.
      </p>
    </Section>
  );
}

function CommunityPanels({ d }: { d: Community }) {
  const open = useDrilldown();
  const openUser = useOpenUser();
  const ch = d.challenges;
  return (
    <Section
      title="Community"
      hint="Whether people are finding each other at all."
    >

      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <StatCard
          label="Friendships"
          value={fmt(d.friends.pairs)}
          sub={`${d.friends.avg_friends.toFixed(1)} friends each`}
          onClick={() => open({ kind: "feature", id: "friend" })}
        />
        <StatCard
          label="Nobody added yet"
          value={fmt(d.friends.solo_users)}
          sub={`${pct(d.friends.solo_users, d.friends.total_users)}% of users are alone in here`}
        />
        <StatCard
          label="Buddy walks"
          value={fmt(d.buddy.sessions)}
          sub={`${fmt(d.buddy.sessions_30d)} in the last 30 days`}
          onClick={() => open({ kind: "feature", id: "buddy" })}
        />
        <StatCard
          label="Out there now"
          value={fmt(d.live_now.tracking)}
          sub={`${fmt(d.live_now.buddy_sessions)} buddy walks live`}
          accent
          onClick={() => open({ kind: "live_tracking" })}
        />
      </div>

      <div className="grid gap-5 lg:grid-cols-2">
        <Card
          title="Buddy walks — how they start"
          hint="Worth knowing before building another door into the feature."
        >
          <BarList
            items={d.buddy.by_origin.map((o) => ({
              label: pretty(ORIGIN_LABELS, o.origin),
              value: o.count,
              onClick: () => open({ kind: "buddy_origin", id: o.origin }),
            }))}
            color={SERIES[1]}
            emptyLabel="No buddy walks yet."
          />
          <div className="mt-4 border-t border-white/10 pt-3">
            <p className="mb-2 text-xs text-white/40">…and what they pick</p>
            <BarList
              items={d.buddy.by_mode.map((m) => ({
                label: pretty(MODE_LABELS, m.mode),
                value: m.count,
                onClick: () => open({ kind: "buddy_mode", id: m.mode }),
              }))}
              color={WALK_BLUE}
              emptyLabel="No buddy walks yet."
            />
          </div>
        </Card>

        <Card
          title="Daily challenges"
          hint="Served vs completed. A challenge everyone is handed and nobody finishes is too hard, not popular."
        >
          {ch.served > 0 && (
            <div className="mb-4 flex items-baseline gap-4 text-sm">
              <span className="text-white/60">
                <span className="text-2xl font-semibold text-white">
                  {pct(ch.completed, ch.served)}%
                </span>{" "}
                completed all-time
              </span>
              {ch.served_30d > 0 && (
                <span className="text-white/40">
                  {pct(ch.completed_30d, ch.served_30d)}% in the last 30 days
                </span>
              )}
            </div>
          )}
          {ch.by_challenge.length === 0 ? (
            <p className="text-sm text-white/40">
              No challenges have been served yet.
            </p>
          ) : (
            <ul className="space-y-2.5">
              {ch.by_challenge.map((c) => (
                <li key={c.challenge_key}>
                  <button
                    onClick={() =>
                      open({ kind: "challenge", id: c.challenge_key })
                    }
                    className="-mx-2 block w-[calc(100%+1rem)] rounded-lg px-2 py-1 text-left transition hover:bg-white/[0.05]"
                  >
                  <div className="mb-1 flex items-baseline justify-between gap-3 text-sm">
                    <span className="truncate text-white/80">
                      {c.title || c.challenge_key}
                    </span>
                    <span className="shrink-0 tabular-nums text-white/50">
                      {fmt(c.completed)}/{fmt(c.served)} ·{" "}
                      <span className="text-white/90">
                        {pct(c.completed, c.served)}%
                      </span>
                    </span>
                  </div>
                  <div className="h-2 overflow-hidden rounded-full bg-white/[0.06]">
                    <div
                      className="h-full rounded-full"
                      style={{
                        width: `${pct(c.completed, c.served)}%`,
                        background: SERIES[0],
                      }}
                    />
                  </div>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </Card>

        <Card
          title="Who is posting photos"
          actions={
            <button
              onClick={() => open({ kind: "feature", id: "photo_post" })}
              className="rounded-full border border-white/[0.12] px-3 py-1 text-xs text-white/55 transition hover:text-white"
            >
              See all
            </button>
          }
          hint="Real photos only — the auto route cards published on a skipped prompt are not people using the camera."
        >
          {d.top_photographers.length === 0 ? (
            <p className="text-sm text-white/40">No photos posted yet.</p>
          ) : (
            <ul className="space-y-2">
              {d.top_photographers.map((p) => (
                <li key={p.user_id}>
                  <button
                    onClick={() => openUser(p.user_id)}
                    className="-mx-2 flex w-[calc(100%+1rem)] items-baseline justify-between gap-3 rounded-lg px-2 py-1 text-left text-sm transition hover:bg-white/[0.05]"
                  >
                  <span className="truncate text-white/80">{nameOf(p)}</span>
                  <span className="shrink-0 tabular-nums text-white/50">
                    <span className="text-white/90">{fmt(p.photos)}</span>{" "}
                    photos · {relativeDay(p.last_photo_at)}
                  </span>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </Card>

        <Card
          title="Badges"
          hint={`${fmt(d.badges.earned)} earned by ${fmt(d.badges.holders)} people.`}
        >
          <BarList
            items={d.badges.top.map((b) => ({
              label: b.name,
              value: b.earned,
              sub: b.rarity,
              onClick: () => open({ kind: "badge", id: b.badge_id }),
            }))}
            color={MAD_WARNING}
            emptyLabel="No badges earned yet."
          />
        </Card>
      </div>
    </Section>
  );
}

// ─── Tab ────────────────────────────────────────────────────────────

type View = "all" | "competitions" | "tokens" | "adoption" | "community";

export function FeaturesTab() {
  const [view, setView] = useState<View>("all");
  const [comps, setComps] = useState<CompetitionStats | null>(null);
  const [tokens, setTokens] = useState<TokenStats | null>(null);
  const [adoption, setAdoption] = useState<Adoption | null>(null);
  const [community, setCommunity] = useState<Community | null>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    Promise.all([
      getData<CompetitionStats>("competitions"),
      getData<TokenStats>("streak-tokens"),
      getData<Adoption>("feature-adoption"),
      getData<Community>("community"),
    ])
      .then(([c, t, a, m]) => {
        setComps(c);
        setTokens(t);
        setAdoption(a);
        setCommunity(m);
      })
      .catch((e) => {
        if (e?.message !== "unauthorized")
          setErr("Failed to load feature usage.");
      });
  }, []);

  if (err) return <p className="text-sm text-[#d94059]">{err}</p>;
  if (!comps || !tokens || !adoption || !community) return <Loading />;

  const show = (v: View) => view === "all" || view === v;

  return (
    <div className={STACK_SECTIONS}>
      <div className="flex items-center justify-between gap-3">
        <SegmentedControl<View>
          value={view}
          onChange={setView}
          options={[
            { value: "all", label: "Everything" },
            { value: "adoption", label: "Adoption" },
            { value: "competitions", label: "Competitions" },
            { value: "tokens", label: "Streak tokens" },
            { value: "community", label: "Community" },
          ]}
        />
      </div>

      {show("adoption") && <Adoption d={adoption} />}
      {show("competitions") && <Competitions d={comps} />}
      {show("tokens") && <StreakTokens d={tokens} />}
      {show("community") && <CommunityPanels d={community} />}
    </div>
  );
}
