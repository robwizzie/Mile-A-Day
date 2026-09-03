"use client";

import { useCallback, useEffect, useState } from "react";
import {
  BarList,
  Card,
  Chip,
  fmt,
  fmtDate,
  getData,
  HEAT_HUE,
  postData,
  Loading,
  MAD_SUCCESS,
  MAD_WARNING,
  pct,
  Section,
  STACK_SECTIONS,
  WALK_BLUE,
  relativeDay,
  StatCard,
} from "./lib";
import { HeatGrid } from "./charts";
import { useDrilldown, useOpenUser } from "./Drilldown";

type ReferralGraph = {
  summary: {
    total_users: number;
    friend_referred: number;
    matched: number;
    unmatched: number;
    referrers: number;
  };
  referrers: {
    referrer_id: string | null;
    referrer_username: string | null;
    typed_as: string;
    linked_by_hand?: boolean;
    count: number;
    active: number;
    referred: {
      user_id: string;
      username: string | null;
      name: string | null;
      created_at: string;
      last_active: string | null;
      total_miles: number;
      current_streak: number;
    }[];
  }[];
};

type Retention = {
  max_week: number;
  cohorts: {
    cohort: string;
    size: number;
    weeks: { week: number; users: number; pct: number }[];
  }[];
};

type Referrals = {
  by_source: { source: string; count: number }[];
  by_goal: { goal: string; count: number }[];
  by_experience: { level: string; count: number }[];
  friend_referrers: { detail: string; count: number }[];
  funnel: { total: number; completed_onboarding: number; gave_source: number };
};

// Pretty labels for the fixed referral-source catalog (backend normalizes
// anything off-catalog to "other"; pre-onboarding users read "unknown").
const SOURCE_LABELS: Record<string, string> = {
  app_store: "App Store search",
  friend: "Friend",
  developer: "Sent by the team",
  instagram: "Instagram",
  tiktok: "TikTok",
  reddit: "Reddit",
  google: "Google",
  youtube: "YouTube",
  ai_chat: "ChatGPT / AI",
  social_ad: "Social media ad",
  flyer: "Flyer or poster",
  other: "Other",
  unknown: "Not asked yet",
};

const pretty = (s: string) =>
  SOURCE_LABELS[s] ??
  s.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());

/**
 * Who brought whom in.
 *
 * There is no referral code — attribution is a name a new user TYPES at
 * onboarding, so this shows the resolved and unresolved halves separately
 * rather than pretending every typed name is an account. The number that
 * matters is `active`: a referrer who brought in ten people who all stopped
 * running brought in nobody.
 */
