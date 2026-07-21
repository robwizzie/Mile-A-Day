"use client";

import { useEffect, useState } from "react";
import { BarList, Card, fmt, getData, Loading, StatCard } from "./lib";

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
  instagram: "Instagram",
  tiktok: "TikTok",
  reddit: "Reddit",
  google: "Google",
  youtube: "YouTube",
  other: "Other",
  unknown: "Not asked yet",
};

const pretty = (s: string) =>
  SOURCE_LABELS[s] ??
  s.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());

export function GrowthTab() {
  const [r, setR] = useState<Referrals | null>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    getData<Referrals>("referrals")
      .then(setR)
      .catch((e) => {
        if (e?.message !== "unauthorized") setErr("Failed to load referrals.");
      });
  }, []);

  if (err) return <p className="text-sm text-[#c72554]">{err}</p>;
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
    <div className="space-y-6">
      <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
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

      <div className="grid gap-6 lg:grid-cols-2">
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
            }))}
            color="#38bdf8"
            emptyLabel="No attributed signups yet — data appears as new users pick a source at onboarding."
          />
        </Card>

        <Card
          title="Top friend referrers"
          hint="Named when “Friend” is picked."
        >
          <BarList
            items={r.friend_referrers.map((f) => ({
              label: f.detail,
              value: f.count,
            }))}
            color="#34d399"
            emptyLabel="No named friend referrers yet."
            formatValue={(v) => `${v} signup${v === 1 ? "" : "s"}`}
          />
        </Card>

        <Card
          title="Signup goals"
          hint="What users say they want out of the app."
        >
          <BarList
            items={r.by_goal
              .filter((g) => g.goal !== "unknown")
              .map((g) => ({ label: pretty(g.goal), value: g.count }))}
            color="#fbbf24"
            emptyLabel="No signup goals recorded yet."
          />
        </Card>

        <Card title="Experience level" hint="Self-reported running experience.">
          <BarList
            items={r.by_experience
              .filter((e) => e.level !== "unknown")
              .map((e) => ({ label: pretty(e.level), value: e.count }))}
            color="#a78bfa"
            emptyLabel="No experience levels recorded yet."
          />
        </Card>
      </div>
    </div>
  );
}
