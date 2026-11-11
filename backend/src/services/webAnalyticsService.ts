import crypto from "node:crypto";
import { PostgresService } from "./DbService.js";

// The marketing site's own analytics: page views and tracked clicks on
// mileaday.run, written by POST /public/web-events and read by the admin
// Website tab. Anonymous by construction (see `web_events` in schema.ts):
// no cookie, no account, no IP stored. A visitor is a hash of IP + user
// agent + a salt derived per UTC day from a server secret, so the same
// person is one visitor for a day and a stranger the next; nothing here can
// follow anyone across days or be turned back into an address.

const db = PostgresService.getInstance();

export const WEB_EVENT_KINDS = ["view", "click"] as const;
export type WebEventKind = (typeof WEB_EVENT_KINDS)[number];

/** The tracker's label for every App Store link (the conversion we care about).
 *  A button can say where it sits after a colon (`app_store:hero`); every
 *  `app_store` or `app_store:*` label counts as an App Store tap. */
export const APP_STORE_TARGET = "app_store";
/** SQL LIKE pattern for every App Store label. */
export const APP_STORE_LIKE = "app_store%";

/** Windows the admin tab offers, in days. */
export const WEB_WINDOWS = [1, 7, 30, 90] as const;

/** The ET calendar the rest of the admin dashboard reads days in. */
const TZ = "America/New_York";

const SITE_HOSTS = new Set(["mileaday.run", "www.mileaday.run", "localhost"]);
const BOT_UA =
  /bot|crawl|spider|slurp|preview|headless|lighthouse|facebookexternalhit|embedly|whatsapp|telegram|discord|pingdom|uptime|monitor|curl|wget|python|axios|node-fetch|go-http/i;

function daySalt(now: Date): string {
  const secret =
    process.env.WEB_ANALYTICS_SALT || process.env.APP_JWT_SECRET || "mad-web";
  return crypto
    .createHash("sha256")
    .update(`${secret}|${now.toISOString().slice(0, 10)}`)
    .digest("hex");
}

/** One person's id for one UTC day; never reversible to the IP. */
export function visitorHash(
  ip: string,
  userAgent: string,
  now = new Date(),
): string {
  return crypto
    .createHash("sha256")
    .update(`${daySalt(now)}|${ip}|${userAgent}`)
    .digest("base64url")
    .slice(0, 22);
}

export function isBot(userAgent: string | undefined): boolean {
  return !userAgent || BOT_UA.test(userAgent);
}

export function deviceOf(userAgent: string): "mobile" | "tablet" | "desktop" {
  if (/iPad|Tablet|PlayBook|Silk|Kindle/i.test(userAgent)) return "tablet";
  if (/Mobi|iPhone|iPod|Android/i.test(userAgent)) return "mobile";
  return "desktop";
}

const clip = (v: unknown, max: number): string | null => {
  if (typeof v !== "string") return null;
  const s = v.trim();
  return s ? s.slice(0, max) : null;
};