function ReferralGraphPanel() {
  const openUser = useOpenUser();
  const openDrill = useDrilldown();
  const [g, setG] = useState<ReferralGraph | null>(null);
  const [openId, setOpenId] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);

  const load = useCallback(() => {
    getData<ReferralGraph>("referral-graph")
      .then(setG)
      .catch((e) => {
        if (e?.message !== "unauthorized")
          setErr("Failed to load the referral graph.");
      });
  }, []);

  useEffect(load, [load]);

  /**
   * Record (or clear) who a typed name meant. This writes an alias, never
   * the user's own answer — `referral_detail` stays exactly as entered, so
   * the link is reversible and the original is still auditable.
   */
  async function link(alias: string, userId: string | null) {
    setBusy(alias);
    try {
      const params = new URLSearchParams({ alias });
      if (userId) params.set("userId", userId);
      await postData(`referral-alias?${params.toString()}`);
      load();
    } catch (e) {
      setErr(e instanceof Error ? e.message : "Could not link that name.");
    } finally {
      setBusy(null);
    }
  }

  if (err) return <Card title="Who referred whom">{err}</Card>;
  if (!g)
    return (
      <Card title="Who referred whom">
        <Loading />
      </Card>
    );

  const { summary } = g;

  return (
    <Card
      hint={`${fmt(summary.friend_referred)} people said a person sent them — a friend, or one of the team. ${fmt(summary.matched)} named an account we could find; ${fmt(summary.unmatched)} typed something that matches no username. Tap a row to see who they brought in.`}
    >
      {g.referrers.length === 0 ? (
        <p className="text-sm text-white/40">
          Nobody has named anyone yet — this fills in as new users pick
          “Friend” or “Someone from the team” at onboarding.
        </p>
      ) : (
        <ul className="divide-y divide-white/5">
          {g.referrers.map((r) => {
            const key = r.referrer_id ?? `typed:${r.typed_as}`;
            const open = openId === key;
            return (
              <li key={key} className="py-2.5">
                <button
                  onClick={() => setOpenId(open ? null : key)}
                  className="flex w-full items-center justify-between gap-3 text-left"
                >
                  <span className="flex min-w-0 items-center gap-2">
                    <span className="w-3 shrink-0 text-xs text-white/30">
                      {open ? "▾" : "▸"}
                    </span>
                    <span className="truncate text-sm text-white/90">
                      {r.referrer_username ? `@${r.referrer_username}` : r.typed_as}
                    </span>
                    {!r.referrer_id && <Chip text="no such user" tone="bad" />}
                    {r.linked_by_hand && (
                      <Chip text="linked by hand" tone="info" />
                    )}
                  </span>
                  <span className="shrink-0 text-sm tabular-nums text-white/50">
                    <span className="text-white/90">{r.count}</span> brought in
                    {" · "}
                    <span
                      className={r.active > 0 ? "" : "text-white/40"}
                      style={r.active > 0 ? { color: MAD_SUCCESS } : undefined}
                    >
                      {r.active} still running
                    </span>
                  </span>
                </button>

                {/* A name that resolved to nobody is not a dead end: an admin
                    who knows who was meant can say so. */}
                {(!r.referrer_id || r.linked_by_hand) && (
                  <div className="mt-1 ml-5 flex items-center gap-2 pl-4">
                    <button
                      disabled={busy === r.typed_as}
                      onClick={() =>
                        openDrill({
                          kind: "link_candidates",
                          id: r.typed_as,
                          pickHint: "tap whoever they meant",
                          onPick: (userId) => link(r.typed_as, userId),
                        })
                      }
                      className="rounded-full border border-white/[0.12] px-2.5 py-0.5 text-[11px] text-white/55 transition hover:text-white disabled:opacity-40"
                    >
                      {r.linked_by_hand ? "Link to someone else" : "Link to a user"}
                    </button>
                    {r.linked_by_hand && (
                      <button
                        disabled={busy === r.typed_as}
                        onClick={() => link(r.typed_as, null)}
                        className="rounded-full border border-white/[0.12] px-2.5 py-0.5 text-[11px] text-white/40 transition hover:text-white disabled:opacity-40"
                      >
                        Unlink
                      </button>
                    )}
                  </div>
                )}

                {open && (
                  <ul className="mt-2 ml-5 space-y-1.5 border-l border-white/10 pl-4">
                    {r.referred.map((u) => (
                      <li key={u.user_id}>
                        <button
                          onClick={() => openUser(u.user_id)}
                          className="-mx-2 flex w-[calc(100%+1rem)] items-baseline justify-between gap-3 rounded-lg px-2 py-0.5 text-left text-xs transition hover:bg-white/[0.05]"
                        >
                          <span className="truncate text-white/70">
                            {u.username
                              ? `@${u.username}`
                              : u.name || u.user_id.slice(0, 8)}
                          </span>
                          <span className="shrink-0 tabular-nums text-white/40">
                            joined {fmtDate(u.created_at)} · last run{" "}
                            {relativeDay(u.last_active)} ·{" "}
                            {Math.round(u.total_miles)} mi
                            {u.current_streak > 0 && ` · ${u.current_streak}🔥`}
                          </span>
                        </button>
                      </li>
                    ))}
                  </ul>
                )}
              </li>
            );
          })}
        </ul>
      )}
    </Card>
  );
}

const WEEKDAY = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

/**
 * Weekly signup cohorts × how many of that cohort were still logging a mile
 * N weeks later. The triangle narrows on its own — a cohort three weeks old
 * has no week-4 cell to fill, which is why those read as blank rather than 0.
 */
