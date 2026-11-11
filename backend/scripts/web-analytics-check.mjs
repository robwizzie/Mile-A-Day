/**
 * Website analytics check: POST /public/web-events (recordWebEvent) and the
 * admin Website tab (getWebAnalytics).
 *
 * The table is written by an UNAUTHENTICATED endpoint and read as numbers
 * people act on, so both halves are pinned:
 *   - anonymity: the visitor id is a hash that is stable within a UTC day,
 *     different the next day, and never contains the IP
 *   - what is dropped: bots, unknown kinds, foreign paths, unlabelled clicks;
 *     our own pages are never a referrer; queries never reach `path`
 *   - the aggregates, as DELTAS (CI runs other checks against the same DB):
 *     views, visits (one visitor = one visit a day), App Store taps, bounce,
 *     a visit's source = its FIRST view's referrer
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/web-analytics-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import {
  visitorHash,
  isBot,
  deviceOf,
  cleanPath,
  cleanTarget,
  referrerHost,
  countryOf,
  recordWebEvent,
  getWebAnalytics,
  resetWebAnalyticsCache,
  APP_STORE_TARGET,
} from "../dist/services/webAnalyticsService.js";

const db = PostgresService.getInstance();
const PREFIX = "/__web-analytics-check";

let failures = 0;
function check(label, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  const ok = a === e;
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${a}${ok ? "" : ` (expected ${e})`}`,
  );
}

const IPHONE =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148";
const MAC =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Safari/605.1.15";

// ─── Pure ────────────────────────────────────────────────────────────────
{
  const d1 = new Date("2026-11-10T12:00:00Z");
  const d1b = new Date("2026-11-10T23:59:00Z");
  const d2 = new Date("2026-11-11T00:01:00Z");
  const h = visitorHash("203.0.113.9", IPHONE, d1);
  check(
    "visitor stable within a UTC day",
    h === visitorHash("203.0.113.9", IPHONE, d1b),
    true,
  );
  check(
    "visitor changes the next day",
    h === visitorHash("203.0.113.9", IPHONE, d2),
    false,
  );
  check(
    "visitor never carries the IP",
    h.includes("203") || h.includes("113"),
    false,
  );
  check(
    "visitor differs by browser",
    h === visitorHash("203.0.113.9", MAC, d1),
    false,
  );

  check(
    "bot UA dropped",
    isBot("Mozilla/5.0 (compatible; Googlebot/2.1)"),
    true,
  );
  check("link preview dropped", isBot("facebookexternalhit/1.1"), true);
  check("missing UA dropped", isBot(undefined), true);
  check("real browser kept", isBot(IPHONE), false);
  check("iPhone = mobile", deviceOf(IPHONE), "mobile");
  check("Mac = desktop", deviceOf(MAC), "desktop");
  check(
    "iPad = tablet",
    deviceOf("Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X)"),
    "tablet",
  );

  check(
    "path keeps no query or hash",
    cleanPath("/u/rob?ref=dave#medals"),
    "/u/rob",
  );
  check("foreign url is not a path", cleanPath("https://evil.example/x"), null);
  check(
    "target strips markup",
    cleanTarget("<b>App Store</b>"),
    "bApp Store/b",
  );
  check(
    "own site is not a referrer",
    referrerHost("https://www.mileaday.run/updates"),
    null,
  );
  check(
    "referrer is a bare host",
    referrerHost("https://www.instagram.com/p/abc?x=1"),
    "instagram.com",
  );
  check("junk referrer dropped", referrerHost("not a url"), null);
  check("country header kept", countryOf("us"), "US");
  check("unknown country dropped", countryOf("XX"), null);
}

// ─── DB: deltas ──────────────────────────────────────────────────────────
async function cleanup() {
  await db.query(`DELETE FROM web_events WHERE path LIKE $1`, [`${PREFIX}%`]);
}

async function snap() {
  resetWebAnalyticsCache();
  return getWebAnalytics(1);
}

const ctx = (ip, ua = IPHONE) => ({ ip, userAgent: ua, country: "US" });

try {
  await cleanup();
  const before = await snap();

  // Visitor A: lands from Instagram via a campaign, reads two pages, taps the App Store.
  check(
    "A lands",
    await recordWebEvent(
      {
        kind: "view",
        path: `${PREFIX}/home`,
        referrer: "https://instagram.com/x",
        utm_source: "Instagram",
        utm_campaign: "launch",
      },
      ctx("198.51.100.1"),
    ),
    true,
  );
  await recordWebEvent(
    {
      kind: "view",
      path: `${PREFIX}/updates`,
      referrer: "https://mileaday.run/",
    },
    ctx("198.51.100.1"),
  );
  await recordWebEvent(
    { kind: "click", path: `${PREFIX}/updates`, target: APP_STORE_TARGET },
    ctx("198.51.100.1"),
  );
  // Visitor B: one page, nothing else (a bounce), on a Mac.
  await recordWebEvent(
    { kind: "view", path: `${PREFIX}/home` },
    ctx("198.51.100.2", MAC),
  );
  // Dropped: a bot, an unknown kind, an unlabelled click, a foreign path.
  check(
    "bot view dropped",
    await recordWebEvent(
      { kind: "view", path: `${PREFIX}/home` },
      ctx("198.51.100.3", "Googlebot/2.1"),
    ),
    false,
  );
  check(
    "unknown kind dropped",
    await recordWebEvent(
      { kind: "purchase", path: `${PREFIX}/home` },
      ctx("198.51.100.3"),
    ),
    false,
  );
  check(
    "unlabelled click dropped",
    await recordWebEvent(
      { kind: "click", path: `${PREFIX}/home` },
      ctx("198.51.100.3"),
    ),
    false,
  );
  check(
    "foreign path dropped",
    await recordWebEvent(
      { kind: "view", path: "https://x.example/" },
      ctx("198.51.100.3"),
    ),
    false,
  );

  const after = await snap();
  const d = (k) => after.totals[k] - before.totals[k];
  check("views +3", d("views"), 3);
  check("visits +2", d("visits"), 2);
  check("clicks +1", d("clicks"), 1);
  check("App Store taps +1", d("store_taps"), 1);
  check("visits that tapped the App Store +1", d("store_visits"), 1);
  check("bounced +1 (B only)", d("bounced"), 1);

  const page = after.pages.find((p) => p.path === `${PREFIX}/home`);
  check(
    "home page: 2 views by 2 visitors",
    page && [page.views, page.visits],
    [2, 2],
  );
  const ig = after.referrers.find((r) => r.source === "instagram.com");
  const igBefore = before.referrers.find((r) => r.source === "instagram.com");
  check(
    "Instagram visits +1 (first view's referrer)",
    (ig?.visits ?? 0) - (igBefore?.visits ?? 0),
    1,
  );
  check(
    "campaign recorded lower-case",
    after.campaigns.some(
      (c) => c.source === "instagram" && c.campaign === "launch",
    ),
    true,
  );
  check(
    "App Store tap credited to its page",
    after.store_by_page.some(
      (p) => p.path === `${PREFIX}/updates` && p.taps >= 1,
    ),
    true,
  );
  check(
    "live visitors counts them",
    after.live_visitors - before.live_visitors >= 2,
    true,
  );
  const stored = await db.query(
    `SELECT count(*)::int AS n FROM web_events WHERE path LIKE $1 AND visitor LIKE '%198.51%'`,
    [`${PREFIX}%`],
  );
  check("no IP stored anywhere in visitor", stored[0].n, 0);
  check(
    "a bad window falls back to 30 days",
    (await getWebAnalytics("365")).days,
    30,
  );
} finally {
  await cleanup();
}

if (failures) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log("\nweb analytics check passed");
process.exit(0);