/** A site path: leading slash, no query or hash, bounded. */
export function cleanPath(v: unknown): string | null {
  const s = clip(v, 400);
  if (!s || !s.startsWith("/")) return null;
  return s.split(/[?#]/)[0].slice(0, 200) || "/";
}

/** A click's label: the tracker's `data-track` name or the link's text. */
export function cleanTarget(v: unknown): string | null {
  const s = clip(v, 200);
  if (!s) return null;
  const t = s
    .replace(/[^\p{L}\p{N} .,:'&/+_-]/gu, "")
    .replace(/\s+/g, " ")
    .trim();
  return t ? t.slice(0, 80) : null;
}

/** Where they came from, as a bare host; our own pages are not a referrer. */
export function referrerHost(v: unknown): string | null {
  const s = clip(v, 500);
  if (!s) return null;
  try {
    const host = new URL(s).hostname.toLowerCase().replace(/^www\./, "");
    if (!host || SITE_HOSTS.has(host) || SITE_HOSTS.has(`www.${host}`))
      return null;
    return host.slice(0, 100);
  } catch {
    return null;
  }
}

const cleanUtm = (v: unknown, max: number) => {
  const s = clip(v, max);
  return s
    ? s
        .toLowerCase()
        .replace(/[^a-z0-9 ._-]/g, "")
        .slice(0, max) || null
    : null;
};

export function countryOf(
  header: string | string[] | undefined,
): string | null {
  const c = (Array.isArray(header) ? header[0] : header)?.trim().toUpperCase();
  return c && /^[A-Z]{2}$/.test(c) && c !== "XX" && c !== "T1" ? c : null;
}

export type WebEventInput = {
  kind: unknown;
  path: unknown;
  target?: unknown;
  referrer?: unknown;
  utm_source?: unknown;
  utm_medium?: unknown;
  utm_campaign?: unknown;
};

/**
 * Records one event; false (and nothing written) when it isn't a real
 * visitor's view or click: a bot, an unknown kind, a path that isn't ours,
 * or a click without a label.
 */
export async function recordWebEvent(
  input: WebEventInput,
  ctx: {
    ip: string | null;
    userAgent: string | undefined;
    country: string | null;
  },
): Promise<boolean> {
  if (isBot(ctx.userAgent)) return false;
  const kind = WEB_EVENT_KINDS.find((k) => k === input.kind);
  const path = cleanPath(input.path);
  if (!kind || !path) return false;
  const target = kind === "click" ? cleanTarget(input.target) : null;
  if (kind === "click" && !target) return false;
  const ua = ctx.userAgent!;
  // No trustworthy IP (a misconfigured proxy): fall back to the user agent
  // alone, which under-counts visitors rather than inventing them.
  const visitor = visitorHash(ctx.ip ?? "unknown", ua);
  await db.query(
    `INSERT INTO web_events
       (kind, path, target, referrer_host, utm_source, utm_medium, utm_campaign, visitor, device, country)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
    [
      kind,
      path,
      target,
      kind === "view" ? referrerHost(input.referrer) : null,
      kind === "view" ? cleanUtm(input.utm_source, 60) : null,
      kind === "view" ? cleanUtm(input.utm_medium, 60) : null,
      kind === "view" ? cleanUtm(input.utm_campaign, 80) : null,
      visitor,
      deviceOf(ua),
      ctx.country,
    ],
  );
  return true;
}

// ---------------------------------------------------------------------------
// Admin read: bounded aggregates over one window, TTL-cached like every other
// admin panel. A "visit" is one visitor on one day (the hash rotates daily),
// so visits over a window are the sum of each day's unique visitors.
// ---------------------------------------------------------------------------

type Totals = {
  views: number;
  visits: number;
  clicks: number;
  store_taps: number;
  store_visits: number;
  bounced: number;
  views_per_visit: number;
};

export type WebAnalytics = {
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

const num = (v: unknown) => Number(v ?? 0);

const TOTALS_SQL = `
  WITH v AS (
    SELECT visitor,
           count(*) FILTER (WHERE kind = 'view') AS views,
           count(*) FILTER (WHERE kind = 'click') AS clicks,
           count(*) FILTER (WHERE kind = 'click' AND target LIKE $3) AS store
      FROM web_events
     WHERE created_at >= $1 AND created_at < $2
     GROUP BY visitor
  )
  SELECT coalesce(sum(views), 0) AS views,
         count(*) FILTER (WHERE views > 0) AS visits,
         coalesce(sum(clicks), 0) AS clicks,
         coalesce(sum(store), 0) AS store_taps,
         count(*) FILTER (WHERE store > 0) AS store_visits,
         count(*) FILTER (WHERE views = 1 AND clicks = 0) AS bounced
    FROM v`;

async function totalsBetween(from: Date, to: Date): Promise<Totals> {
  const rows = await db.query(TOTALS_SQL, [
    from.toISOString(),
    to.toISOString(),
    APP_STORE_LIKE,
  ]);
  const r = rows[0] ?? {};
  const views = num(r.views);
  const visits = num(r.visits);
  return {
    views,
    visits,
    clicks: num(r.clicks),
    store_taps: num(r.store_taps),
    store_visits: num(r.store_visits),
    bounced: num(r.bounced),
    views_per_visit: visits ? Math.round((views / visits) * 100) / 100 : 0,
  };
}

async function loadWebAnalytics(days: number): Promise<WebAnalytics> {
  const now = new Date();
  const from = new Date(now.getTime() - days * 86_400_000);
  const priorFrom = new Date(from.getTime() - days * 86_400_000);
  // The current window is open-ended: rows are stamped in microseconds and
  // `now` here is milliseconds, so a bound at `now` would drop the newest
  // events. The prior window closes exactly where this one opens.
  const until = new Date(now.getTime() + 60_000);
  const range = [from.toISOString(), until.toISOString()];

  const [
    totals,
    prior,
    series,
    hours,
    pages,
    referrers,
    campaigns,
    clicks,
    storeByPage,
    devices,
    countries,
    live,
  ] = await Promise.all([
    totalsBetween(from, until),
    totalsBetween(priorFrom, from),
    db.query(
      `SELECT to_char((created_at AT TIME ZONE '${TZ}')::date, 'YYYY-MM-DD') AS date,
                count(*) FILTER (WHERE kind = 'view') AS views,
                count(DISTINCT visitor) FILTER (WHERE kind = 'view') AS visits,
                count(*) FILTER (WHERE kind = 'click' AND target LIKE $3) AS store_taps
           FROM web_events WHERE created_at >= $1 AND created_at < $2
          GROUP BY 1 ORDER BY 1`,
      [...range, APP_STORE_LIKE],
    ),
    db.query(
      `SELECT extract(hour FROM created_at AT TIME ZONE '${TZ}')::int AS hour, count(*) AS views
           FROM web_events WHERE kind = 'view' AND created_at >= $1 AND created_at < $2
          GROUP BY 1 ORDER BY 1`,
      range,
    ),
    db.query(
      `SELECT path, count(*) AS views, count(DISTINCT visitor) AS visits
           FROM web_events WHERE kind = 'view' AND created_at >= $1 AND created_at < $2
          GROUP BY path ORDER BY views DESC, path LIMIT 15`,
      range,
    ),
    // A visit's source is its FIRST view's referrer (later pages are internal).
    db.query(
      `WITH firsts AS (
           SELECT DISTINCT ON (visitor) visitor, referrer_host
             FROM web_events WHERE kind = 'view' AND created_at >= $1 AND created_at < $2
            ORDER BY visitor, created_at
         )
         SELECT coalesce(referrer_host, 'Direct') AS source, count(*) AS visits
           FROM firsts GROUP BY 1 ORDER BY visits DESC, source LIMIT 12`,
      range,
    ),
    db.query(
      `SELECT utm_source AS source, utm_medium AS medium, utm_campaign AS campaign,
                count(DISTINCT visitor) AS visits
           FROM web_events
          WHERE kind = 'view' AND utm_source IS NOT NULL AND created_at >= $1 AND created_at < $2
          GROUP BY 1, 2, 3 ORDER BY visits DESC LIMIT 12`,
      range,
    ),
    db.query(
      `SELECT target, count(*) AS clicks, count(DISTINCT visitor) AS visits
           FROM web_events WHERE kind = 'click' AND created_at >= $1 AND created_at < $2
          GROUP BY target ORDER BY clicks DESC, target LIMIT 15`,
      range,
    ),
    db.query(
      `SELECT path, count(*) AS taps
           FROM web_events WHERE kind = 'click' AND target LIKE $3 AND created_at >= $1 AND created_at < $2
          GROUP BY path ORDER BY taps DESC, path LIMIT 10`,
      [...range, APP_STORE_LIKE],
    ),
    db.query(
      `SELECT coalesce(device, 'unknown') AS device, count(DISTINCT visitor) AS visits
           FROM web_events WHERE created_at >= $1 AND created_at < $2
          GROUP BY 1 ORDER BY visits DESC`,
      range,
    ),
    db.query(
      `SELECT country, count(DISTINCT visitor) AS visits
           FROM web_events WHERE country IS NOT NULL AND created_at >= $1 AND created_at < $2
          GROUP BY 1 ORDER BY visits DESC LIMIT 10`,
      range,
    ),
    db.query(
      `SELECT path, count(DISTINCT visitor) AS visitors
           FROM web_events WHERE created_at >= now() - interval '5 minutes'
          GROUP BY path ORDER BY visitors DESC LIMIT 5`,
    ),
  ]);

  const liveVisitors = await db.query(
    `SELECT count(DISTINCT visitor) AS n FROM web_events WHERE created_at >= now() - interval '5 minutes'`,
  );

  return {
    days,
    generated_at: now.toISOString(),
    live_visitors: num(liveVisitors[0]?.n),
    live_pages: live.map((r: any) => ({
      path: r.path,
      visitors: num(r.visitors),
    })),
    totals,
    prior,
    series: series.map((r: any) => ({
      date: r.date,
      views: num(r.views),
      visits: num(r.visits),
      store_taps: num(r.store_taps),
    })),
    hours: hours.map((r: any) => ({ hour: num(r.hour), views: num(r.views) })),
    pages: pages.map((r: any) => ({
      path: r.path,
      views: num(r.views),
      visits: num(r.visits),
    })),
    referrers: referrers.map((r: any) => ({
      source: r.source,
      visits: num(r.visits),
    })),
    campaigns: campaigns.map((r: any) => ({
      source: r.source,
      medium: r.medium,
      campaign: r.campaign,
      visits: num(r.visits),
    })),
    clicks: clicks.map((r: any) => ({
      target: r.target,
      clicks: num(r.clicks),
      visits: num(r.visits),
    })),
    store_by_page: storeByPage.map((r: any) => ({
      path: r.path,
      taps: num(r.taps),
    })),
    devices: devices.map((r: any) => ({
      device: r.device,
      visits: num(r.visits),
    })),
    countries: countries.map((r: any) => ({
      country: r.country,
      visits: num(r.visits),
    })),
  };
}

const cache = new Map<number, { at: number; data: WebAnalytics }>();
const TTL_MS = 60_000;

/** Drop the cache. Only for scripts/web-analytics-check.mjs. */
export function resetWebAnalyticsCache(): void {
  cache.clear();
}

export async function getWebAnalytics(
  daysParam: unknown,
): Promise<WebAnalytics> {
  const asked = Number(daysParam);
  const days = (WEB_WINDOWS as readonly number[]).includes(asked) ? asked : 30;
  const hit = cache.get(days);
  if (hit && Date.now() - hit.at < TTL_MS) return hit.data;
  const data = await loadWebAnalytics(days);
  cache.set(days, { at: Date.now(), data });
  return data;
}
