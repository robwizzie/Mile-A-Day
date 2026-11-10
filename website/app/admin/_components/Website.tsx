"use client";

import { useEffect, useState } from "react";
import {
  BarList,
  Card,
  fmt,
  getData,
  Loading,
  MAD_SUCCESS,
  pct,
  Section,
  SegmentedControl,
  STACK_SECTIONS,
  StatCard,
  WALK_BLUE,
} from "./lib";
import { HeatGrid, TimeSeriesBars } from "./charts";

// mileaday.run's own traffic: backend GET /admin/web (webAnalyticsService).
// First-party and anonymous: a "visit" is one visitor on one day (the
// visitor hash rotates daily), page views are page loads and client-side
// navigations, and an App Store tap is any click on an App Store link.

type Totals = {
  views: number;
  visits: number;
  clicks: number;
  store_taps: number;
  store_visits: number;
  bounced: number;
  views_per_visit: number;
};

type WebAnalytics = {
  days: number;
  generated_at: string;
  live_visitors: number;
  live_pages: { path: string; visitors: number }[];
  totals: Totals;
  prior: Totals;
  series: { date: string; views: number; visits: number; store_taps: number }[];
  hours: { hour: number; views: number }[];
  pages: { path: string; views: number; visits: number }[];
  referrers: { source: string; visits: number }[];
  campaigns: {
    source: string;
    medium: string | null;
    campaign: string | null;
    visits: number;
  }[];
  clicks: { target: string; clicks: number; visits: number }[];
  store_by_page: { path: string; taps: number }[];
  devices: { device: string; visits: number }[];
  countries: { country: string; visits: number }[];
};

type Window = "1" | "7" | "30" | "90";
const WINDOWS: { value: Window; label: string }[] = [
  { value: "1", label: "24 hours" },
  { value: "7", label: "7 days" },
  { value: "30", label: "30 days" },
  { value: "90", label: "90 days" },
];

const change = (cur: number, prev: number) =>
  prev > 0 ? ((cur - prev) / prev) * 100 : null;
const rate = (part: number, whole: number) =>
  whole > 0 ? (part / whole) * 100 : 0;
const pctText = (v: number) => `${v.toFixed(v < 10 && v > 0 ? 1 : 0)}%`;

/** Friendly names for the tracker's click labels. */
const TARGET_LABELS: Record<string, string> = {
  app_store: "App Store",
  email: "Email us",
  android_waitlist: "Android waitlist",
  desk_interest: "Desk: I'd buy one",
};
const targetLabel = (t: string) =>
  TARGET_LABELS[t] ?? (t.startsWith("out:") ? `↗ ${t.slice(4)}` : t);

const pageLabel = (p: string) =>
  p === "/"
    ? "Home"
    : p.startsWith("/u/")
      ? `Profile ${p.slice(3)}`
      : p.startsWith("/p/")
        ? "Shared post"
        : p;

const COUNTRY =
  typeof Intl !== "undefined" && "DisplayNames" in Intl
    ? new Intl.DisplayNames(["en"], { type: "region" })
    : null;
const countryName = (c: string) => {
  try {
    return COUNTRY?.of(c) ?? c;
  } catch {
    return c;
  }
};