function RetentionPanel() {
  const open = useDrilldown();
  const [r, setR] = useState<Retention | null>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    getData<Retention>("retention")
      .then(setR)
      .catch((e) => {
        if (e?.message !== "unauthorized") setErr("Failed to load retention.");
      });
  }, []);

  if (err) return <Card title="Retention">{err}</Card>;
  if (!r)
    return (
      <Card title="Retention">
        <Loading />
      </Card>
    );
  if (r.cohorts.length === 0)
    return (
      <Card title="Retention">
        <p className="text-sm text-white/40">Not enough signup history yet.</p>
      </Card>
    );

  const today = new Date();
  const weeksSince = (cohort: string) =>
    Math.floor(
      (today.getTime() - new Date(`${cohort}T00:00:00`).getTime()) /
        (7 * 86_400_000),
    );

  return (
    <Card hint="Share of each week's signups still logging a mile N weeks later. Week 0 is the week they joined. Tap a week to see who joined then.">
      <HeatGrid
        hue={HEAT_HUE}
        rows={r.cohorts.map((c) => ({
          key: c.cohort,
          label: `${c.cohort.slice(5)} · ${c.size}`,
        }))}
        cols={Array.from({ length: r.max_week + 1 }, (_, w) => ({
          key: String(w),
          label: `W${w}`,
        }))}
        value={(cohortKey, weekKey) => {
          const c = r.cohorts.find((x) => x.cohort === cohortKey);
          const w = Number(weekKey);
          // A cohort that has not lived this long yet has no cell, which is
          // different from a cohort that lost everybody.
          if (!c || w > weeksSince(cohortKey)) return null;
          return c.weeks.find((x) => x.week === w)?.pct ?? 0;
        }}
        title={(cohort, week, v) => `${cohort} · ${week}: ${v}% still running`}
        onRowClick={(cohortKey) => open({ kind: "cohort", id: cohortKey })}
        formatValue={(v) => `${Math.round(v)}%`}
        legend="Each row is a signup week; the label shows its size."
      />
    </Card>
  );
}

export function GrowthTab() {
  const open = useDrilldown();
  const [r, setR] = useState<Referrals | null>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    getData<Referrals>("referrals")
      .then(setR)
      .catch((e) => {
        if (e?.message !== "unauthorized") setErr("Failed to load referrals.");
      });
  }, []);

  if (err) return <p className="text-sm text-[#d94059]">{err}</p>;
  if (!r) return <Loading />;

  const { funnel } = r;
  const sourcePct = funnel.total
    ? Math.round((funnel.gave_source / funnel.total) * 100)
    : 0;
  const onbPct = funnel.total
    ? Math.round((funnel.completed_onboarding / funnel.total) * 100)
    : 0;

  // Split the "known source" answers from the not-yet-asked bucket so the
  // acquisition chart reflects real attribution, with the gap called out.
  const known = r.by_source.filter((s) => s.source !== "unknown");
  const unknown = r.by_source.find((s) => s.source === "unknown")?.count ?? 0;

  return (
    <div className={STACK_SECTIONS}>
      <Section
        title="Acquisition"
        hint="Where people say they came from, answered at onboarding."
      >
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <StatCard label="Total users" value={fmt(funnel.total)} />
        <StatCard
          label="Gave a source"
          value={fmt(funnel.gave_source)}
          sub={`${sourcePct}% attributed`}
          accent
        />
        <StatCard
          label="Completed onboarding"
          value={fmt(funnel.completed_onboarding)}
          sub={`${onbPct}% of users`}
        />
        <StatCard
          label="Not yet asked"
          value={fmt(unknown)}
          sub="pre-onboarding users"
        />
      </div>

      <div className="grid gap-5 lg:grid-cols-2">
        <Card
          title="Where users come from"
          hint="Self-reported at signup. Excludes users who predate the onboarding step."
        >
          <BarList
            items={known.map((s) => ({
              label: pretty(s.source),
              value: s.count,
              sub: funnel.gave_source
                ? `${Math.round((s.count / funnel.gave_source) * 100)}%`
                : undefined,
              onClick: () => open({ kind: "referral_source", id: s.source }),
            }))}
            color={WALK_BLUE}
            emptyLabel="No attributed signups yet — data appears as new users pick a source at onboarding."
          />
        </Card>

        <Card
          title="Signup goals"
          hint="What users say they want out of the app."
        >
          <BarList
            items={r.by_goal
              .filter((g) => g.goal !== "unknown")
              .map((g) => ({
                label: pretty(g.goal),
                value: g.count,
                onClick: () => open({ kind: "signup_goal", id: g.goal }),
              }))}
            color={MAD_WARNING}
            emptyLabel="No signup goals recorded yet."
          />
        </Card>

        <Card title="Experience level" hint="Self-reported running experience.">
          <BarList
            items={r.by_experience
              .filter((e) => e.level !== "unknown")
              .map((e) => ({
                label: pretty(e.level),
                value: e.count,
                onClick: () => open({ kind: "experience_level", id: e.level }),
              }))}
            color={MAD_SUCCESS}
            emptyLabel="No experience levels recorded yet."
          />
        </Card>
      </div>
      </Section>

      <Section
        title="Referrals"
        hint="There are no referral codes — attribution is the name a new user types at onboarding, resolved against real accounts here."
      >
        <ReferralGraphPanel />
      </Section>

      <Section
        title="Retention"
        hint="Whether the people we get stay."
      >
        <RetentionPanel />
      </Section>
    </div>
  );
}