export function WebsiteTab() {
  const [win, setWin] = useState<Window>("30");
  const [data, setData] = useState<WebAnalytics | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    setData(null);
    setError(null);
    getData<WebAnalytics>(`web?days=${win}`)
      .then((d) => alive && setData(d))
      .catch((e) => alive && setError(String(e?.message ?? e)));
    return () => {
      alive = false;
    };
  }, [win]);

  // The live count refreshes on its own every 30 s.
  const [live, setLive] = useState<{
    n: number;
    pages: WebAnalytics["live_pages"];
  } | null>(null);
  useEffect(() => {
    let alive = true;
    const tick = () =>
      getData<WebAnalytics>("web?days=1")
        .then(
          (d) => alive && setLive({ n: d.live_visitors, pages: d.live_pages }),
        )
        .catch(() => {});
    tick();
    const id = setInterval(tick, 30_000);
    return () => {
      alive = false;
      clearInterval(id);
    };
  }, []);

  const picker = (
    <SegmentedControl<Window> value={win} options={WINDOWS} onChange={setWin} />
  );

  if (error) {
    return (
      <Section title="Website" actions={picker}>
        <Card>
          <p className="text-sm text-white/60">
            Couldn&apos;t load website analytics: {error}
          </p>
        </Card>
      </Section>
    );
  }
  if (!data) return <Loading label="Loading website analytics…" />;

  const t = data.totals;
  const p = data.prior;
  const conversion = rate(t.store_visits, t.visits);
  const priorConversion = rate(p.store_visits, p.visits);
  const bounce = rate(t.bounced, t.visits);
  const spark = (k: "views" | "visits" | "store_taps") =>
    data.series.map((d) => d[k]);
  const empty = t.views === 0 && t.clicks === 0;

  return (
    <div className={STACK_SECTIONS}>
      <Section
        title="Website"
        hint="mileaday.run, counted by the site itself: anonymous, no cookies. A visit is one person on one day."
        actions={picker}
      >
        <div className="flex flex-wrap items-center gap-3 rounded-2xl border border-white/[0.08] bg-white/[0.05] px-4 py-3">
          <span className="relative flex h-2.5 w-2.5">
            <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-[#33b34d] opacity-70 motion-reduce:animate-none" />
            <span className="relative inline-flex h-2.5 w-2.5 rounded-full bg-[#33b34d]" />
          </span>
          <span className="mad-num text-[22px] font-extrabold">
            {fmt(live?.n ?? data.live_visitors)}
          </span>
          <span className="text-sm text-white/55">
            on the site right now (last 5 minutes)
          </span>
          {(live?.pages ?? data.live_pages).length > 0 && (
            <span className="text-[12.5px] text-white/40">
              ·{" "}
              {(live?.pages ?? data.live_pages)
                .map((lp) => `${pageLabel(lp.path)} (${lp.visitors})`)
                .join(", ")}
            </span>
          )}
        </div>

        {empty && (
          <Card>
            <p className="text-sm text-white/60">
              No visits recorded in this window yet. Events start arriving once
              the site with the tracker is deployed.
            </p>
          </Card>
        )}

        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <StatCard
            label="Visits"
            value={fmt(t.visits)}
            changePct={change(t.visits, p.visits)}
            previous={p.visits}
            current={t.visits}
            spark={spark("visits")}
            accent
          />
          <StatCard
            label="Page views"
            value={fmt(t.views)}
            sub={`${t.views_per_visit.toFixed(1)} pages per visit`}
            changePct={change(t.views, p.views)}
            previous={p.views}
            current={t.views}
            spark={spark("views")}
          />
          <StatCard
            label="App Store taps"
            value={fmt(t.store_taps)}
            sub={`${fmt(t.store_visits)} visits tapped through`}
            changePct={change(t.store_taps, p.store_taps)}
            previous={p.store_taps}
            current={t.store_taps}
            spark={spark("store_taps")}
          />
          <StatCard
            label="Tap-through rate"
            value={pctText(conversion)}
            sub={p.visits > 0 ? `of visits tapped the App Store (was ${pctText(priorConversion)})` : "of visits tapped the App Store"}
            changePct={
              priorConversion > 0 ? change(conversion, priorConversion) : null
            }
          />
          <StatCard
            label="Clicks"
            value={fmt(t.clicks)}
            sub="buttons and links, all kinds"
            changePct={change(t.clicks, p.clicks)}
            previous={p.clicks}
            current={t.clicks}
          />
          <StatCard
            label="Bounce rate"
            value={pctText(bounce)}
            sub="visits that saw one page and clicked nothing"
            tone="up-bad"
            changePct={
              rate(p.bounced, p.visits) > 0
                ? change(bounce, rate(p.bounced, p.visits))
                : null
            }
          />
          <StatCard
            label="Desktop vs phone"
            value={deviceSplit(data.devices)}
            sub="share of visits on a phone"
          />
          <StatCard
            label="Top source"
            value={data.referrers[0] ? data.referrers[0].source : "—"}
            sub={
              data.referrers[0]
                ? `${pctText(rate(data.referrers[0].visits, t.visits))} of visits`
                : undefined
            }
          />
        </div>
      </Section>

      <Section title="Traffic over time" hint="Days are Eastern time.">
        <div className="grid gap-5 lg:grid-cols-2">
          <Card>
            <TimeSeriesBars
              data={data.series.map((d) => ({ date: d.date, value: d.visits }))}
              label="Visits per day"
              formatValue={(v) => fmt(v)}
            />
          </Card>
          <Card>
            <TimeSeriesBars
              data={data.series.map((d) => ({
                date: d.date,
                value: d.store_taps,
              }))}
              label="App Store taps per day"
              color={MAD_SUCCESS}
              hoverColor="#a6f0b6"
              formatValue={(v) => fmt(v)}
            />
          </Card>
        </div>
        <Card
          title="When people visit"
          hint="Page views by hour of day, Eastern time."
        >
          <HeatGrid
            rows={[{ key: "views", label: "Views" }]}
            cols={Array.from({ length: 24 }, (_, h) => ({
              key: String(h),
              label: hourLabel(h),
            }))}
            value={(_, c) =>
              data.hours.find((x) => x.hour === Number(c))?.views ?? 0
            }
            title={(_, c, v) => `${c}: ${fmt(v)} views`}
            colLabel={(_, i) => i % 3 === 0}
            formatValue={(v) => fmt(v)}
            fit
          />
        </Card>
      </Section>

      <Section title="What they read and tap">
        <div className="grid gap-5 lg:grid-cols-2">
          <Card
            title="Top pages"
            hint="Page views, and how many visits saw each."
          >
            <BarList
              items={data.pages.map((pg) => ({
                label: pageLabel(pg.path),
                value: pg.views,
                sub: `${fmt(pg.visits)} visits`,
              }))}
              emptyLabel="No page views yet."
            />
          </Card>
          <Card title="Top clicks" hint="Every tracked button and link.">
            <BarList
              items={data.clicks.map((c) => ({
                label: targetLabel(c.target),
                value: c.clicks,
                sub: `${fmt(c.visits)} visits`,
                color: c.target === "app_store" ? MAD_SUCCESS : undefined,
              }))}
              emptyLabel="No clicks yet."
            />
          </Card>
          <Card
            title="Where App Store taps happen"
            hint="The page someone was on when they tapped through."
          >
            <BarList
              items={data.store_by_page.map((s) => ({
                label: pageLabel(s.path),
                value: s.taps,
              }))}
              color={MAD_SUCCESS}
              emptyLabel="No App Store taps yet."
            />
          </Card>
          <Card title="Devices" hint="Share of visits.">
            <BarList
              items={data.devices.map((d) => ({
                label: d.device[0].toUpperCase() + d.device.slice(1),
                value: d.visits,
                sub: `${pct(d.visits, t.visits)}%`,
                color: d.device === "mobile" ? WALK_BLUE : undefined,
              }))}
              emptyLabel="No visits yet."
            />
          </Card>
        </div>
      </Section>

      <Section
        title="Where they come from"
        hint="A visit's source is the site that sent its first page view."
      >
        <div className="grid gap-5 lg:grid-cols-3">
          <Card title="Sources">
            <BarList
              items={data.referrers.map((r) => ({
                label: r.source,
                value: r.visits,
                sub: `${pct(r.visits, t.visits)}%`,
              }))}
              emptyLabel="No visits yet."
            />
          </Card>
          <Card
            title="Campaigns"
            hint="Links tagged with utm_source / utm_campaign."
          >
            <BarList
              items={data.campaigns.map((c) => ({
                label: [c.source, c.medium, c.campaign]
                  .filter(Boolean)
                  .join(" · "),
                value: c.visits,
              }))}
              emptyLabel="No tagged links yet. Add ?utm_source=instagram&utm_campaign=… to links you share."
            />
          </Card>
          <Card title="Countries">
            <BarList
              items={data.countries.map((c) => ({
                label: countryName(c.country),
                value: c.visits,
              }))}
              emptyLabel="No country data yet."
            />
          </Card>
        </div>
      </Section>
    </div>
  );
}

function hourLabel(h: number) {
  return h === 0 ? "12a" : h < 12 ? `${h}a` : h === 12 ? "12p" : `${h - 12}p`;
}

function deviceSplit(devices: WebAnalytics["devices"]) {
  const total = devices.reduce((s, d) => s + d.visits, 0);
  const mobile = devices.find((d) => d.device === "mobile")?.visits ?? 0;
  return total ? `${Math.round((mobile / total) * 100)}% phone` : "—";
}
